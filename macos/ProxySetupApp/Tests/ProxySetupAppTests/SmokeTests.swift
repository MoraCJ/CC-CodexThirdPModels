import Testing
@testable import ProxySetupApp

struct SmokeTests {
    @Test
    @MainActor
    func appStateHasInitialStatus() {
        let state = AppState()
        #expect(state.proxyStatusLabel == "未检测 / Not Checked")
    }

    @Test
    @MainActor
    func appStateValidatesDefaultConfiguration() {
        let state = AppState()
        state.validateConfiguration()

        #expect(state.isConfigurationValid)
        #expect(state.validationMessage.contains("配置可用"))
    }

    @Test
    @MainActor
    func appStateDoesNotAllowKeychainSaveWithoutConfirmation() {
        let state = AppState()
        state.claudeAPIKey = "secret"

        #expect(!state.canSaveProviderKeys)

        state.keychainWriteConfirmation.reviewedAccounts = true
        state.keychainWriteConfirmation.understandsKeychainWrite = true
        state.keychainWriteConfirmation.typedPhrase = "KEYCHAIN"

        #expect(state.canSaveProviderKeys)
    }
}
