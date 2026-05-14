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
}
