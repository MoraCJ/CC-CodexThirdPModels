import Foundation

struct InstallationCommandRecord: Identifiable, Equatable {
    var id: String { "\(title):\(command.joined(separator: " "))" }
    var title: String
    var command: [String]
    var exitCode: Int32
    var stdout: String
    var stderr: String

    var succeeded: Bool {
        exitCode == 0
    }
}

struct InstallationExecutionResult: Equatable {
    var backupResult: BackupResult
    var localInstallationResult: LocalInstallationResult
    var commandRecords: [InstallationCommandRecord]
    var verificationSummary: VerificationSummary
}

struct InstallationExecutionService {
    var label = "com.cj.claude-local-https-proxy"

    func execute(
        config: SetupConfiguration,
        environment: InstallationEnvironment = .defaultEnvironment(),
        clientConfigEnvironment: ClientConfigEnvironment = .defaultEnvironment(),
        confirmation: InstallationConfirmation,
        runner: CommandRunning = CommandRunner(),
        timestamp: String = InstallationExecutionService.timestamp(),
        proxySourceDirectory: URL? = nil
    ) async throws -> InstallationExecutionResult {
        guard confirmation.canProceed else {
            throw InstallationError.confirmationRequired
        }

        try config.validate()

        let localService = LocalInstallationService(label: label)
        let localChanges = try localService.managedFileChanges(config: config, environment: environment)
        let clientChanges = try ClientConfigService().managedClientConfigChanges(
            config: config,
            environment: clientConfigEnvironment
        )
        let managedChanges = localChanges + clientChanges

        let backupDirectory = environment.installRoot
            .appendingPathComponent("backups", isDirectory: true)
            .appendingPathComponent("install-\(timestamp)", isDirectory: true)
        let backupResult = try InstallationSafetyService().createBackups(
            for: managedChanges,
            backupDirectory: backupDirectory,
            timestamp: timestamp
        )

        let localResult = try localService.prepareLocalFiles(
            config: config,
            environment: environment,
            proxySourceDirectory: proxySourceDirectory
        )
        try write(changes: clientChanges)

        var commandRecords: [InstallationCommandRecord] = []
        let certsDirectory = localResult.proxyDirectory.appendingPathComponent("certs", isDirectory: true)
        if shouldGenerateCertificates(in: certsDirectory) {
            for command in CertificateService().generationCommands(certsDirectory: certsDirectory) {
                try await runRequired(
                    title: "Generate certificate",
                    command: command,
                    runner: runner,
                    records: &commandRecords
                )
            }
        }

        try await runRequired(
            title: "Trust local CA",
            command: localResult.trustCommand,
            runner: runner,
            records: &commandRecords
        )

        _ = await run(
            title: "Stop existing LaunchAgent",
            command: localResult.launchCommands.bootout,
            runner: runner,
            records: &commandRecords
        )
        try await runRequired(
            title: "Bootstrap LaunchAgent",
            command: localResult.launchCommands.bootstrap,
            runner: runner,
            records: &commandRecords
        )
        try await runRequired(
            title: "Start LaunchAgent",
            command: localResult.launchCommands.kickstart,
            runner: runner,
            records: &commandRecords
        )
        try await runRequired(
            title: "Check LaunchAgent",
            command: localResult.launchCommands.printStatus,
            runner: runner,
            records: &commandRecords
        )

        let verificationSummary = await VerificationService().run(config: config, runner: runner)
        return InstallationExecutionResult(
            backupResult: backupResult,
            localInstallationResult: localResult,
            commandRecords: commandRecords,
            verificationSummary: verificationSummary
        )
    }

    enum InstallationError: LocalizedError, Equatable {
        case confirmationRequired
        case commandFailed

        var errorDescription: String? {
            switch self {
            case .confirmationRequired:
                return "安装前必须完成 dry-run、备份、系统变更确认，并输入 INSTALL。"
            case .commandFailed:
                return "安装命令执行失败，请查看命令日志。"
            }
        }
    }

    private func write(changes: [ManagedFileChange]) throws {
        let fileManager = FileManager.default
        for change in changes {
            try fileManager.createDirectory(
                at: change.targetURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try change.proposedContents.write(to: change.targetURL, atomically: true, encoding: .utf8)
        }
    }

    private func shouldGenerateCertificates(in certsDirectory: URL) -> Bool {
        let fileManager = FileManager.default
        return !fileManager.fileExists(atPath: certsDirectory.appendingPathComponent("ca.crt").path) ||
            !fileManager.fileExists(atPath: certsDirectory.appendingPathComponent("server.crt").path) ||
            !fileManager.fileExists(atPath: certsDirectory.appendingPathComponent("server.key").path)
    }

    @discardableResult
    private func runRequired(
        title: String,
        command: [String],
        runner: CommandRunning,
        records: inout [InstallationCommandRecord]
    ) async throws -> InstallationCommandRecord {
        let record = await run(title: title, command: command, runner: runner, records: &records)
        guard record.succeeded else {
            throw InstallationError.commandFailed
        }
        return record
    }

    @discardableResult
    private func run(
        title: String,
        command: [String],
        runner: CommandRunning,
        records: inout [InstallationCommandRecord]
    ) async -> InstallationCommandRecord {
        guard let executable = command.first else {
            let record = InstallationCommandRecord(
                title: title,
                command: command,
                exitCode: 127,
                stdout: "",
                stderr: "empty command"
            )
            records.append(record)
            return record
        }
        let result = await runner.run(executable, Array(command.dropFirst()))
        let record = InstallationCommandRecord(
            title: title,
            command: command,
            exitCode: result.exitCode,
            stdout: result.stdout,
            stderr: result.stderr
        )
        records.append(record)
        return record
    }

    static func timestamp(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMddHHmmss"
        return formatter.string(from: date)
    }
}
