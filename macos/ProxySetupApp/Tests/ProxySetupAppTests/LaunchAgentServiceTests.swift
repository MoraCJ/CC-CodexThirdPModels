import Foundation
import Testing
@testable import ProxySetupApp

struct LaunchAgentServiceTests {
    @Test
    func plistContainsRunAtLoadKeepAliveAndNoSecret() {
        let service = LaunchAgentService(label: "com.cj.claude-local-https-proxy")
        let plist = service.renderPlist(
            nodePath: "/opt/homebrew/bin/node",
            proxyDirectory: URL(fileURLWithPath: "/tmp/CJLocalProxy/claude-local-proxy"),
            config: .default
        )

        #expect(plist.contains("<key>RunAtLoad</key>"))
        #expect(plist.contains("<key>KeepAlive</key>"))
        #expect(plist.contains("KEYCHAIN_SERVICE"))
        #expect(plist.contains("CLAUDE_KEYCHAIN_ACCOUNT"))
        #expect(plist.contains("CODEX_KEYCHAIN_ACCOUNT"))
        #expect(!plist.contains("sk-"))
        #expect(!plist.contains("Bearer "))
    }

    @Test
    func escapesXmlValues() {
        var config = SetupConfiguration.default
        config.claudeProvider.baseURL = "https://example.com/a?x=1&y=2"

        let plist = LaunchAgentService(label: "com.cj.test").renderPlist(
            nodePath: "/tmp/node",
            proxyDirectory: URL(fileURLWithPath: "/tmp/proxy"),
            config: config
        )

        #expect(plist.contains("https://example.com/a?x=1&amp;y=2"))
    }
}
