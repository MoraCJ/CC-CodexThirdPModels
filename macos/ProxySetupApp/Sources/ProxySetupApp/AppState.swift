import AppKit
import Foundation

@MainActor
final class AppState: ObservableObject {
    typealias InstallationExecutor = (
        SetupConfiguration,
        InstallationConfirmation,
        InstallationProgressHandler?
    ) async throws -> InstallationExecutionResult
    typealias VerificationExecutor = (SetupConfiguration) async -> VerificationSummary
    typealias FactoryRestoreExecutor = (
        SetupConfiguration,
        FactoryRestoreConfirmation,
        InstallationProgressHandler?
    ) async throws -> FactoryRestoreResult

    @Published var proxyStatusLabel: String = "未检测 / Not Checked"
    @Published var setupConfiguration: SetupConfiguration = .default
    @Published var selectedSection: Section? = .status
    @Published var selectedSetupTab: SetupTab = .provider
    @Published var claudeAPIKey: String = ""
    @Published var codexAPIKey: String = ""
    @Published var validationMessage: String = "尚未验证 / Not validated"
    @Published var toolCheckResult: ToolCheckResult?
    @Published var isCheckingConfiguration = false
    @Published var keychainStatusMessage: String = "尚未保存 / Not saved"
    @Published var keychainWriteConfirmation = KeychainWriteConfirmation()
    @Published var hasValidatedConfiguration = false
    @Published var installationConfirmation = InstallationConfirmation()
    @Published var installationStatusMessage: String = "尚未安装 / Not installed"
    @Published var installationCommandRecords: [InstallationCommandRecord] = []
    @Published var installationProgressEvents: [InstallationProgressEvent] = []
    @Published var installationVerificationSummary: VerificationSummary?
    @Published var backupManifestPath: String?
    @Published var isInstalling = false
    @Published var isVerifyingInstallation = false
    @Published var factoryRestoreConfirmation = FactoryRestoreConfirmation()
    @Published var factoryRestoreStatusMessage: String = "尚未还原 / Not restored"
    @Published var factoryRestoreCommandRecords: [InstallationCommandRecord] = []
    @Published var factoryRestoreProgressEvents: [InstallationProgressEvent] = []
    @Published var factoryRestoreBackupManifestPath: String?
    @Published var isRestoringFactoryDefaults = false
    @Published var telemetrySnapshot: TelemetrySnapshot?
    @Published var telemetryStatusMessage: String = "尚未读取用量 / Usage not loaded"
    @Published var isRefreshingTelemetry = false

    private let installationExecutor: InstallationExecutor
    private let verificationExecutor: VerificationExecutor
    private let factoryRestoreExecutor: FactoryRestoreExecutor

    init(
        installationExecutor: @escaping InstallationExecutor = { config, confirmation, progress in
            try await InstallationExecutionService().execute(
                config: config,
                confirmation: confirmation,
                progress: progress
            )
        },
        verificationExecutor: @escaping VerificationExecutor = { config in
            await VerificationService().run(config: config)
        },
        factoryRestoreExecutor: @escaping FactoryRestoreExecutor = { config, confirmation, progress in
            try await FactoryRestoreService().restore(
                config: config,
                confirmation: confirmation,
                progress: progress
            )
        }
    ) {
        self.installationExecutor = installationExecutor
        self.verificationExecutor = verificationExecutor
        self.factoryRestoreExecutor = factoryRestoreExecutor
    }

    enum Section: String, CaseIterable, Identifiable, Hashable {
        case status
        case settings
        case start
        case restore
        case logs

        var id: String { rawValue }

        var title: String {
            switch self {
            case .status: return "状态 / Status"
            case .settings: return "设置 / Settings"
            case .start: return "启动配置 / Start"
            case .restore: return "还原配置 / Restore"
            case .logs: return "日志 / Logs"
            }
        }

        var systemImage: String {
            switch self {
            case .status: return "gauge.with.dots.needle.67percent"
            case .settings: return "slider.horizontal.3"
            case .start: return "power.circle.fill"
            case .restore: return "arrow.uturn.backward.circle.fill"
            case .logs: return "doc.text.magnifyingglass"
            }
        }
    }

    enum SetupTab: String, CaseIterable, Identifiable {
        case provider
        case models

        var id: String { rawValue }

        var title: String {
            switch self {
            case .provider: return "服务商 / Provider"
            case .models: return "模型 / Models"
            }
        }

        var systemImage: String {
            switch self {
            case .provider: return "network"
            case .models: return "slider.horizontal.3"
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
        var items = [
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
        if let toolCheckResult {
            items.append(
                ReadinessItem(
                    title: "Node",
                    detail: toolCheckResult.node.path.isEmpty
                        ? toolCheckResult.node.detail
                        : "\(toolCheckResult.node.path) \(toolCheckResult.node.version)",
                    isReady: toolCheckResult.node.status == .ok
                )
            )
        }
        return items
    }

    func openDashboard() {
        guard let url = URL(string: "https://127.0.0.1:38443/dashboard") else { return }
        NSWorkspace.shared.open(url)
    }

    func refreshTelemetrySummary() async {
        guard !isRefreshingTelemetry else { return }
        isRefreshingTelemetry = true
        do {
            let snapshot = try await TelemetryService().fetchSummary(config: setupConfiguration)
            telemetrySnapshot = snapshot
            telemetryStatusMessage = "已更新 / Updated: \(snapshot.generatedAt)"
        } catch {
            telemetryStatusMessage = "读取失败 / \(error.localizedDescription)"
        }
        isRefreshingTelemetry = false
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

    func checkConfiguration() async {
        isCheckingConfiguration = true
        hasValidatedConfiguration = true
        do {
            try setupConfiguration.validate()
            let tools = await PreflightService(runner: CommandRunner()).checkTools()
            toolCheckResult = tools
            validationMessage = tools.requiredToolsReady
                ? "配置与必需依赖可用 / Configuration and required dependencies look valid"
                : "缺少必需依赖 node；请先安装 Node.js 或修正 PATH。"
        } catch {
            validationMessage = "配置需要调整 / \(error.localizedDescription)"
        }
        isCheckingConfiguration = false
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
            (toolCheckResult?.requiredToolsReady == true) &&
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
        if toolCheckResult?.requiredToolsReady != true {
            return "请先点击检查配置，并确保 Node 可用。"
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

    var canRestoreFactoryDefaults: Bool {
        factoryRestoreConfirmation.canProceed &&
            !isInstalling &&
            !isRestoringFactoryDefaults
    }

    var factoryRestoreDisabledReason: String {
        if isInstalling {
            return "正在安装与验证，请稍候。"
        }
        if isRestoringFactoryDefaults {
            return "正在还原配置，请稍候。"
        }
        if !factoryRestoreConfirmation.reviewedBackups {
            return "请确认还原前会创建备份。"
        }
        if !factoryRestoreConfirmation.understandsOfficialDefaults {
            return "请确认还原后 Claude 和 Codex 会回到官方服务。"
        }
        if factoryRestoreConfirmation.typedPhrase != "RESTORE" {
            return "请输入大写 RESTORE 解锁还原。"
        }
        return "可以还原 Claude 与 Codex 到官方服务。"
    }

    func runInstallation() async {
        guard canRunInstallation else {
            installationStatusMessage = "安装前请完成确认 / \(installationDisabledReason)"
            return
        }

        isInstalling = true
        installationStatusMessage = "正在安装并启动代理 / Installing and starting proxy..."
        installationCommandRecords = []
        installationProgressEvents = []
        installationVerificationSummary = nil
        backupManifestPath = nil

        do {
            let result = try await installationExecutor(
                setupConfiguration,
                installationConfirmation
            ) { [weak self] event in
                await MainActor.run {
                    self?.installationProgressEvents.append(event)
                    self?.installationStatusMessage = event.status.userFacingPrefix + event.title
                }
            }
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

    func recheckInstallation() async {
        guard !isInstalling, !isVerifyingInstallation else { return }

        isVerifyingInstallation = true
        installationStatusMessage = "正在重新验证代理 / Rechecking proxy..."

        let summary = await verificationExecutor(setupConfiguration)
        installationVerificationSummary = summary
        proxyStatusLabel = summary.isPassing
            ? "运行中 / Running"
            : "验证未通过 / Verification failed"
        installationStatusMessage = summary.isPassing
            ? "验证通过 / Verification passed"
            : "验证未通过，请稍后重试或查看代理日志 / Verification failed, retry or check proxy logs"

        isVerifyingInstallation = false
    }

    func restoreFactoryDefaults() async {
        guard canRestoreFactoryDefaults else {
            factoryRestoreStatusMessage = "恢复前请完成确认 / \(factoryRestoreDisabledReason)"
            return
        }

        isRestoringFactoryDefaults = true
        factoryRestoreStatusMessage = "正在还原官方服务配置 / Restoring official defaults..."
        factoryRestoreCommandRecords = []
        factoryRestoreProgressEvents = []
        factoryRestoreBackupManifestPath = nil

        do {
            let result = try await factoryRestoreExecutor(
                setupConfiguration,
                factoryRestoreConfirmation
            ) { [weak self] event in
                await MainActor.run {
                    self?.factoryRestoreProgressEvents.append(event)
                    self?.factoryRestoreStatusMessage = event.status.userFacingPrefix + event.title
                }
            }
            factoryRestoreCommandRecords = result.commandRecords
            factoryRestoreBackupManifestPath = result.backupResult.manifestURL.path
            installationVerificationSummary = nil
            installationStatusMessage = "已还原官方服务；如需代理，请重新执行安装。"
            factoryRestoreStatusMessage = "已还原官方服务 / Official defaults restored"
            proxyStatusLabel = "已还原官方服务 / Official defaults restored"
        } catch {
            factoryRestoreStatusMessage = "还原失败 / \(error.localizedDescription)"
        }

        isRestoringFactoryDefaults = false
    }
}

private extension InstallationProgressStatus {
    var userFacingPrefix: String {
        switch self {
        case .running:
            return "正在执行 / Running: "
        case .succeeded:
            return "完成 / Done: "
        case .failed:
            return "失败 / Failed: "
        case .skipped:
            return "跳过 / Skipped: "
        }
    }
}

struct ReadinessItem: Identifiable, Equatable {
    var id: String { title }
    var title: String
    var detail: String
    var isReady: Bool
}
