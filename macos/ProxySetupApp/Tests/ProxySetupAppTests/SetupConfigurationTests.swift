import Foundation
import Testing
@testable import ProxySetupApp

struct SetupConfigurationTests {
    @Test
    func defaultConfigurationUsesStableClientPrefixes() throws {
        let config = SetupConfiguration.default
        #expect(config.claudeDesktopBaseURL.absoluteString == "https://127.0.0.1:38443/claude-desktop")
        #expect(config.claudeCLIBaseURL.absoluteString == "https://127.0.0.1:38443/claude-cli")
        #expect(config.codexAppBaseURL.absoluteString == "https://127.0.0.1:38443/codex-app/v1")
        #expect(config.codexCLIBaseURL.absoluteString == "https://127.0.0.1:38443/codex-cli/v1")
    }

    @Test
    func rejectsNonHTTPSProviderURL() {
        var config = SetupConfiguration.default
        config.claudeProvider.baseURL = "http://example.com"

        #expect(throws: SetupConfiguration.ValidationError.invalidProviderURL("http://example.com")) {
            try config.validate()
        }
    }

    @Test
    func requiresAtLeastOneEnabledProvider() {
        var config = SetupConfiguration.default
        config.claudeProvider.isEnabled = false
        config.codexProvider.isEnabled = false

        #expect(throws: SetupConfiguration.ValidationError.noEnabledProvider) {
            try config.validate()
        }
    }

    @Test
    func rejectsInvalidPort() {
        var config = SetupConfiguration.default
        config.listenPort = 70000

        #expect(throws: SetupConfiguration.ValidationError.invalidPort) {
            try config.validate()
        }
    }
}
