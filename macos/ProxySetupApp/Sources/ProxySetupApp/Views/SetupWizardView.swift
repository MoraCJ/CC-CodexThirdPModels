import SwiftUI

struct SetupWizardView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Picker("Setup Step", selection: $appState.selectedSetupTab) {
                ForEach(AppState.SetupTab.allCases) { tab in
                    Label(tab.title, systemImage: tab.systemImage).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)
            .padding(.bottom, 14)

            Group {
                switch appState.selectedSetupTab {
                case .provider:
                    ProviderSettingsView(
                        config: $appState.setupConfiguration,
                        claudeAPIKey: $appState.claudeAPIKey,
                        codexAPIKey: $appState.codexAPIKey
                    )
                case .models:
                    ModelMappingView(config: $appState.setupConfiguration)
                case .verify:
                    VerificationResultsView(config: appState.setupConfiguration)
                }
            }
            .padding(.horizontal, 24)

            actionBar
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("本机代理设置 / Local Proxy Setup")
                    .font(.title2.bold())
                Text("输入 Base URL、API Key 和模型名；真实 Key 只保存到 macOS Keychain。")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                InfoBadge(
                    text: appState.isConfigurationValid ? "配置可用 / Valid" : "待校验 / Check needed",
                    systemImage: appState.isConfigurationValid ? "checkmark.seal.fill" : "exclamationmark.triangle",
                    tint: appState.isConfigurationValid ? .green : .orange
                )
                Text(appState.keychainStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(24)
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button {
                appState.validateConfiguration()
            } label: {
                Label("检查配置 / Check", systemImage: "checkmark.circle")
            }

            Button {
                appState.saveProviderKeysToKeychain()
            } label: {
                Label("保存 Key / Save Keys", systemImage: "key.fill")
            }
            .buttonStyle(.borderedProminent)

            Text(appState.validationMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()
        }
        .padding(24)
        .background(.bar)
    }
}
