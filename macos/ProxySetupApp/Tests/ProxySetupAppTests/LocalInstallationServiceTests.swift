import Foundation
import Testing
@testable import ProxySetupApp

struct LocalInstallationServiceTests {
    @Test
    func buildPlanDescribesLocalInstallWithoutSecrets() throws {
        let environment = InstallationEnvironment(
            installRoot: URL(fileURLWithPath: "/tmp/CJLocalProxy"),
            launchAgentDirectory: URL(fileURLWithPath: "/tmp/LaunchAgents"),
            nodePath: "/opt/homebrew/bin/node",
            userID: 501,
            loginKeychainPath: "/Users/cj/Library/Keychains/login.keychain-db"
        )

        let plan = try LocalInstallationService(label: "com.cj.proxy").buildPlan(
            config: .default,
            environment: environment
        )
        let joined = plan.map { "\($0.title) \($0.detail)" }.joined(separator: "\n")

        #expect(plan.count >= 7)
        #expect(joined.contains("复制代理文件"))
        #expect(joined.contains("写入 LaunchAgent"))
        #expect(joined.contains("RunAtLoad"))
        #expect(joined.contains("KeepAlive"))
        #expect(joined.contains("/claude-desktop/health"))
        #expect(!joined.contains("Bearer "))
        #expect(!joined.contains("sk-"))
    }

    @Test
    func buildPlanRejectsInvalidConfiguration() {
        var config = SetupConfiguration.default
        config.claudeProvider.baseURL = "http://not-secure.example.com"

        #expect(throws: SetupConfiguration.ValidationError.invalidProviderURL("http://not-secure.example.com")) {
            try LocalInstallationService().buildPlan(
                config: config,
                environment: InstallationEnvironment(
                    installRoot: URL(fileURLWithPath: "/tmp/CJLocalProxy"),
                    launchAgentDirectory: URL(fileURLWithPath: "/tmp/LaunchAgents"),
                    nodePath: "/opt/homebrew/bin/node",
                    userID: 501,
                    loginKeychainPath: "/Users/cj/Library/Keychains/login.keychain-db"
                )
            )
        }
    }

    @Test
    func prepareLocalFilesWritesOnlyInjectedDirectories() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = temp.appendingPathComponent("source")
        let installRoot = temp.appendingPathComponent("install")
        let launchAgents = temp.appendingPathComponent("LaunchAgents")
        defer { try? FileManager.default.removeItem(at: temp) }

        try FileManager.default.createDirectory(
            at: source.appendingPathComponent("bin"),
            withIntermediateDirectories: true
        )
        try "server".write(to: source.appendingPathComponent("server.js"), atomically: true, encoding: .utf8)
        try "telemetry".write(to: source.appendingPathComponent("telemetry.js"), atomically: true, encoding: .utf8)
        try "keychain".write(to: source.appendingPathComponent("keychain.js"), atomically: true, encoding: .utf8)
        try "launcher".write(to: source.appendingPathComponent("bin/claude-ca-launcher.c"), atomically: true, encoding: .utf8)

        let environment = InstallationEnvironment(
            installRoot: installRoot,
            launchAgentDirectory: launchAgents,
            nodePath: "/opt/homebrew/bin/node",
            userID: 501,
            loginKeychainPath: "/Users/cj/Library/Keychains/login.keychain-db"
        )

        let result = try LocalInstallationService(
            label: "com.cj.claude-local-https-proxy"
        ).prepareLocalFiles(
            config: .default,
            environment: environment,
            proxySourceDirectory: source
        )

        #expect(FileManager.default.fileExists(atPath: installRoot.appendingPathComponent("claude-local-proxy/server.js").path))
        #expect(FileManager.default.fileExists(atPath: installRoot.appendingPathComponent("config/proxy.env").path))
        #expect(FileManager.default.fileExists(atPath: launchAgents.appendingPathComponent("com.cj.claude-local-https-proxy.plist").path))
        #expect(FileManager.default.fileExists(atPath: installRoot.appendingPathComponent("claude-local-proxy/certs/openssl-server.cnf").path))

        let runtime = try String(contentsOf: installRoot.appendingPathComponent("config/proxy.env"), encoding: .utf8)
        let plist = try String(contentsOf: result.launchAgentPlistURL, encoding: .utf8)
        let certConfig = try String(contentsOf: result.openSSLConfigURL, encoding: .utf8)

        #expect(runtime.contains("KEYCHAIN_SERVICE=CJLocalProxy"))
        #expect(plist.contains("<key>RunAtLoad</key>"))
        #expect(plist.contains("<key>KeepAlive</key>"))
        #expect(certConfig.contains("IP.1 = 127.0.0.1"))
        #expect(result.launchCommands.bootstrap[1] == "bootstrap")
        #expect(result.trustCommand.first == "security")
        #expect(result.verificationSummary.checks.count == 7)
        #expect(!runtime.contains("Bearer "))
        #expect(!plist.contains("sk-"))
    }

    @Test
    func managedFileChangesDescribeRuntimeCertificateAndLaunchAgent() throws {
        let environment = InstallationEnvironment(
            installRoot: URL(fileURLWithPath: "/tmp/CJLocalProxy"),
            launchAgentDirectory: URL(fileURLWithPath: "/tmp/LaunchAgents"),
            nodePath: "/opt/homebrew/bin/node",
            userID: 501,
            loginKeychainPath: "/Users/cj/Library/Keychains/login.keychain-db"
        )

        let changes = try LocalInstallationService(
            label: "com.cj.claude-local-https-proxy"
        ).managedFileChanges(config: .default, environment: environment)
        let titles = changes.map(\.title)
        let joinedContents = changes.map(\.proposedContents).joined(separator: "\n")

        #expect(titles == [
            "Proxy runtime config",
            "OpenSSL server config",
            "LaunchAgent plist",
        ])
        #expect(changes[0].targetURL.path == "/tmp/CJLocalProxy/config/proxy.env")
        #expect(changes[1].targetURL.path == "/tmp/CJLocalProxy/claude-local-proxy/certs/openssl-server.cnf")
        #expect(changes[2].targetURL.path == "/tmp/LaunchAgents/com.cj.claude-local-https-proxy.plist")
        #expect(joinedContents.contains("KEYCHAIN_SERVICE=CJLocalProxy"))
        #expect(joinedContents.contains("<key>RunAtLoad</key>"))
        #expect(!joinedContents.contains("Bearer "))
        #expect(!joinedContents.contains("sk-"))
    }
}
