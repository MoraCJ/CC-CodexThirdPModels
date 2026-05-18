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
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

            statusBanners
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
                    .font(.title.bold())
                Text("输入 Base URL、API Key 和模型名；真实 Key 只保存到 macOS Keychain。")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                InfoBadge(
                    text: headerStatusText,
                    systemImage: headerStatusIcon,
                    tint: headerStatusTint
                )
                Text(appState.keychainStatusMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(24)
    }

    private var statusBanners: some View {
        HStack(spacing: 12) {
            FeedbackBanner(
                title: configurationBannerTitle,
                detail: appState.validationMessage,
                systemImage: configurationBannerIcon,
                tint: configurationBannerTint
            )
            FeedbackBanner(
                title: appState.isKeychainSaved ? "Keychain 已保存 / Saved" : "Keychain 待保存 / Pending",
                detail: appState.keychainStatusMessage,
                systemImage: appState.isKeychainSaved ? "key.fill" : "key",
                tint: appState.isKeychainSaved ? .green : .blue
            )
        }
    }

    private var headerStatusText: String {
        guard appState.hasValidatedConfiguration else { return "待校验 / Check needed" }
        return appState.isConfigurationValid ? "配置可用 / Valid" : "需要调整 / Needs changes"
    }

    private var headerStatusIcon: String {
        guard appState.hasValidatedConfiguration else { return "exclamationmark.triangle" }
        return appState.isConfigurationValid ? "checkmark.seal.fill" : "exclamationmark.triangle"
    }

    private var headerStatusTint: Color {
        guard appState.hasValidatedConfiguration else { return .orange }
        return appState.isConfigurationValid ? .green : .orange
    }

    private var configurationBannerTitle: String {
        guard appState.hasValidatedConfiguration else { return "尚未运行检查 / Not checked yet" }
        return appState.isConfigurationValid ? "配置检查通过 / Config OK" : "配置需要调整 / Needs changes"
    }

    private var configurationBannerIcon: String {
        guard appState.hasValidatedConfiguration else { return "info.circle" }
        return appState.isConfigurationValid ? "checkmark.seal.fill" : "exclamationmark.triangle"
    }

    private var configurationBannerTint: Color {
        guard appState.hasValidatedConfiguration else { return .blue }
        return appState.isConfigurationValid ? .green : .orange
    }

    private var actionBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            if appState.hasPendingProviderKey {
                keychainConfirmationBar
            }

            HStack(spacing: 12) {
                Button {
                    appState.validateConfiguration()
                } label: {
                    Label("检查配置 / Check", systemImage: "checkmark.circle")
                }
                .controlSize(.large)

                Button {
                    appState.saveProviderKeysToKeychain()
                } label: {
                    Label("保存 Key / Save Keys", systemImage: "key.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!appState.canSaveProviderKeys)

                saveKeyStatusPill

                Spacer()
            }
        }
        .padding(24)
        .background(.bar)
    }

    private var saveKeyStatusPill: some View {
        let tint = saveKeyStatusTint
        return Label(appState.saveKeysDisabledReason, systemImage: saveKeyStatusIcon)
            .font(.headline.weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(tint.opacity(0.14))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(tint.opacity(0.35), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var saveKeyStatusIcon: String {
        if appState.canSaveProviderKeys { return "checkmark.circle.fill" }
        if appState.isKeychainSaved { return "checkmark.seal.fill" }
        return "exclamationmark.circle.fill"
    }

    private var saveKeyStatusTint: Color {
        if appState.canSaveProviderKeys || appState.isKeychainSaved { return .green }
        if appState.hasPendingProviderKey { return .orange }
        return .blue
    }

    private var keychainConfirmationBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                Toggle("已核对账号 / Accounts reviewed", isOn: $appState.keychainWriteConfirmation.reviewedAccounts)
                    .toggleStyle(.checkbox)
                Toggle("确认写入 Keychain / Confirm Keychain write", isOn: $appState.keychainWriteConfirmation.understandsKeychainWrite)
                    .toggleStyle(.checkbox)
                TextField("输入大写 KEYCHAIN / Type KEYCHAIN", text: $appState.keychainWriteConfirmation.typedPhrase)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .frame(width: 260)
                Spacer()
            }
            Text("保存按钮会在两个确认框都勾选，并输入大写 KEYCHAIN 后启用。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
