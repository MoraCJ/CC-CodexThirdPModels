import Foundation
import Testing
@testable import ProxySetupApp

struct ProxyInstallerTests {
    @Test
    func installCreatesExpectedDirectories() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = ProxyInstaller(installRoot: root)

        try installer.createDirectories()

        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("claude-local-proxy").path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("claude-local-proxy/logs").path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("claude-local-proxy/certs").path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("config").path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("backups").path))
    }

    @Test
    func runtimeConfigContainsNoProviderSecrets() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = ProxyInstaller(installRoot: root)
        try installer.createDirectories()

        try installer.writeRuntimeConfig(.default)
        let config = try String(
            contentsOf: root.appendingPathComponent("config/proxy.env"),
            encoding: .utf8
        )

        #expect(config.contains("KEYCHAIN_SERVICE=CJLocalProxy"))
        #expect(config.contains("CLAUDE_KEYCHAIN_ACCOUNT=claude-upstream-api-key"))
        #expect(config.contains("CODEX_KEYCHAIN_ACCOUNT=codex-upstream-api-key"))
        #expect(!config.contains("Bearer "))
        #expect(!config.contains("sk-"))
    }

    @Test
    func copiesProxyBundleIncludingKeychainHelper() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = temp.appendingPathComponent("source")
        let root = temp.appendingPathComponent("install")
        defer { try? FileManager.default.removeItem(at: temp) }

        try FileManager.default.createDirectory(
            at: source.appendingPathComponent("bin"),
            withIntermediateDirectories: true
        )
        try "server".write(to: source.appendingPathComponent("server.js"), atomically: true, encoding: .utf8)
        try "telemetry".write(to: source.appendingPathComponent("telemetry.js"), atomically: true, encoding: .utf8)
        try "keychain".write(to: source.appendingPathComponent("keychain.js"), atomically: true, encoding: .utf8)
        try "launcher".write(to: source.appendingPathComponent("bin/claude-ca-launcher.c"), atomically: true, encoding: .utf8)

        let installer = ProxyInstaller(installRoot: root)
        try installer.createDirectories()
        try installer.copyProxyFiles(from: source)

        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("claude-local-proxy/server.js").path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("claude-local-proxy/telemetry.js").path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("claude-local-proxy/keychain.js").path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("claude-local-proxy/bin/claude-ca-launcher.c").path))
    }
}
