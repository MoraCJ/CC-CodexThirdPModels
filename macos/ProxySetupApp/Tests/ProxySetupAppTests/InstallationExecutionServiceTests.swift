import Foundation
import Testing
@testable import ProxySetupApp

struct InstallationExecutionServiceTests {
    @Test
    func executeInstallsWithBackupsCommandsAndVerificationUsingInjectedPaths() async throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = temp.appendingPathComponent("source")
        let installRoot = temp.appendingPathComponent("install")
        let launchAgents = temp.appendingPathComponent("LaunchAgents")
        let clientRoot = temp.appendingPathComponent("home")
        defer { try? FileManager.default.removeItem(at: temp) }

        try createProxySource(at: source)
        try FileManager.default.createDirectory(
            at: clientRoot.appendingPathComponent(".claude"),
            withIntermediateDirectories: true
        )
        try "{}".write(
            to: clientRoot.appendingPathComponent(".claude/settings.json"),
            atomically: true,
            encoding: .utf8
        )

        var confirmation = InstallationConfirmation()
        confirmation.reviewedDryRun = true
        confirmation.createdBackups = true
        confirmation.understandsSystemChanges = true
        confirmation.typedPhrase = "INSTALL"

        let runner = RecordingCommandRunner()
        let result = try await InstallationExecutionService(label: "com.cj.proxy").execute(
            config: .default,
            environment: InstallationEnvironment(
                installRoot: installRoot,
                launchAgentDirectory: launchAgents,
                nodePath: "/opt/homebrew/bin/node",
                userID: 501,
                loginKeychainPath: clientRoot.appendingPathComponent("login.keychain-db").path
            ),
            clientConfigEnvironment: ClientConfigEnvironment(
                claudeSettingsURL: clientRoot.appendingPathComponent(".claude/settings.json"),
                claudeDesktopGatewayURL: clientRoot.appendingPathComponent("Claude-3p/configLibrary/\(ClientConfigEnvironment.claudeDesktopConfigID).json"),
                claudeDesktopMetaURL: clientRoot.appendingPathComponent("Claude-3p/configLibrary/_meta.json"),
                claudeDesktopModeURL: clientRoot.appendingPathComponent("Claude-3p/claude_desktop_config.json"),
                codexConfigURL: clientRoot.appendingPathComponent(".codex/config.toml")
            ),
            confirmation: confirmation,
            runner: runner,
            timestamp: "20260518190000",
            proxySourceDirectory: source
        )

        #expect(FileManager.default.fileExists(atPath: installRoot.appendingPathComponent("claude-local-proxy/server.js").path))
        #expect(FileManager.default.fileExists(atPath: launchAgents.appendingPathComponent("com.cj.proxy.plist").path))
        #expect(FileManager.default.fileExists(atPath: clientRoot.appendingPathComponent(".codex/config.toml").path))
        #expect(result.backupResult.manifest.entries.count == 8)
        #expect(result.verificationSummary.isPassing)

        let commands = runner.recordedCommands.map { $0.joined(separator: " ") }
        #expect(commands.contains { $0.contains("openssl genrsa") })
        #expect(commands.contains { $0.contains("security add-trusted-cert") })
        #expect(commands.contains { $0.contains("launchctl bootstrap gui/501") })
        #expect(commands.contains { $0.contains("curl -sk") && $0.contains("/health") })

        let settings = try String(contentsOf: clientRoot.appendingPathComponent(".claude/settings.json"), encoding: .utf8)
        let manifest = try String(contentsOf: result.backupResult.manifestURL, encoding: .utf8)
        #expect(settings.contains("CJ_LOCAL_PROXY_TOKEN"))
        #expect(!settings.contains("Bearer "))
        #expect(!manifest.contains("CJ_LOCAL_PROXY_TOKEN"))
        #expect(!manifest.contains("sk-"))
    }

    @Test
    func executeReportsStreamingProgressEvents() async throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = temp.appendingPathComponent("source")
        let installRoot = temp.appendingPathComponent("install")
        let launchAgents = temp.appendingPathComponent("LaunchAgents")
        let clientRoot = temp.appendingPathComponent("home")
        defer { try? FileManager.default.removeItem(at: temp) }

        try createProxySource(at: source)

        var confirmation = InstallationConfirmation()
        confirmation.reviewedDryRun = true
        confirmation.createdBackups = true
        confirmation.understandsSystemChanges = true
        confirmation.typedPhrase = "INSTALL"

        let lock = NSLock()
        var events: [InstallationProgressEvent] = []
        let runner = RecordingCommandRunner()

        _ = try await InstallationExecutionService(label: "com.cj.proxy").execute(
            config: .default,
            environment: InstallationEnvironment(
                installRoot: installRoot,
                launchAgentDirectory: launchAgents,
                nodePath: "/usr/local/bin/node",
                userID: 501,
                loginKeychainPath: clientRoot.appendingPathComponent("login.keychain-db").path
            ),
            clientConfigEnvironment: ClientConfigEnvironment(
                claudeSettingsURL: clientRoot.appendingPathComponent(".claude/settings.json"),
                claudeDesktopGatewayURL: clientRoot.appendingPathComponent("Claude-3p/configLibrary/\(ClientConfigEnvironment.claudeDesktopConfigID).json"),
                claudeDesktopMetaURL: clientRoot.appendingPathComponent("Claude-3p/configLibrary/_meta.json"),
                claudeDesktopModeURL: clientRoot.appendingPathComponent("Claude-3p/claude_desktop_config.json"),
                codexConfigURL: clientRoot.appendingPathComponent(".codex/config.toml")
            ),
            confirmation: confirmation,
            runner: runner,
            timestamp: "20260518190500",
            proxySourceDirectory: source,
            progress: { event in
                lock.withLock {
                    events.append(event)
                }
            }
        )

        #expect(events.contains { $0.title.contains("探测依赖") && $0.status == .succeeded })
        #expect(events.contains { $0.title == "Bootstrap LaunchAgent" && $0.status == .running })
        #expect(events.contains { $0.title == "Start LaunchAgent" && $0.status == .succeeded })
        #expect(events.contains { $0.title.contains("验证端点") && $0.status == .succeeded })
    }

    @Test
    func executeWritesResolvedNodePathWhenEnvironmentDoesNotProvideOne() async throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = temp.appendingPathComponent("source")
        let installRoot = temp.appendingPathComponent("install")
        let launchAgents = temp.appendingPathComponent("LaunchAgents")
        let clientRoot = temp.appendingPathComponent("home")
        defer { try? FileManager.default.removeItem(at: temp) }

        try createProxySource(at: source)

        var confirmation = InstallationConfirmation()
        confirmation.reviewedDryRun = true
        confirmation.createdBackups = true
        confirmation.understandsSystemChanges = true
        confirmation.typedPhrase = "INSTALL"

        let runner = RecordingCommandRunner(outputs: [
            "command -v node": CommandResult(exitCode: 0, stdout: "/usr/local/bin/node\n", stderr: ""),
            "/usr/local/bin/node --version": CommandResult(exitCode: 0, stdout: "v24.15.0\n", stderr: ""),
            "command -v npm": CommandResult(exitCode: 1, stdout: "", stderr: ""),
            "command -v brew": CommandResult(exitCode: 1, stdout: "", stderr: ""),
            "command -v claude": CommandResult(exitCode: 1, stdout: "", stderr: ""),
            "command -v codex": CommandResult(exitCode: 1, stdout: "", stderr: ""),
        ])

        let result = try await InstallationExecutionService(label: "com.cj.proxy").execute(
            config: .default,
            environment: InstallationEnvironment(
                installRoot: installRoot,
                launchAgentDirectory: launchAgents,
                nodePath: "",
                userID: 501,
                loginKeychainPath: clientRoot.appendingPathComponent("login.keychain-db").path
            ),
            clientConfigEnvironment: ClientConfigEnvironment(
                claudeSettingsURL: clientRoot.appendingPathComponent(".claude/settings.json"),
                claudeDesktopGatewayURL: clientRoot.appendingPathComponent("Claude-3p/configLibrary/\(ClientConfigEnvironment.claudeDesktopConfigID).json"),
                claudeDesktopMetaURL: clientRoot.appendingPathComponent("Claude-3p/configLibrary/_meta.json"),
                claudeDesktopModeURL: clientRoot.appendingPathComponent("Claude-3p/claude_desktop_config.json"),
                codexConfigURL: clientRoot.appendingPathComponent(".codex/config.toml")
            ),
            confirmation: confirmation,
            runner: runner,
            timestamp: "20260518190600",
            proxySourceDirectory: source
        )

        let plist = try String(contentsOf: result.localInstallationResult.launchAgentPlistURL, encoding: .utf8)
        #expect(plist.contains("/usr/local/bin/node"))
        #expect(!plist.contains("/opt/homebrew/bin/node"))
    }

    @Test
    func executeRejectsMissingInstallationConfirmation() async throws {
        let service = InstallationExecutionService(label: "com.cj.proxy")

        await #expect(throws: InstallationExecutionService.InstallationError.confirmationRequired) {
            try await service.execute(
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
                confirmation: InstallationConfirmation(),
                runner: RecordingCommandRunner(),
                timestamp: "20260518190100",
                proxySourceDirectory: nil
            )
        }
    }

    @Test
    func executeStopsOnRequiredCommandFailure() async throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = temp.appendingPathComponent("source")
        defer { try? FileManager.default.removeItem(at: temp) }
        try createProxySource(at: source)

        var confirmation = InstallationConfirmation()
        confirmation.reviewedDryRun = true
        confirmation.createdBackups = true
        confirmation.understandsSystemChanges = true
        confirmation.typedPhrase = "INSTALL"

        let runner = RecordingCommandRunner(failingExecutable: "openssl")

        await #expect(throws: InstallationExecutionService.InstallationError.commandFailed) {
            try await InstallationExecutionService(label: "com.cj.proxy").execute(
                config: .default,
                environment: InstallationEnvironment(
                    installRoot: temp.appendingPathComponent("install"),
                    launchAgentDirectory: temp.appendingPathComponent("LaunchAgents"),
                    nodePath: "/opt/homebrew/bin/node",
                    userID: 501,
                    loginKeychainPath: temp.appendingPathComponent("login.keychain-db").path
                ),
                clientConfigEnvironment: ClientConfigEnvironment(
                    claudeSettingsURL: temp.appendingPathComponent(".claude/settings.json"),
                    claudeDesktopGatewayURL: temp.appendingPathComponent("Claude-3p/configLibrary/\(ClientConfigEnvironment.claudeDesktopConfigID).json"),
                    claudeDesktopMetaURL: temp.appendingPathComponent("Claude-3p/configLibrary/_meta.json"),
                    claudeDesktopModeURL: temp.appendingPathComponent("Claude-3p/claude_desktop_config.json"),
                    codexConfigURL: temp.appendingPathComponent(".codex/config.toml")
                ),
                confirmation: confirmation,
                runner: runner,
                timestamp: "20260518190200",
                proxySourceDirectory: source
            )
        }
    }

    private func createProxySource(at source: URL) throws {
        try FileManager.default.createDirectory(
            at: source.appendingPathComponent("bin"),
            withIntermediateDirectories: true
        )
        try "server".write(to: source.appendingPathComponent("server.js"), atomically: true, encoding: .utf8)
        try "telemetry".write(to: source.appendingPathComponent("telemetry.js"), atomically: true, encoding: .utf8)
        try "keychain".write(to: source.appendingPathComponent("keychain.js"), atomically: true, encoding: .utf8)
        try "launcher".write(to: source.appendingPathComponent("bin/claude-ca-launcher.c"), atomically: true, encoding: .utf8)
    }
}

private final class RecordingCommandRunner: CommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var commands: [[String]] = []
    private let failingExecutable: String?
    private let outputs: [String: CommandResult]

    init(
        failingExecutable: String? = nil,
        outputs: [String: CommandResult] = [:]
    ) {
        self.failingExecutable = failingExecutable
        self.outputs = outputs
    }

    var recordedCommands: [[String]] {
        lock.withLock { commands }
    }

    func run(_ executable: String, _ arguments: [String]) async -> CommandResult {
        lock.withLock {
            commands.append([executable] + arguments)
        }
        let key = ([executable] + arguments).joined(separator: " ")
        if let output = outputs[key] {
            return output
        }
        if executable == failingExecutable {
            return CommandResult(exitCode: 1, stdout: "", stderr: "forced failure")
        }
        if executable.contains("curl") || executable == "curl" {
            return CommandResult(exitCode: 0, stdout: "200", stderr: "")
        }
        return CommandResult(exitCode: 0, stdout: "ok", stderr: "")
    }
}
