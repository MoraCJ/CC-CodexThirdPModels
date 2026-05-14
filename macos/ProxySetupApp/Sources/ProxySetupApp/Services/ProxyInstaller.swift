import Foundation

struct ProxyInstaller {
    var installRoot: URL

    var proxyDirectory: URL {
        installRoot.appendingPathComponent("claude-local-proxy", isDirectory: true)
    }

    func createDirectories() throws {
        let directories = [
            proxyDirectory,
            proxyDirectory.appendingPathComponent("logs", isDirectory: true),
            proxyDirectory.appendingPathComponent("certs", isDirectory: true),
            installRoot.appendingPathComponent("config", isDirectory: true),
            installRoot.appendingPathComponent("backups", isDirectory: true),
        ]
        for directory in directories {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    func copyBundledProxyFiles() throws {
        guard let bundleURL = Bundle.module.url(forResource: "ProxyBundle", withExtension: nil) else {
            throw InstallerError.missingProxyBundle
        }
        try copyProxyFiles(from: bundleURL)
    }

    func copyProxyFiles(from sourceDirectory: URL) throws {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: sourceDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw InstallerError.missingProxyBundle
        }

        for case let sourceURL as URL in enumerator {
            let values = try sourceURL.resourceValues(forKeys: [.isDirectoryKey])
            let relativePath = sourceURL.path.replacingOccurrences(
                of: sourceDirectory.path + "/",
                with: ""
            )
            let targetURL = proxyDirectory.appendingPathComponent(relativePath)

            if values.isDirectory == true {
                try fileManager.createDirectory(at: targetURL, withIntermediateDirectories: true)
                continue
            }

            try fileManager.createDirectory(
                at: targetURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: targetURL.path) {
                try fileManager.removeItem(at: targetURL)
            }
            try fileManager.copyItem(at: sourceURL, to: targetURL)
        }
    }

    func writeRuntimeConfig(_ config: SetupConfiguration) throws {
        let runtime = [
            "LISTEN_HOST=\(config.listenHost)",
            "LISTEN_PORT=\(config.listenPort)",
            "UPSTREAM_BASE_URL=\(config.claudeProvider.baseURL)",
            "CODEX_UPSTREAM_BASE_URL=\(config.codexProvider.baseURL)",
            "BIG_MODEL=\(config.claudeModels.opus)",
            "MIDDLE_MODEL=\(config.claudeModels.sonnet)",
            "SMALL_MODEL=\(config.claudeModels.haiku)",
            "KEYCHAIN_SERVICE=\(config.keychainService)",
            "CLAUDE_KEYCHAIN_ACCOUNT=\(config.claudeProvider.keychainAccount)",
            "CODEX_KEYCHAIN_ACCOUNT=\(config.codexProvider.keychainAccount)",
            "TLS_CERT_FILE=\(proxyDirectory.path)/certs/server.crt",
            "TLS_KEY_FILE=\(proxyDirectory.path)/certs/server.key",
            "TELEMETRY_FILE=\(proxyDirectory.path)/logs/telemetry.jsonl",
        ].joined(separator: "\n") + "\n"

        let configURL = installRoot.appendingPathComponent("config/proxy.env")
        try runtime.write(to: configURL, atomically: true, encoding: .utf8)
    }

    enum InstallerError: Error, Equatable {
        case missingProxyBundle
    }
}
