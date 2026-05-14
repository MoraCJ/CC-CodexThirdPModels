import SwiftUI

struct ProviderSettingsView: View {
    @Binding var config: SetupConfiguration

    var body: some View {
        Form {
            Section("Claude Provider / Claude 服务商") {
                Toggle("启用 Claude / Enable Claude", isOn: $config.claudeProvider.isEnabled)
                TextField("Anthropic-compatible Base URL", text: $config.claudeProvider.baseURL)
                TextField("Keychain Account", text: $config.claudeProvider.keychainAccount)
            }

            Section("Codex Provider / Codex 服务商") {
                Toggle("启用 Codex / Enable Codex", isOn: $config.codexProvider.isEnabled)
                TextField("OpenAI-compatible Base URL", text: $config.codexProvider.baseURL)
                TextField("Keychain Account", text: $config.codexProvider.keychainAccount)
            }

            Section("Local Proxy / 本机代理") {
                TextField("Listen Host", text: $config.listenHost)
                Stepper(value: $config.listenPort, in: 1024...65535) {
                    Text("Listen Port: \(config.listenPort)")
                }
                TextField("Keychain Service", text: $config.keychainService)
            }
        }
        .formStyle(.grouped)
    }
}
