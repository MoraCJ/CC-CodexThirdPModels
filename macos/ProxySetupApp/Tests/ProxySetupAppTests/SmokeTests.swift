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
        #expect(!state.hasValidatedConfiguration)
        state.validateConfiguration()

        #expect(state.hasValidatedConfiguration)
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
        #expect(state.saveKeysDisabledReason.contains("可以保存"))
    }

    @Test
    @MainActor
    func appStateExplainsDisabledSaveKeyButton() {
        let state = AppState()
        #expect(state.saveKeysDisabledReason.contains("请输入至少一个 API Key"))

        state.claudeAPIKey = "secret"
        #expect(state.saveKeysDisabledReason.contains("已核对账号"))

        state.keychainWriteConfirmation.reviewedAccounts = true
        #expect(state.saveKeysDisabledReason.contains("写入 macOS Keychain"))

        state.keychainWriteConfirmation.understandsKeychainWrite = true
        #expect(state.saveKeysDisabledReason.contains("KEYCHAIN"))
    }
}
