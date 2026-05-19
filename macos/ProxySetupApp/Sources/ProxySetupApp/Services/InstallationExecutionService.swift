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

enum InstallationProgressStatus: String, Equatable {
    case running
    case succeeded
    case failed
    case skipped
}

struct InstallationProgressEvent: Identifiable, Equatable {
    var id = UUID()
    var title: String
    var detail: String
    var status: InstallationProgressStatus
    var command: [String] = []
    var elapsedSeconds: TimeInterval?

    static func == (lhs: InstallationProgressEvent, rhs: InstallationProgressEvent) -> Bool {
        lhs.title == rhs.title &&
            lhs.detail == rhs.detail &&
            lhs.status == rhs.status &&
            lhs.command == rhs.command &&
            lhs.elapsedSeconds == rhs.elapsedSeconds
    }
}

typealias InstallationProgressHandler = (InstallationProgressEvent) async -> Void

struct InstallationExecutionResult: Equatable {
    var backupResult: BackupResult
    var localInstallationResult: LocalInstallationResult
    var commandRecords: [InstallationCommandRecord]
    var verificationSummary: VerificationSummary
}

struct InstallationExecutionService {
    var label = "com.cj.claude-local-https-proxy"
    var commandTimeoutSeconds: TimeInterval = 30

    func execute(
        config: SetupConfiguration,
        environment: InstallationEnvironment = .defaultEnvironment(),
        clientConfigEnvironment: ClientConfigEnvironment = .defaultEnvironment(),
        confirmation: InstallationConfirmation,
        runner: CommandRunning = CommandRunner(),
        timestamp: String = InstallationExecutionService.timestamp(),
        proxySourceDirectory: URL? = nil,
        progress: InstallationProgressHandler? = nil
    ) async throws -> InstallationExecutionResult {
        guard confirmation.canProceed else {
            throw InstallationError.confirmationRequired
        }

        var resolvedEnvironment = environment
        if resolvedEnvironment.nodePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            await emit(
                title: "探测依赖 / Check dependencies",
                detail: "正在查找 node/npm/brew/claude/codex",
                status: .running,
                progress: progress
            )
            let tools = await PreflightService(runner: runner).checkTools()
            guard tools.requiredToolsReady else {
                await emit(
                    title: "探测依赖 / Check dependencies",
                    detail: "未找到必需的 node，请先安装 Node.js。",
                    status: .failed,
                    progress: progress
                )
                throw InstallationError.requiredToolMissing("node")
            }
            resolvedEnvironment.nodePath = tools.node.path
            await emit(
                title: "探测依赖 / Check dependencies",
                detail: "Node: \(tools.node.path) \(tools.node.version)",
                status: .succeeded,
                progress: progress
            )
        } else {
            await emit(
                title: "探测依赖 / Check dependencies",
                detail: "使用已解析 Node: \(resolvedEnvironment.nodePath)",
                status: .succeeded,
                progress: progress
            )
        }

        try config.validate()

        let localService = LocalInstallationService(label: label)
        let localChanges = try localService.managedFileChanges(config: config, environment: resolvedEnvironment)
        let clientChanges = try ClientConfigService().managedClientConfigChanges(
            config: config,
            environment: clientConfigEnvironment
        )
        let managedChanges = localChanges + clientChanges

        await emit(
            title: "备份配置 / Create backups",
            detail: "正在备份将被修改的配置文件",
            status: .running,
            progress: progress
        )
        let backupDirectory = resolvedEnvironment.installRoot
            .appendingPathComponent("backups", isDirectory: true)
            .appendingPathComponent("install-\(timestamp)", isDirectory: true)
        let backupResult = try InstallationSafetyService().createBackups(
            for: managedChanges,
            backupDirectory: backupDirectory,
            timestamp: timestamp
        )
        await emit(
            title: "备份配置 / Create backups",
            detail: backupResult.manifestURL.path,
            status: .succeeded,
            progress: progress
        )

        await emit(
            title: "写入代理配置 / Write proxy files",
            detail: "正在复制代理文件并写入运行配置",
            status: .running,
            progress: progress
        )
        let localResult = try localService.prepareLocalFiles(
            config: config,
            environment: resolvedEnvironment,
            proxySourceDirectory: proxySourceDirectory
        )
        try write(changes: clientChanges)
        await emit(
            title: "写入代理配置 / Write proxy files",
            detail: localResult.installRoot.path,
            status: .succeeded,
            progress: progress
        )

        var commandRecords: [InstallationCommandRecord] = []
        let certsDirectory = localResult.proxyDirectory.appendingPathComponent("certs", isDirectory: true)
        if shouldGenerateCertificates(in: certsDirectory) {
            for command in CertificateService().generationCommands(certsDirectory: certsDirectory) {
                try await runRequired(
                    title: "Generate certificate",
                    command: command,
                    runner: runner,
                    records: &commandRecords,
                    progress: progress
                )
            }
        } else {
            await emit(
                title: "Generate certificate",
                detail: "证书已存在，跳过生成 / Certificate files already exist",
                status: .skipped,
                progress: progress
            )
        }

        try await runRequired(
            title: "Trust local CA",
            command: localResult.trustCommand,
            runner: runner,
            records: &commandRecords,
            progress: progress
        )

        _ = await run(
            title: "Stop existing LaunchAgent",
            command: localResult.launchCommands.bootout,
            runner: runner,
            records: &commandRecords,
            progress: progress
        )
        try await runRequired(
            title: "Bootstrap LaunchAgent",
            command: localResult.launchCommands.bootstrap,
            runner: runner,
            records: &commandRecords,
            progress: progress
        )
        try await runRequired(
            title: "Start LaunchAgent",
            command: localResult.launchCommands.kickstart,
            runner: runner,
            records: &commandRecords,
            progress: progress
        )
        try await runRequired(
            title: "Check LaunchAgent",
            command: localResult.launchCommands.printStatus,
            runner: runner,
            records: &commandRecords,
            progress: progress
        )

        await emit(
            title: "验证端点 / Verify endpoints",
            detail: "正在检查代理健康状态和 dashboard",
            status: .running,
            progress: progress
        )
        let verificationSummary = await VerificationService().run(
            config: config,
            runner: runner,
            progress: { event in
                await progress?(
                    InstallationProgressEvent(
                        title: "验证端点 / Verify endpoints",
                        detail: "\(event.name): \(event.detail)",
                        status: event.status.installationStatus
                    )
                )
            }
        )
        await emit(
            title: "验证端点 / Verify endpoints",
            detail: verificationSummary.isPassing ? "全部端点验证通过" : "部分端点验证失败",
            status: verificationSummary.isPassing ? .succeeded : .failed,
            progress: progress
        )
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
        case requiredToolMissing(String)

        var errorDescription: String? {
            switch self {
            case .confirmationRequired:
                return "安装前必须完成 dry-run、备份、系统变更确认，并输入 INSTALL。"
            case .commandFailed:
                return "安装命令执行失败，请查看命令日志。"
            case .requiredToolMissing(let name):
                return "缺少必需依赖：\(name)。请先安装或修正 PATH 后再重试。"
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
        records: inout [InstallationCommandRecord],
        progress: InstallationProgressHandler?
    ) async throws -> InstallationCommandRecord {
        let record = await run(
            title: title,
            command: command,
            runner: runner,
            records: &records,
            progress: progress
        )
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
        records: inout [InstallationCommandRecord],
        progress: InstallationProgressHandler?
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
            await emit(
                title: title,
                detail: record.stderr,
                status: .failed,
                command: command,
                progress: progress
            )
            return record
        }
        await emit(
            title: title,
            detail: command.joined(separator: " "),
            status: .running,
            command: command,
            progress: progress
        )
        let startedAt = Date()
        let result: CommandResult
        if let timedRunner = runner as? TimedCommandRunning {
            result = await timedRunner.run(
                executable,
                Array(command.dropFirst()),
                timeoutSeconds: commandTimeoutSeconds
            )
        } else {
            result = await runner.run(executable, Array(command.dropFirst()))
        }
        let elapsed = Date().timeIntervalSince(startedAt)
        let record = InstallationCommandRecord(
            title: title,
            command: command,
            exitCode: result.exitCode,
            stdout: result.stdout,
            stderr: result.stderr
        )
        records.append(record)
        await emit(
            title: title,
            detail: record.succeeded
                ? "完成 / Done"
                : (result.timedOut ? "命令超时 / Command timed out" : "失败 / Failed"),
            status: record.succeeded ? .succeeded : .failed,
            command: command,
            elapsedSeconds: elapsed,
            progress: progress
        )
        return record
    }

    private func emit(
        title: String,
        detail: String,
        status: InstallationProgressStatus,
        command: [String] = [],
        elapsedSeconds: TimeInterval? = nil,
        progress: InstallationProgressHandler?
    ) async {
        await progress?(
            InstallationProgressEvent(
                title: title,
                detail: detail,
                status: status,
                command: command,
                elapsedSeconds: elapsedSeconds
            )
        )
    }

    static func timestamp(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMddHHmmss"
        return formatter.string(from: date)
    }
}

private extension VerificationProgressStatus {
    var installationStatus: InstallationProgressStatus {
        switch self {
        case .running:
            return .running
        case .passed:
            return .succeeded
        case .failed:
            return .failed
        }
    }
}
