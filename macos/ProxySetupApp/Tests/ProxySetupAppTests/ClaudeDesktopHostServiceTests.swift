import Foundation
import Testing
@testable import ProxySetupApp

struct ClaudeDesktopHostServiceTests {
    @Test
    func environmentUsesConfigurableDesktopSupportDirectoryName() {
        let home = URL(fileURLWithPath: "/tmp/cj-home", isDirectory: true)
        let environment = ClaudeDesktopEnvironment(
            supportDirectoryName: "Claude-Custom3p",
            homeDirectory: home
        )

        #expect(environment.supportRoot.path == "/tmp/cj-home/Library/Application Support/Claude-Custom3p")
        #expect(environment.configLibraryURL.path.hasSuffix("Claude-Custom3p/configLibrary"))
        #expect(environment.desktopModeURL.path.hasSuffix("Claude-Custom3p/claude_desktop_config.json"))
        #expect(environment.logURL.path == "/tmp/cj-home/Library/Logs/Claude-Custom3p/main.log")
        #expect(environment.hostBundleRootURL.path.hasSuffix("Claude-Custom3p/claude-code"))
    }

    @Test
    func clientConfigEnvironmentFollowsConfigurableDesktopSupportDirectoryName() {
        let home = URL(fileURLWithPath: "/tmp/cj-home", isDirectory: true)
        let environment = ClientConfigEnvironment.defaultEnvironment(
            homeDirectory: home,
            claudeDesktopSupportDirectoryName: "Claude-Custom3p"
        )

        #expect(environment.claudeDesktopGatewayURL.path.hasSuffix("Claude-Custom3p/configLibrary/\(ClientConfigEnvironment.claudeDesktopConfigID).json"))
        #expect(environment.claudeDesktopMetaURL.path.hasSuffix("Claude-Custom3p/configLibrary/_meta.json"))
        #expect(environment.claudeDesktopModeURL.path.hasSuffix("Claude-Custom3p/claude_desktop_config.json"))
    }

    @Test
    func inspectParsesHostVersionFromDesktopLogAndReportsMissingBinary() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let environment = ClaudeDesktopEnvironment(supportDirectoryName: "Claude-3p", homeDirectory: temp)
        try FileManager.default.createDirectory(
            at: environment.logURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        2026-05-19 21:15:54 [info] [CCD] Downloading bundle from https://downloads.claude.ai/claude-code-releases/2.1.138/darwin-arm64/claude.app.tar.zst
        """.write(to: environment.logURL, atomically: true, encoding: .utf8)

        let status = try ClaudeDesktopHostBundleService().inspect(environment: environment)

        #expect(status.version == "2.1.138")
        #expect(!status.isHostBinaryReady)
        #expect(status.checks.contains { $0.title == "Desktop host executable" && $0.status == .missing })
    }

    @Test
    func initializeFromLocalCLIWritesLauncherSymlinksAndVerifiedMarker() async throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let environment = ClaudeDesktopEnvironment(supportDirectoryName: "Claude-3p", homeDirectory: temp)
        let proxyDirectory = temp
            .appendingPathComponent("Library/Application Support/CJLocalProxy/claude-local-proxy", isDirectory: true)
        try FileManager.default.createDirectory(
            at: environment.logURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        2026-05-19 21:15:27 [info] [ClaudeCodeManager-VM] Downloading from https://downloads.claude.ai/claude-code-releases/2.1.138/linux-arm64/claude.zst
        """.write(to: environment.logURL, atomically: true, encoding: .utf8)

        let runner = HostRecordingCommandRunner(outputs: [
            "command -v claude": CommandResult(exitCode: 0, stdout: "/opt/homebrew/bin/claude\n", stderr: "")
        ])
        var events: [InstallationProgressEvent] = []
        let result = try await ClaudeDesktopHostBundleService().initializeFromLocalCLI(
            environment: environment,
            proxyDirectory: proxyDirectory,
            config: .default,
            runner: runner,
            progress: { event in events.append(event) }
        )

        let versionRoot = environment.hostBundleRootURL.appendingPathComponent("2.1.138", isDirectory: true)
        let launcherURL = proxyDirectory.appendingPathComponent("bin/claude-ca-launcher", isDirectory: false)
        let desktopExecutableURL = versionRoot.appendingPathComponent("claude.app/Contents/MacOS/claude")
        let directExecutableURL = versionRoot.appendingPathComponent("claude")

        #expect(result.status.isHostBinaryReady)
        #expect(FileManager.default.fileExists(atPath: versionRoot.appendingPathComponent(".verified").path))
        #expect(FileManager.default.fileExists(atPath: launcherURL.path))
        #expect((try? String(contentsOf: launcherURL, encoding: .utf8))?.contains("ANTHROPIC_BASE_URL") == true)
        #expect((try? String(contentsOf: launcherURL, encoding: .utf8))?.contains("ANTHROPIC_AUTH_TOKEN=CJ_LOCAL_PROXY_TOKEN") == true)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: desktopExecutableURL.path) == launcherURL.path)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: directExecutableURL.path) == launcherURL.path)
        #expect(events.contains { $0.title.contains("初始化 Claude Desktop Host") && $0.status == .succeeded })
        #expect(!String(describing: result).contains("sk-"))
        #expect(!String(describing: result).contains("Bearer "))
    }
}

private final class HostRecordingCommandRunner: CommandRunning, @unchecked Sendable {
    private let outputs: [String: CommandResult]

    init(outputs: [String: CommandResult]) {
        self.outputs = outputs
    }

    func run(_ executable: String, _ arguments: [String]) async -> CommandResult {
        let key = ([executable] + arguments).joined(separator: " ")
        return outputs[key] ?? CommandResult(exitCode: 0, stdout: "ok", stderr: "")
    }
}
