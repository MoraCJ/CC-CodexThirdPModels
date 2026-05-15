import AppKit
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var proxyStatusLabel: String = "未检测 / Not Checked"
    @Published var setupConfiguration: SetupConfiguration = .default
    @Published var selectedSection: Section? = .status
    @Published var selectedSetupTab: SetupTab = .provider
    @Published var claudeAPIKey: String = ""
    @Published var codexAPIKey: String = ""
    @Published var validationMessage: String = "尚未验证 / Not validated"
    @Published var keychainStatusMessage: String = "尚未保存 / Not saved"
    @Published var keychainWriteConfirmation = KeychainWriteConfirmation()

    enum Section: String, CaseIterable, Identifiable, Hashable {
        case status
        case setup
        case logs

        var id: String { rawValue }

        var title: String {
            switch self {
            case .status: return "状态 / Status"
            case .setup: return "设置向导 / Setup"
            case .logs: return "日志 / Logs"
            }
        }

        var systemImage: String {
            switch self {
            case .status: return "gauge.with.dots.needle.67percent"
            case .setup: return "wand.and.stars"
            case .logs: return "doc.text.magnifyingglass"
            }
        }
    }

    enum SetupTab: String, CaseIterable, Identifiable {
        case provider
        case models
        case verify

        var id: String { rawValue }

        var title: String {
            switch self {
            case .provider: return "服务商 / Provider"
            case .models: return "模型 / Models"
            case .verify: return "验证 / Verify"
            }
        }

        var systemImage: String {
            switch self {
            case .provider: return "network"
            case .models: return "slider.horizontal.3"
            case .verify: return "checkmark.seal"
            }
        }
    }

    var menuBarSystemImage: String {
        proxyStatusLabel.contains("运行") ? "bolt.horizontal.circle.fill" : "bolt.horizontal.circle"
    }

    var isConfigurationValid: Bool {
        (try? setupConfiguration.validate()) != nil
    }

    var readinessItems: [ReadinessItem] {
        [
            ReadinessItem(
                title: "Claude Provider",
                detail: setupConfiguration.claudeProvider.isEnabled
                    ? setupConfiguration.claudeProvider.protocolType.title
                    : "未启用 / Disabled",
                isReady: setupConfiguration.claudeProvider.isEnabled
            ),
            ReadinessItem(
                title: "Codex Provider",
                detail: setupConfiguration.codexProvider.isEnabled
                    ? setupConfiguration.codexProvider.protocolType.title
                    : "未启用 / Disabled",
                isReady: setupConfiguration.codexProvider.isEnabled
            ),
            ReadinessItem(
                title: "API Key",
                detail: hasPendingProviderKey ? "已输入待保存 / Entered, ready to save" : keychainStatusMessage,
                isReady: hasPendingProviderKey || keychainStatusMessage.contains("已保存")
            ),
            ReadinessItem(
                title: "Local Proxy",
                detail: "\(setupConfiguration.listenHost):\(setupConfiguration.listenPort)",
                isReady: isConfigurationValid
            ),
        ]
    }

    func openDashboard() {
        guard let url = URL(string: "https://127.0.0.1:38443/dashboard") else { return }
        NSWorkspace.shared.open(url)
    }

    func validateConfiguration() {
        do {
            try setupConfiguration.validate()
            validationMessage = "配置可用 / Configuration looks valid"
        } catch {
            validationMessage = "配置需要调整 / \(error.localizedDescription)"
        }
    }

    func saveProviderKeysToKeychain() {
        guard canSaveProviderKeys else {
            keychainStatusMessage = "需要确认后才能写入 Keychain / Confirm before saving"
            return
        }

        do {
            try setupConfiguration.validate()
            let keychain = KeychainService(serviceName: setupConfiguration.keychainService)
            var savedAccounts: [String] = []

            if setupConfiguration.claudeProvider.isEnabled, !claudeAPIKey.isEmpty {
                try keychain.save(claudeAPIKey, account: setupConfiguration.claudeProvider.keychainAccount)
                savedAccounts.append(setupConfiguration.claudeProvider.keychainAccount)
                claudeAPIKey = ""
            }

            if setupConfiguration.codexProvider.isEnabled, !codexAPIKey.isEmpty {
                try keychain.save(codexAPIKey, account: setupConfiguration.codexProvider.keychainAccount)
                savedAccounts.append(setupConfiguration.codexProvider.keychainAccount)
                codexAPIKey = ""
            }

            if savedAccounts.isEmpty {
                keychainStatusMessage = "未输入新 Key / No new key entered"
                return
            }

            keychainStatusMessage = "已保存到 Keychain / Saved: \(savedAccounts.joined(separator: ", "))"
            keychainWriteConfirmation = KeychainWriteConfirmation()
        } catch {
            keychainStatusMessage = "保存失败 / \(error.localizedDescription)"
        }
    }

    var hasPendingProviderKey: Bool {
        !claudeAPIKey.isEmpty || !codexAPIKey.isEmpty
    }

    var canSaveProviderKeys: Bool {
        hasPendingProviderKey && keychainWriteConfirmation.canSave
    }
}

struct ReadinessItem: Identifiable, Equatable {
    var id: String { title }
    var title: String
    var detail: String
    var isReady: Bool
}
