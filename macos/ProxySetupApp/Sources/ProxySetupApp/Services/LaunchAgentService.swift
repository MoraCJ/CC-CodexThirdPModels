import Foundation

struct LaunchAgentService {
    var label: String

    struct ControlCommands: Equatable {
        var bootstrap: [String]
        var kickstart: [String]
        var printStatus: [String]
        var bootout: [String]
    }

    func renderPlist(nodePath: String, proxyDirectory: URL, config: SetupConfiguration) -> String {
        let proxyPath = proxyDirectory.path
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>\(xml(label))</string>
          <key>ProgramArguments</key>
          <array>
            <string>\(xml(nodePath))</string>
            <string>\(xml(proxyPath))/server.js</string>
          </array>
          <key>WorkingDirectory</key>
          <string>\(xml(proxyPath))</string>
          <key>RunAtLoad</key>
          <true/>
          <key>KeepAlive</key>
          <true/>
          <key>StandardOutPath</key>
          <string>\(xml(proxyPath))/logs/proxy.log</string>
          <key>StandardErrorPath</key>
          <string>\(xml(proxyPath))/logs/proxy.err.log</string>
          <key>EnvironmentVariables</key>
          <dict>
            <key>LISTEN_HOST</key><string>\(xml(config.listenHost))</string>
            <key>LISTEN_PORT</key><string>\(config.listenPort)</string>
            <key>UPSTREAM_BASE_URL</key><string>\(xml(config.claudeProvider.baseURL))</string>
            <key>CODEX_UPSTREAM_BASE_URL</key><string>\(xml(config.codexProvider.baseURL))</string>
            <key>BIG_MODEL</key><string>\(xml(config.claudeModels.opus))</string>
            <key>MIDDLE_MODEL</key><string>\(xml(config.claudeModels.sonnet))</string>
            <key>SMALL_MODEL</key><string>\(xml(config.claudeModels.haiku))</string>
            <key>KEYCHAIN_SERVICE</key><string>\(xml(config.keychainService))</string>
            <key>CLAUDE_KEYCHAIN_ACCOUNT</key><string>\(xml(config.claudeProvider.keychainAccount))</string>
            <key>CODEX_KEYCHAIN_ACCOUNT</key><string>\(xml(config.codexProvider.keychainAccount))</string>
            <key>TLS_CERT_FILE</key><string>\(xml(proxyPath))/certs/server.crt</string>
            <key>TLS_KEY_FILE</key><string>\(xml(proxyPath))/certs/server.key</string>
            <key>TELEMETRY_FILE</key><string>\(xml(proxyPath))/logs/telemetry.jsonl</string>
          </dict>
        </dict>
        </plist>
        """
    }

    func controlCommands(plistURL: URL, userID: Int) -> ControlCommands {
        let domain = "gui/\(userID)"
        let serviceTarget = "\(domain)/\(label)"
        return ControlCommands(
            bootstrap: ["launchctl", "bootstrap", domain, plistURL.path],
            kickstart: ["launchctl", "kickstart", "-k", serviceTarget],
            printStatus: ["launchctl", "print", serviceTarget],
            bootout: ["launchctl", "bootout", domain, plistURL.path]
        )
    }

    private func xml(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
