import Foundation
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
    func sidebarSectionsExposeStartConfiguration() {
        let titles = AppState.Section.allCases.map(\.title)

        #expect(titles.contains("启动配置 / Start"))
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

    @Test
    @MainActor
    func appStateRequiresInstallGateBeforeRunningInstaller() async {
        var installCallCount = 0
        let state = AppState(installationExecutor: { _, _ in
            installCallCount += 1
            return SmokeTests.successfulInstallationResult()
        })

        state.validateConfiguration()
        await state.runInstallation()

        #expect(installCallCount == 0)
        #expect(state.installationStatusMessage.contains("完成确认"))
    }

    @Test
    @MainActor
    func appStateRunsInjectedInstallerAndRecordsResult() async {
        let state = AppState(installationExecutor: { _, confirmation in
            #expect(confirmation.canProceed)
            return SmokeTests.successfulInstallationResult()
        })
        state.validateConfiguration()
        state.installationConfirmation.reviewedDryRun = true
        state.installationConfirmation.createdBackups = true
        state.installationConfirmation.understandsSystemChanges = true
        state.installationConfirmation.typedPhrase = "INSTALL"

        await state.runInstallation()

        #expect(state.installationStatusMessage.contains("安装完成"))
        #expect(state.proxyStatusLabel.contains("运行中"))
        #expect(state.installationCommandRecords.map(\.title) == ["Bootstrap LaunchAgent"])
        #expect(state.installationVerificationSummary?.isPassing == true)
        #expect(state.backupManifestPath == "/tmp/manifest.json")
    }

    @Test
    @MainActor
    func appStateCanRecheckInstalledProxyWithoutReinstalling() async {
        let state = AppState(verificationExecutor: { _ in
            SmokeTests.successfulVerificationSummary()
        })

        await state.recheckInstallation()

        #expect(state.installationVerificationSummary?.isPassing == true)
        #expect(state.installationStatusMessage.contains("验证通过"))
        #expect(state.proxyStatusLabel.contains("运行中"))
    }

    @Test
    @MainActor
    func appStateRequiresRestoreGateBeforeRestoringFactoryDefaults() async {
        var restoreCallCount = 0
        let state = AppState(factoryRestoreExecutor: { _, _ in
            restoreCallCount += 1
            return SmokeTests.successfulFactoryRestoreResult()
        })

        await state.restoreFactoryDefaults()

        #expect(restoreCallCount == 0)
        #expect(state.factoryRestoreStatusMessage.contains("完成确认"))
    }

    @Test
    @MainActor
    func appStateRunsInjectedFactoryRestoreAndRecordsResult() async {
        let state = AppState(factoryRestoreExecutor: { _, confirmation in
            #expect(confirmation.canProceed)
            return SmokeTests.successfulFactoryRestoreResult()
        })
        state.factoryRestoreConfirmation.reviewedBackups = true
        state.factoryRestoreConfirmation.understandsOfficialDefaults = true
        state.factoryRestoreConfirmation.typedPhrase = "RESTORE"

        await state.restoreFactoryDefaults()

        #expect(state.factoryRestoreStatusMessage.contains("已还原"))
        #expect(state.proxyStatusLabel.contains("官方服务"))
        #expect(state.factoryRestoreCommandRecords.map(\.title) == ["Stop LaunchAgent"])
        #expect(state.factoryRestoreBackupManifestPath == "/tmp/restore-manifest.json")
    }

    private static func successfulInstallationResult() -> InstallationExecutionResult {
        let config = SetupConfiguration.default
        let installRoot = URL(fileURLWithPath: "/tmp/CJLocalProxy")
        let proxyDirectory = installRoot.appendingPathComponent("claude-local-proxy")
        let manifestURL = URL(fileURLWithPath: "/tmp/manifest.json")
        let summary = successfulVerificationSummary()

        return InstallationExecutionResult(
            backupResult: BackupResult(
                manifest: BackupManifest(version: 1, createdAt: "20260518193000", entries: []),
                manifestURL: manifestURL
            ),
            localInstallationResult: LocalInstallationResult(
                installRoot: installRoot,
                proxyDirectory: proxyDirectory,
                launchAgentPlistURL: URL(fileURLWithPath: "/tmp/com.cj.proxy.plist"),
                openSSLConfigURL: proxyDirectory.appendingPathComponent("certs/openssl-server.cnf"),
                launchCommands: LaunchAgentService(label: "com.cj.proxy").controlCommands(
                    plistURL: URL(fileURLWithPath: "/tmp/com.cj.proxy.plist"),
                    userID: 501
                ),
                trustCommand: ["security", "add-trusted-cert"],
                verificationSummary: VerificationService.pendingSummary(config: config)
            ),
            commandRecords: [
                InstallationCommandRecord(
                    title: "Bootstrap LaunchAgent",
                    command: ["launchctl", "bootstrap"],
                    exitCode: 0,
                    stdout: "ok",
                    stderr: ""
                ),
            ],
            verificationSummary: summary
        )
    }

    private static func successfulVerificationSummary() -> VerificationSummary {
        VerificationSummary(
            checks: [
                VerificationCheck(
                    name: "Proxy health",
                    url: URL(string: "https://127.0.0.1:38443/health"),
                    status: .passed,
                    detail: "HTTP 200"
                ),
            ]
        )
    }

    private static func successfulFactoryRestoreResult() -> FactoryRestoreResult {
        FactoryRestoreResult(
            backupResult: BackupResult(
                manifest: BackupManifest(version: 1, createdAt: "20260519110000", entries: []),
                manifestURL: URL(fileURLWithPath: "/tmp/restore-manifest.json")
            ),
            commandRecords: [
                InstallationCommandRecord(
                    title: "Stop LaunchAgent",
                    command: ["launchctl", "bootout"],
                    exitCode: 0,
                    stdout: "ok",
                    stderr: ""
                ),
            ]
        )
    }
}
