import AppKit
import Foundation

@MainActor
final class AppState: ObservableObject {
    typealias InstallationExecutor = (SetupConfiguration, InstallationConfirmation) async throws -> InstallationExecutionResult

    @Published var proxyStatusLabel: String = "未检测 / Not Checked"
    @Published var setupConfiguration: SetupConfiguration = .default
    @Published var selectedSection: Section? = .status
    @Published var selectedSetupTab: SetupTab = .provider
    @Published var claudeAPIKey: String = ""
    @Published var codexAPIKey: String = ""
    @Published var validationMessage: String = "尚未验证 / Not validated"
    @Published var keychainStatusMessage: String = "尚未保存 / Not saved"
    @Published var keychainWriteConfirmation = KeychainWriteConfirmation()
    @Published var hasValidatedConfiguration = false
    @Published var installationConfirmation = InstallationConfirmation()
    @Published var installationStatusMessage: String = "尚未安装 / Not installed"
    @Published var installationCommandRecords: [InstallationCommandRecord] = []
    @Published var installationVerificationSummary: VerificationSummary?
    @Published var backupManifestPath: String?
    @Published var isInstalling = false

    private let installationExecutor: InstallationExecutor

    init(
        installationExecutor: @escaping InstallationExecutor = { config, confirmation in
            try await InstallationExecutionService().execute(
                config: config,
                confirmation: confirmation
            )
        }
    ) {
        self.installationExecutor = installationExecutor
    }

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
        hasValidatedConfiguration = true
        do {
            try setupConfiguration.validate()
            validationMessage = "配置可用，可以继续查看验证预览 / Configuration looks valid"
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

    var saveKeysDisabledReason: String {
        if !hasPendingProviderKey {
            return keychainStatusMessage.contains("已保存")
                ? "已保存；如需替换，请重新粘贴 API Key。"
                : "请输入至少一个 API Key。"
        }
        if !keychainWriteConfirmation.reviewedAccounts {
            return "请先勾选已核对账号。"
        }
        if !keychainWriteConfirmation.understandsKeychainWrite {
            return "请确认写入 macOS Keychain。"
        }
        if keychainWriteConfirmation.typedPhrase != "KEYCHAIN" {
            return "请输入大写 KEYCHAIN 解锁保存。"
        }
        return "可以保存到 Keychain。"
    }

    var isKeychainSaved: Bool {
        keychainStatusMessage.contains("已保存")
    }

    var canRunInstallation: Bool {
        hasValidatedConfiguration &&
            isConfigurationValid &&
            installationConfirmation.canProceed &&
            !isInstalling
    }

    var installationDisabledReason: String {
        if isInstalling {
            return "正在安装与验证，请稍候。"
        }
        if !hasValidatedConfiguration {
            return "请先点击检查配置。"
        }
        if !isConfigurationValid {
            return "请先修正配置错误。"
        }
        if !installationConfirmation.reviewedDryRun {
            return "请先确认已查看差异预览。"
        }
        if !installationConfirmation.createdBackups {
            return "请确认安装会先创建备份。"
        }
        if !installationConfirmation.understandsSystemChanges {
            return "请确认理解 LaunchAgent、证书和客户端配置变更。"
        }
        if installationConfirmation.typedPhrase != "INSTALL" {
            return "请输入大写 INSTALL 解锁安装。"
        }
        return "可以执行安装并启动本机代理。"
    }

    func runInstallation() async {
        guard canRunInstallation else {
            installationStatusMessage = "安装前请完成确认 / \(installationDisabledReason)"
            return
        }

        isInstalling = true
        installationStatusMessage = "正在安装并启动代理 / Installing and starting proxy..."
        installationCommandRecords = []
        installationVerificationSummary = nil
        backupManifestPath = nil

        do {
            let result = try await installationExecutor(setupConfiguration, installationConfirmation)
            installationCommandRecords = result.commandRecords
            installationVerificationSummary = result.verificationSummary
            backupManifestPath = result.backupResult.manifestURL.path
            proxyStatusLabel = result.verificationSummary.isPassing
                ? "运行中 / Running"
                : "已安装，验证未完全通过 / Installed, verification needs attention"
            installationStatusMessage = result.verificationSummary.isPassing
                ? "安装完成并验证通过 / Installed and verified"
                : "安装完成，但部分验证失败 / Installed, but verification needs attention"
        } catch {
            installationStatusMessage = "安装失败 / \(error.localizedDescription)"
            proxyStatusLabel = "安装失败 / Install failed"
        }

        isInstalling = false
    }
}

struct ReadinessItem: Identifiable, Equatable {
    var id: String { title }
    var title: String
    var detail: String
    var isReady: Bool
}
