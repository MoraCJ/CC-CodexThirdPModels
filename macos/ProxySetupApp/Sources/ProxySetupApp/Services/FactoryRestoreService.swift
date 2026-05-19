import Foundation

struct FactoryRestoreConfirmation: Equatable {
    var reviewedBackups = false
    var understandsOfficialDefaults = false
    var typedPhrase = ""

    var canProceed: Bool {
        reviewedBackups &&
            understandsOfficialDefaults &&
            typedPhrase == "RESTORE"
    }
}

struct FactoryRestoreResult: Equatable {
    var backupResult: BackupResult
    var commandRecords: [InstallationCommandRecord]
}

struct FactoryRestoreService {
    var label = "com.cj.claude-local-https-proxy"
    private let claudeDesktopConfigID = ClientConfigEnvironment.claudeDesktopConfigID
    private let legacyClaudeDesktopConfigID = "cj-local-proxy"

    func restore(
        config: SetupConfiguration,
        environment: InstallationEnvironment = .defaultEnvironment(),
        clientConfigEnvironment: ClientConfigEnvironment? = nil,
        confirmation: FactoryRestoreConfirmation,
        runner: CommandRunning = CommandRunner(),
        timestamp: String = InstallationExecutionService.timestamp(),
        progress: InstallationProgressHandler? = nil
    ) async throws -> FactoryRestoreResult {
        guard confirmation.canProceed else {
            throw FactoryRestoreError.confirmationRequired
        }

        await emit(
            title: "备份现有配置 / Backup current files",
            detail: "正在备份 Claude、Codex 和 LaunchAgent 配置",
            status: .running,
            progress: progress
        )
        let launchAgentURL = environment.launchAgentDirectory
            .appendingPathComponent("\(label).plist")
        let resolvedClientConfigEnvironment = clientConfigEnvironment ?? ClientConfigEnvironment.defaultEnvironment(
            claudeDesktopSupportDirectoryName: config.claudeDesktopSupportDirectoryName
        )
        let changes = restoreTargets(
            clientConfigEnvironment: resolvedClientConfigEnvironment,
            launchAgentURL: launchAgentURL
        )
        let backupDirectory = environment.installRoot
            .appendingPathComponent("backups", isDirectory: true)
            .appendingPathComponent("restore-\(timestamp)", isDirectory: true)
        let backupResult = try InstallationSafetyService().createBackups(
            for: changes,
            backupDirectory: backupDirectory,
            timestamp: timestamp
        )
        await emit(
            title: "备份现有配置 / Backup current files",
            detail: backupResult.manifestURL.path,
            status: .succeeded,
            progress: progress
        )

        var commandRecords: [InstallationCommandRecord] = []
        let launchCommands = LaunchAgentService(label: label).controlCommands(
            plistURL: launchAgentURL,
            userID: environment.userID
        )
        await emit(
            title: "Stop LaunchAgent",
            detail: launchCommands.bootout.joined(separator: " "),
            status: .running,
            command: launchCommands.bootout,
            progress: progress
        )
        let stopRecord = await run(
            title: "Stop LaunchAgent",
            command: launchCommands.bootout,
            runner: runner,
            records: &commandRecords
        )
        await emit(
            title: "Stop LaunchAgent",
            detail: stopRecord.succeeded
                ? "完成 / Done"
                : "LaunchAgent 可能未加载，继续还原配置 / LaunchAgent may not be loaded",
            status: stopRecord.succeeded ? .succeeded : .skipped,
            command: launchCommands.bootout,
            progress: progress
        )

        await emit(
            title: "还原客户端配置 / Restore client configs",
            detail: "正在移除本机代理片段",
            status: .running,
            progress: progress
        )
        try restoreClaudeCLISettings(at: resolvedClientConfigEnvironment.claudeSettingsURL)
        try removeIfExists(resolvedClientConfigEnvironment.claudeDesktopGatewayURL)
        try removeIfExists(legacyClaudeDesktopGatewayURL(from: resolvedClientConfigEnvironment))
        try restoreClaudeDesktopMeta(at: resolvedClientConfigEnvironment.claudeDesktopMetaURL)
        try restoreClaudeDesktopMode(at: resolvedClientConfigEnvironment.claudeDesktopModeURL)
        try restoreCodexConfig(
            at: resolvedClientConfigEnvironment.codexConfigURL,
            profileNames: config.codexProfiles.map(\.name)
        )
        try removeIfExists(launchAgentURL)
        await emit(
            title: "还原客户端配置 / Restore client configs",
            detail: "Claude 与 Codex 已恢复官方默认服务",
            status: .succeeded,
            progress: progress
        )

        return FactoryRestoreResult(
            backupResult: backupResult,
            commandRecords: commandRecords
        )
    }

    enum FactoryRestoreError: LocalizedError, Equatable {
        case confirmationRequired
        case invalidJSON(String)

        var errorDescription: String? {
            switch self {
            case .confirmationRequired:
                return "恢复前必须确认已备份、理解会回到官方服务，并输入 RESTORE。"
            case .invalidJSON(let path):
                return "配置文件不是可安全修改的 JSON：\(path)"
            }
        }
    }

    private func restoreTargets(
        clientConfigEnvironment: ClientConfigEnvironment,
        launchAgentURL: URL
    ) -> [ManagedFileChange] {
        var targets = [
            ManagedFileChange(
                title: "Claude CLI settings restore",
                targetURL: clientConfigEnvironment.claudeSettingsURL,
                proposedContents: ""
            ),
            ManagedFileChange(
                title: "Claude Desktop gateway restore",
                targetURL: clientConfigEnvironment.claudeDesktopGatewayURL,
                proposedContents: ""
            ),
        ]

        let legacyGatewayURL = legacyClaudeDesktopGatewayURL(from: clientConfigEnvironment)
        if legacyGatewayURL != clientConfigEnvironment.claudeDesktopGatewayURL {
            targets.append(
                ManagedFileChange(
                    title: "Claude Desktop legacy gateway restore",
                    targetURL: legacyGatewayURL,
                    proposedContents: ""
                )
            )
        }

        targets.append(contentsOf: [
            ManagedFileChange(
                title: "Claude Desktop config library meta restore",
                targetURL: clientConfigEnvironment.claudeDesktopMetaURL,
                proposedContents: ""
            ),
            ManagedFileChange(
                title: "Claude Desktop deployment mode restore",
                targetURL: clientConfigEnvironment.claudeDesktopModeURL,
                proposedContents: ""
            ),
            ManagedFileChange(
                title: "Codex config restore",
                targetURL: clientConfigEnvironment.codexConfigURL,
                proposedContents: ""
            ),
            ManagedFileChange(
                title: "LaunchAgent plist restore",
                targetURL: launchAgentURL,
                proposedContents: ""
            ),
        ])
        return targets
    }

    private func restoreClaudeCLISettings(at url: URL) throws {
        guard var object = try readJSONDictionary(at: url) else { return }
        let managedEnvKeys: Set<String> = [
            "ANTHROPIC_BASE_URL",
            "ANTHROPIC_AUTH_TOKEN",
            "ANTHROPIC_DEFAULT_OPUS_MODEL",
            "ANTHROPIC_DEFAULT_SONNET_MODEL",
            "ANTHROPIC_DEFAULT_HAIKU_MODEL",
            "NODE_USE_SYSTEM_CA",
            "NODE_EXTRA_CA_CERTS",
            "SSL_CERT_FILE",
        ]

        if var env = object["env"] as? [String: Any] {
            for key in managedEnvKeys {
                env.removeValue(forKey: key)
            }
            if env.isEmpty {
                object.removeValue(forKey: "env")
            } else {
                object["env"] = env
            }
        }

        try writeJSONOrRemoveIfEmpty(object, to: url)
    }

    private func restoreClaudeDesktopMeta(at url: URL) throws {
        guard var object = try readJSONDictionary(at: url) else { return }

        let managedIDs = [claudeDesktopConfigID, legacyClaudeDesktopConfigID]
        if managedIDs.contains(object["appliedId"] as? String ?? "") {
            object.removeValue(forKey: "appliedId")
        }

        if var configs = object["configs"] as? [[String: Any]] {
            configs.removeAll { managedIDs.contains($0["id"] as? String ?? "") }
            if configs.isEmpty {
                object.removeValue(forKey: "configs")
            } else {
                object["configs"] = configs
            }
        }

        if var entries = object["entries"] as? [[String: Any]] {
            entries.removeAll { managedIDs.contains($0["id"] as? String ?? "") }
            if entries.isEmpty {
                object.removeValue(forKey: "entries")
            } else {
                object["entries"] = entries
            }
        }

        try writeJSONOrRemoveIfEmpty(object, to: url)
    }

    private func legacyClaudeDesktopGatewayURL(from environment: ClientConfigEnvironment) -> URL {
        environment.claudeDesktopGatewayURL
            .deletingLastPathComponent()
            .appendingPathComponent("\(legacyClaudeDesktopConfigID).json")
    }

    private func restoreClaudeDesktopMode(at url: URL) throws {
        guard var object = try readJSONDictionary(at: url) else { return }

        if object["deploymentMode"] as? String == "3p" {
            object.removeValue(forKey: "deploymentMode")
        }

        try writeJSONOrRemoveIfEmpty(object, to: url)
    }

    private func restoreCodexConfig(at url: URL, profileNames: [String]) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let current = try String(contentsOf: url, encoding: .utf8)
        let restored = restoreCodexConfigText(current, profileNames: profileNames)

        guard let restored, !restored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            try removeIfExists(url)
            return
        }

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try restored.write(to: url, atomically: true, encoding: .utf8)
    }

    private func restoreCodexConfigText(_ text: String, profileNames: [String]) -> String? {
        let hasManagedTopLevelProvider = hasManagedCodexTopLevelProvider(in: text)
        let managedTopLevelKeys: Set<String> = [
            "model_provider",
            "model",
            "model_reasoning_effort",
            "disable_response_storage",
        ]
        let managedSections = Set(
            ["model_providers.ark-coding-app", "model_providers.ark-coding-cli"] +
                profileNames.map { "profiles.\(tomlBareKey($0))" }
        )

        var keptLines: [String] = []
        var currentSection: String?
        var skippingSection = false

        for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let section = sectionName(from: trimmed) {
                currentSection = section
                skippingSection = managedSections.contains(section)
                if skippingSection {
                    continue
                }
                keptLines.append(line)
                continue
            }

            if skippingSection {
                continue
            }

            if currentSection == nil,
               let key = topLevelKey(from: trimmed),
               managedTopLevelKeys.contains(key),
               shouldRemoveCodexTopLevelLine(trimmed, key: key, hasManagedTopLevelProvider: hasManagedTopLevelProvider) {
                continue
            }

            keptLines.append(line)
        }

        let compact = collapseBlankLines(keptLines)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return compact.isEmpty ? nil : compact + "\n"
    }

    private func readJSONDictionary(at url: URL) throws -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return nil }
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            throw FactoryRestoreError.invalidJSON(url.path)
        }
        return dictionary
    }

    private func writeJSONOrRemoveIfEmpty(_ object: [String: Any], to url: URL) throws {
        guard !object.isEmpty else {
            try removeIfExists(url)
            return
        }

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: url, options: .atomic)
    }

    private func removeIfExists(_ url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func sectionName(from trimmedLine: String) -> String? {
        guard trimmedLine.hasPrefix("["),
              trimmedLine.hasSuffix("]"),
              trimmedLine.count >= 2 else {
            return nil
        }
        return String(trimmedLine.dropFirst().dropLast())
    }

    private func topLevelKey(from trimmedLine: String) -> String? {
        guard let equals = trimmedLine.firstIndex(of: "=") else { return nil }
        return String(trimmedLine[..<equals]).trimmingCharacters(in: .whitespaces)
    }

    private func topLevelValue(from trimmedLine: String) -> String? {
        guard let equals = trimmedLine.firstIndex(of: "=") else { return nil }
        return String(trimmedLine[trimmedLine.index(after: equals)...])
            .trimmingCharacters(in: .whitespaces)
    }

    private func hasManagedCodexTopLevelProvider(in text: String) -> Bool {
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if sectionName(from: trimmed) != nil {
                return false
            }
            guard topLevelKey(from: trimmed) == "model_provider",
                  let value = topLevelValue(from: trimmed) else {
                continue
            }
            return value.contains("ark-coding-app") || value.contains("ark-coding-cli")
        }
        return false
    }

    private func shouldRemoveCodexTopLevelLine(
        _ trimmedLine: String,
        key: String,
        hasManagedTopLevelProvider: Bool
    ) -> Bool {
        if key == "model_provider" {
            guard let value = topLevelValue(from: trimmedLine) else { return false }
            return value.contains("ark-coding-app") || value.contains("ark-coding-cli")
        }
        return hasManagedTopLevelProvider
    }

    private func collapseBlankLines(_ lines: [String]) -> [String] {
        var result: [String] = []
        var previousWasBlank = false

        for line in lines {
            let isBlank = line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if isBlank, previousWasBlank {
                continue
            }
            result.append(line)
            previousWasBlank = isBlank
        }

        return result
    }

    private func tomlBareKey(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
        if value.unicodeScalars.allSatisfy({ allowed.contains($0) }), !value.isEmpty {
            return value
        }
        return "\"\(tomlString(value))\""
    }

    private func tomlString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
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

    private func emit(
        title: String,
        detail: String,
        status: InstallationProgressStatus,
        command: [String] = [],
        progress: InstallationProgressHandler?
    ) async {
        await progress?(
            InstallationProgressEvent(
                title: title,
                detail: detail,
                status: status,
                command: command
            )
        )
    }
}
