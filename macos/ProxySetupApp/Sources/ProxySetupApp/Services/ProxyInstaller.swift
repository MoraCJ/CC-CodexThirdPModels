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
        guard let bundleURL = bundledProxyDirectory() else {
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
        let runtime = renderRuntimeConfig(config)
        let configURL = installRoot.appendingPathComponent("config/proxy.env")
        try runtime.write(to: configURL, atomically: true, encoding: .utf8)
    }

    func renderRuntimeConfig(_ config: SetupConfiguration) -> String {
        [
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
    }

    enum InstallerError: Error, Equatable {
        case missingProxyBundle
    }

    private func bundledProxyDirectory() -> URL? {
        let fileManager = FileManager.default
        if let appResourceURL = Bundle.main.resourceURL {
            let packagedURL = appResourceURL
                .appendingPathComponent("ProxySetupApp_ProxySetupApp.bundle", isDirectory: true)
                .appendingPathComponent("ProxyBundle", isDirectory: true)
            if fileManager.fileExists(atPath: packagedURL.path) {
                return packagedURL
            }
        }

        if let swiftPMURL = Bundle.module.url(forResource: "ProxyBundle", withExtension: nil),
           fileManager.fileExists(atPath: swiftPMURL.path) {
            return swiftPMURL
        }

        if let resourceURL = Bundle.module.resourceURL?
            .appendingPathComponent("ProxyBundle", isDirectory: true),
            fileManager.fileExists(atPath: resourceURL.path) {
            return resourceURL
        }

        return nil
    }
}
