import SwiftUI

struct ProviderSettingsView: View {
    @Binding var config: SetupConfiguration
    @Binding var claudeAPIKey: String
    @Binding var codexAPIKey: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SetupPanel(
                    title: "Claude Code",
                    subtitle: "Claude Desktop 与 Claude CLI 走独立路径，方便 dashboard 分开统计。",
                    systemImage: "terminal"
                ) {
                    ProviderEditor(
                        isEnabled: $config.claudeProvider.isEnabled,
                        protocolType: $config.claudeProvider.protocolType,
                        baseURL: $config.claudeProvider.baseURL,
                        keychainAccount: $config.claudeProvider.keychainAccount,
                        apiKey: $claudeAPIKey,
                        keyPlaceholder: "Claude provider API Key"
                    )
                }

                SetupPanel(
                    title: "Codex",
                    subtitle: "Codex App 与 Codex CLI 使用不同 base path，避免用量统计混在一起。",
                    systemImage: "curlybraces.square"
                ) {
                    ProviderEditor(
                        isEnabled: $config.codexProvider.isEnabled,
                        protocolType: $config.codexProvider.protocolType,
                        baseURL: $config.codexProvider.baseURL,
                        keychainAccount: $config.codexProvider.keychainAccount,
                        apiKey: $codexAPIKey,
                        keyPlaceholder: "Codex provider API Key"
                    )
                }

                SetupPanel(
                    title: "本机代理 / Local Proxy",
                    subtitle: "只监听本机地址；LaunchAgent 会使用 RunAtLoad 和 KeepAlive。",
                    systemImage: "bolt.horizontal.circle"
                ) {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                        GridRow {
                            Text("Host")
                                .foregroundStyle(.secondary)
                            TextField("127.0.0.1", text: $config.listenHost)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.large)
                        }
                        GridRow {
                            Text("Port")
                                .foregroundStyle(.secondary)
                            Stepper(value: $config.listenPort, in: 1024...65535) {
                                Text("\(config.listenPort)")
                                    .monospacedDigit()
                            }
                            .controlSize(.large)
                        }
                        GridRow {
                            Text("Keychain")
                                .foregroundStyle(.secondary)
                            TextField("CJLocalProxy", text: $config.keychainService)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.large)
                        }
                    }
                    .font(.body)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

private struct ProviderEditor: View {
    @Binding var isEnabled: Bool
    @Binding var protocolType: ProviderProtocol
    @Binding var baseURL: String
    @Binding var keychainAccount: String
    @Binding var apiKey: String
    let keyPlaceholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("启用 / Enable", isOn: $isEnabled)
                .toggleStyle(.switch)
                .font(.title3.weight(.semibold))

            Picker("兼容类型 / Compatibility", selection: $protocolType) {
                ForEach(ProviderProtocol.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.large)
            .disabled(!isEnabled)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Base URL")
                        .foregroundStyle(.secondary)
                    TextField("https://provider.example.com/api", text: $baseURL)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.large)
                }
                GridRow {
                    Text("API Key")
                        .foregroundStyle(.secondary)
                    SecureField(keyPlaceholder, text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.large)
                }
                GridRow {
                    Text("Keychain")
                        .foregroundStyle(.secondary)
                    TextField("account", text: $keychainAccount)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.large)
                }
            }
            .font(.body)
            .disabled(!isEnabled)

            Text("保存时只写入 macOS Keychain；客户端配置只使用本地占位 token。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
