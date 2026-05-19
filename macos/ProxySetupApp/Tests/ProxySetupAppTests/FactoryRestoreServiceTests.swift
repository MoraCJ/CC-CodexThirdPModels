import Foundation
import Testing
@testable import ProxySetupApp

struct FactoryRestoreServiceTests {
    @Test
    func restoreOfficialDefaultsRemovesOnlyManagedClientConfigAndLaunchAgent() async throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let installRoot = temp.appendingPathComponent("install")
        let launchAgents = temp.appendingPathComponent("LaunchAgents")
        let clientRoot = temp.appendingPathComponent("home")
        defer { try? FileManager.default.removeItem(at: temp) }

        let clientEnvironment = ClientConfigEnvironment(
            claudeSettingsURL: clientRoot.appendingPathComponent(".claude/settings.json"),
            claudeDesktopGatewayURL: clientRoot.appendingPathComponent("Claude-3p/configLibrary/\(ClientConfigEnvironment.claudeDesktopConfigID).json"),
            claudeDesktopMetaURL: clientRoot.appendingPathComponent("Claude-3p/configLibrary/_meta.json"),
            claudeDesktopModeURL: clientRoot.appendingPathComponent("Claude-3p/claude_desktop_config.json"),
            codexConfigURL: clientRoot.appendingPathComponent(".codex/config.toml")
        )
        let installEnvironment = InstallationEnvironment(
            installRoot: installRoot,
            launchAgentDirectory: launchAgents,
            nodePath: "/opt/homebrew/bin/node",
            userID: 501,
            loginKeychainPath: clientRoot.appendingPathComponent("login.keychain-db").path
        )

        try seedInstalledProxyFiles(
            clientEnvironment: clientEnvironment,
            installEnvironment: installEnvironment
        )

        var confirmation = FactoryRestoreConfirmation()
        confirmation.reviewedBackups = true
        confirmation.understandsOfficialDefaults = true
        confirmation.typedPhrase = "RESTORE"

        let runner = RestoreRecordingCommandRunner()
        let result = try await FactoryRestoreService(label: "com.cj.proxy").restore(
            config: .default,
            environment: installEnvironment,
            clientConfigEnvironment: clientEnvironment,
            confirmation: confirmation,
            runner: runner,
            timestamp: "20260519101010"
        )

        let settings = try String(contentsOf: clientEnvironment.claudeSettingsURL, encoding: .utf8)
        #expect(!settings.contains("ANTHROPIC_BASE_URL"))
        #expect(!settings.contains("CJ_LOCAL_PROXY_TOKEN"))
        #expect(settings.contains("KEEP_ME"))

        #expect(!FileManager.default.fileExists(atPath: clientEnvironment.claudeDesktopGatewayURL.path))
        #expect(!FileManager.default.fileExists(
            atPath: clientEnvironment.claudeDesktopGatewayURL
                .deletingLastPathComponent()
                .appendingPathComponent("cj-local-proxy.json")
                .path
        ))

        let meta = try String(contentsOf: clientEnvironment.claudeDesktopMetaURL, encoding: .utf8)
        #expect(!meta.contains(ClientConfigEnvironment.claudeDesktopConfigID))
        #expect(!meta.contains("cj-local-proxy"))
        #expect(meta.contains("official-config"))

        let desktopMode = try String(contentsOf: clientEnvironment.claudeDesktopModeURL, encoding: .utf8)
        #expect(!desktopMode.contains("deploymentMode"))
        #expect(desktopMode.contains("keep"))

        let codex = try String(contentsOf: clientEnvironment.codexConfigURL, encoding: .utf8)
        #expect(!codex.contains("ark-coding-app"))
        #expect(!codex.contains("ark-coding-cli"))
        #expect(!codex.contains("ark-doubao"))
        #expect(codex.contains("[profiles.official]"))
        #expect(codex.contains("official-model"))

        let launchAgent = launchAgents.appendingPathComponent("com.cj.proxy.plist")
        #expect(!FileManager.default.fileExists(atPath: launchAgent.path))
        #expect(result.backupResult.manifest.entries.count == 7)
        #expect(FileManager.default.fileExists(atPath: result.backupResult.manifestURL.path))
        #expect(result.commandRecords.contains { $0.title == "Stop LaunchAgent" })
        #expect(runner.recordedCommands.contains { $0.joined(separator: " ").contains("launchctl bootout gui/501") })
    }

    @Test
    func restoreRejectsMissingConfirmation() async throws {
        await #expect(throws: FactoryRestoreService.FactoryRestoreError.confirmationRequired) {
            try await FactoryRestoreService(label: "com.cj.proxy").restore(
                config: .default,
                environment: InstallationEnvironment(
                    installRoot: URL(fileURLWithPath: "/tmp/install"),
                    launchAgentDirectory: URL(fileURLWithPath: "/tmp/LaunchAgents"),
                    nodePath: "/opt/homebrew/bin/node",
                    userID: 501,
                    loginKeychainPath: "/tmp/login.keychain-db"
                ),
                clientConfigEnvironment: ClientConfigEnvironment(
                    claudeSettingsURL: URL(fileURLWithPath: "/tmp/.claude/settings.json"),
                    claudeDesktopGatewayURL: URL(fileURLWithPath: "/tmp/Claude-3p/configLibrary/\(ClientConfigEnvironment.claudeDesktopConfigID).json"),
                    claudeDesktopMetaURL: URL(fileURLWithPath: "/tmp/Claude-3p/configLibrary/_meta.json"),
                    claudeDesktopModeURL: URL(fileURLWithPath: "/tmp/Claude-3p/claude_desktop_config.json"),
                    codexConfigURL: URL(fileURLWithPath: "/tmp/.codex/config.toml")
                ),
                confirmation: FactoryRestoreConfirmation(),
                runner: RestoreRecordingCommandRunner(),
                timestamp: "20260519102020"
            )
        }
    }

    @Test
    func restorePreservesUserCodexTopLevelOfficialProvider() async throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let installRoot = temp.appendingPathComponent("install")
        let clientRoot = temp.appendingPathComponent("home")
        defer { try? FileManager.default.removeItem(at: temp) }

        let clientEnvironment = ClientConfigEnvironment(
            claudeSettingsURL: clientRoot.appendingPathComponent(".claude/settings.json"),
            claudeDesktopGatewayURL: clientRoot.appendingPathComponent("Claude-3p/configLibrary/\(ClientConfigEnvironment.claudeDesktopConfigID).json"),
            claudeDesktopMetaURL: clientRoot.appendingPathComponent("Claude-3p/configLibrary/_meta.json"),
            claudeDesktopModeURL: clientRoot.appendingPathComponent("Claude-3p/claude_desktop_config.json"),
            codexConfigURL: clientRoot.appendingPathComponent(".codex/config.toml")
        )
        let installEnvironment = InstallationEnvironment(
            installRoot: installRoot,
            launchAgentDirectory: temp.appendingPathComponent("LaunchAgents"),
            nodePath: "/opt/homebrew/bin/node",
            userID: 501,
            loginKeychainPath: clientRoot.appendingPathComponent("login.keychain-db").path
        )

        try FileManager.default.createDirectory(
            at: clientEnvironment.codexConfigURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        model_provider = "openai"
        model = "official-model"
        model_reasoning_effort = "high"

        [model_providers.ark-coding-app]
        name = "Third-party provider via CJ Local Proxy - Codex App"
        base_url = "https://127.0.0.1:38443/codex-app/v1"

        [profiles.ark-doubao]
        model_provider = "ark-coding-cli"
        model = "doubao-seed-2.0-pro"
        """.write(to: clientEnvironment.codexConfigURL, atomically: true, encoding: .utf8)

        var confirmation = FactoryRestoreConfirmation()
        confirmation.reviewedBackups = true
        confirmation.understandsOfficialDefaults = true
        confirmation.typedPhrase = "RESTORE"

        _ = try await FactoryRestoreService(label: "com.cj.proxy").restore(
            config: .default,
            environment: installEnvironment,
            clientConfigEnvironment: clientEnvironment,
            confirmation: confirmation,
            runner: RestoreRecordingCommandRunner(),
            timestamp: "20260519103030"
        )

        let codex = try String(contentsOf: clientEnvironment.codexConfigURL, encoding: .utf8)
        #expect(codex.contains("model_provider = \"openai\""))
        #expect(codex.contains("model = \"official-model\""))
        #expect(codex.contains("model_reasoning_effort = \"high\""))
        #expect(!codex.contains("ark-coding-app"))
        #expect(!codex.contains("ark-doubao"))
    }

    private func seedInstalledProxyFiles(
        clientEnvironment: ClientConfigEnvironment,
        installEnvironment: InstallationEnvironment
    ) throws {
        let fileManager = FileManager.default
        for url in [
            clientEnvironment.claudeSettingsURL,
            clientEnvironment.claudeDesktopGatewayURL,
            clientEnvironment.claudeDesktopGatewayURL
                .deletingLastPathComponent()
                .appendingPathComponent("cj-local-proxy.json"),
            clientEnvironment.claudeDesktopMetaURL,
            clientEnvironment.claudeDesktopModeURL,
            clientEnvironment.codexConfigURL,
            installEnvironment.launchAgentDirectory.appendingPathComponent("com.cj.proxy.plist"),
        ] {
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        }

        try """
        {
          "env": {
            "ANTHROPIC_BASE_URL": "https://127.0.0.1:38443/claude-cli",
            "ANTHROPIC_AUTH_TOKEN": "CJ_LOCAL_PROXY_TOKEN",
            "NODE_USE_SYSTEM_CA": "1",
            "KEEP_ME": "yes"
          },
          "custom": true
        }
        """.write(to: clientEnvironment.claudeSettingsURL, atomically: true, encoding: .utf8)

        try """
        {
          "inferenceProvider": "gateway",
          "inferenceGatewayBaseUrl": "https://127.0.0.1:38443/claude-desktop",
          "inferenceGatewayApiKey": "CJ_LOCAL_PROXY_TOKEN"
        }
        """.write(to: clientEnvironment.claudeDesktopGatewayURL, atomically: true, encoding: .utf8)

        try """
        {"id":"cj-local-proxy","name":"Legacy CJ Local Proxy"}
        """.write(
            to: clientEnvironment.claudeDesktopGatewayURL
                .deletingLastPathComponent()
                .appendingPathComponent("cj-local-proxy.json"),
            atomically: true,
            encoding: .utf8
        )

        try """
        {
          "appliedId": "\(ClientConfigEnvironment.claudeDesktopConfigID)",
          "entries": [
            {"id": "\(ClientConfigEnvironment.claudeDesktopConfigID)", "name": "CJ Local Proxy"},
            {"id": "official-config", "name": "Official"}
          ],
          "configs": [
            {"id": "cj-local-proxy", "name": "Legacy CJ Local Proxy"}
          ]
        }
        """.write(to: clientEnvironment.claudeDesktopMetaURL, atomically: true, encoding: .utf8)

        try """
        {
          "deploymentMode": "3p",
          "keep": true
        }
        """.write(to: clientEnvironment.claudeDesktopModeURL, atomically: true, encoding: .utf8)

        try """
        model_provider = "ark-coding-app"
        model = "doubao-seed-2.0-pro"
        model_reasoning_effort = "medium"
        disable_response_storage = true

        [model_providers.ark-coding-app]
        name = "Third-party provider via CJ Local Proxy - Codex App"
        wire_api = "responses"
        base_url = "https://127.0.0.1:38443/codex-app/v1"

        [model_providers.ark-coding-cli]
        name = "Third-party provider via CJ Local Proxy - Codex CLI"
        wire_api = "responses"
        base_url = "https://127.0.0.1:38443/codex-cli/v1"

        [profiles.ark-doubao]
        model_provider = "ark-coding-cli"
        model = "doubao-seed-2.0-pro"

        [profiles.official]
        model_provider = "openai"
        model = "official-model"
        """.write(to: clientEnvironment.codexConfigURL, atomically: true, encoding: .utf8)

        try "<plist/>".write(
            to: installEnvironment.launchAgentDirectory.appendingPathComponent("com.cj.proxy.plist"),
            atomically: true,
            encoding: .utf8
        )
    }
}

private final class RestoreRecordingCommandRunner: CommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var commands: [[String]] = []

    var recordedCommands: [[String]] {
        lock.withLock { commands }
    }

    func run(_ executable: String, _ arguments: [String]) async -> CommandResult {
        lock.withLock {
            commands.append([executable] + arguments)
        }
        return CommandResult(exitCode: 0, stdout: "ok", stderr: "")
    }
}
