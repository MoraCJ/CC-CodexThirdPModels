import SwiftUI
import Darwin

struct VerificationResultsView: View {
    @EnvironmentObject private var appState: AppState

    let config: SetupConfiguration
    private let configService = ClientConfigService()
    private var summary: VerificationSummary {
        appState.installationVerificationSummary ?? VerificationService.pendingSummary(config: config)
    }
    private var installationPlanResult: Result<[InstallationPlanItem], Error> {
        Result {
            try LocalInstallationService().buildPlan(config: config)
        }
    }
    private var dryRunResult: Result<[DryRunFileDiff], Error> {
        Result {
            let changes = try LocalInstallationService().managedFileChanges(config: config) +
                ClientConfigService().managedClientConfigChanges(config: config)
            return try InstallationSafetyService().dryRun(changes: changes)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SetupPanel(
                    title: "验证端点 / Verification Endpoints",
                    subtitle: "这些 URL 会区分 Claude Desktop、Claude CLI、Codex App、Codex CLI 的请求来源。",
                    systemImage: "checkmark.seal"
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label(
                                appState.isVerifyingInstallation
                                    ? "正在重新验证 / Rechecking..."
                                    : "安装后如出现 HTTP 000，可等待几秒后重新验证。",
                                systemImage: appState.isVerifyingInstallation ? "hourglass" : "arrow.clockwise.circle"
                            )
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(appState.isVerifyingInstallation ? .blue : .secondary)

                            Spacer()

                            Button {
                                Task {
                                    await appState.recheckInstallation()
                                }
                            } label: {
                                Label("重新验证 / Recheck", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(appState.isInstalling || appState.isVerifyingInstallation)
                        }

                        ForEach(summary.checks, id: \.name) { check in
                            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                                GridRow {
                                    Label(check.name, systemImage: verificationIcon(check.status))
                                        .foregroundStyle(verificationTint(check.status))
                                    Text(check.url?.absoluteString ?? "")
                                        .font(.system(.title3, design: .monospaced))
                                        .lineLimit(1)
                                        .textSelection(.enabled)
                                }
                                GridRow {
                                    Text("")
                                    Text(check.detail)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                SetupPanel(
                    title: "启动与证书命令 / Launch & Certificate Commands",
                    subtitle: "点击执行安装前可在此审查命令；执行时会按这些命令运行。",
                    systemImage: "terminal"
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        let home = NSHomeDirectory()
                        let launchAgent = LaunchAgentService(label: "com.cj.claude-local-https-proxy")
                        let commands = launchAgent.controlCommands(
                            plistURL: URL(fileURLWithPath: "\(home)/Library/LaunchAgents/com.cj.claude-local-https-proxy.plist"),
                            userID: Int(getuid())
                        )
                        commandRow("Bootstrap", command: commands.bootstrap)
                        commandRow("Kickstart", command: commands.kickstart)
                        commandRow("Status", command: commands.printStatus)
                        commandRow(
                            "Trust CA",
                            command: CertificateService().trustCommand(
                                certsDirectory: URL(fileURLWithPath: "\(home)/Library/Application Support/CJLocalProxy/claude-local-proxy/certs"),
                                loginKeychainPath: "\(home)/Library/Keychains/login.keychain-db"
                            )
                        )
                    }
                }

                SetupPanel(
                    title: "安装计划 / Installation Plan",
                    subtitle: "按顺序展示本机部署会进行的文件写入、LaunchAgent 和验证步骤。",
                    systemImage: "checklist"
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        switch installationPlanResult {
                        case .success(let items):
                            ForEach(items) { item in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title)
                                        .font(.headline)
                                    Text(item.detail)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                        .textSelection(.enabled)
                                }
                                .padding(.vertical, 2)
                            }
                        case .failure(let error):
                            Label(
                                "安装计划暂不可用 / Installation plan unavailable",
                                systemImage: "exclamationmark.triangle"
                            )
                            .foregroundStyle(.orange)
                            Text(error.localizedDescription)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }

                SetupPanel(
                    title: "安全边界 / Safety Boundary",
                    subtitle: "默认先预览；只有完成确认并点击执行安装后才会写入和启动。",
                    systemImage: "hand.raised"
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        safetyRow("安装前先查看 dry-run diff / Review dry-run before install")
                        safetyRow("写入前创建备份 manifest / Backup manifest before writes")
                        safetyRow("真实 API Key 仍只保存在 Keychain / Real API keys stay in Keychain")
                        safetyRow("执行安装会写入客户端配置与 LaunchAgent / Install writes client config and LaunchAgent")
                        safetyRow("执行安装会生成证书并启动代理 / Install creates certs and starts proxy")
                    }
                }

                SetupPanel(
                    title: "Dry-run Diff / 差异预览",
                    subtitle: "只读检查目标文件；不会写入、备份或执行系统命令。",
                    systemImage: "doc.text.magnifyingglass"
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        switch dryRunResult {
                        case .success(let diffs):
                            ForEach(diffs) { diff in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(diff.change.title)
                                            .font(.headline)
                                        InfoBadge(
                                            text: diff.kind.rawValue,
                                            systemImage: diffIcon(diff.kind),
                                            tint: diffTint(diff.kind)
                                        )
                                    }
                                    Text(diff.change.targetURL.path)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .textSelection(.enabled)
                                    Text(diff.preview)
                                        .font(.system(.callout, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(6)
                                        .textSelection(.enabled)
                                }
                                .padding(.vertical, 4)
                            }
                        case .failure(let error):
                            Label(
                                "Dry-run 暂不可用 / Dry-run unavailable",
                                systemImage: "exclamationmark.triangle"
                            )
                            .foregroundStyle(.orange)
                            Text(error.localizedDescription)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }

                SetupPanel(
                    title: "执行安装 / Install & Start",
                    subtitle: "完成确认后，App 会备份文件、写入配置、生成证书、启动 LaunchAgent，并立即验证代理端点。",
                    systemImage: "play.circle"
                ) {
                    installationGateView
                }

                SetupPanel(
                    title: "客户端路径 / Client Paths",
                    subtitle: "固定前缀让 dashboard 能分别统计 desktop、cli、app 用量。",
                    systemImage: "point.3.connected.trianglepath.dotted"
                ) {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                        pathRow("Claude Desktop", value: config.claudeDesktopBaseURL.absoluteString)
                        pathRow("Claude CLI", value: config.claudeCLIBaseURL.absoluteString)
                        pathRow("Codex App", value: config.codexAppBaseURL.absoluteString)
                        pathRow("Codex CLI", value: config.codexCLIBaseURL.absoluteString)
                    }
                }

                SetupPanel(
                    title: "配置预览 / Config Preview",
                    subtitle: "预览只包含本地占位 token，不包含真实 provider API Key。",
                    systemImage: "doc.plaintext"
                ) {
                    DisclosureGroup("Claude CLI settings.json") {
                        previewText((try? configService.renderClaudeSettings(config: config)) ?? "{}")
                    }
                    DisclosureGroup("Claude Desktop gateway") {
                        previewText((try? configService.renderClaudeDesktopGatewayConfig(config: config)) ?? "{}")
                    }
                    DisclosureGroup("Codex config.toml") {
                        previewText(configService.renderCodexConfig(config: config))
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var installationGateView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Label(
                    appState.installationStatusMessage,
                    systemImage: installationStatusIcon
                )
                .font(.headline.weight(.semibold))
                .foregroundStyle(installationStatusTint)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(installationStatusTint.opacity(0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(installationStatusTint.opacity(0.35), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Button {
                    Task {
                        await appState.runInstallation()
                    }
                } label: {
                    Label(
                        appState.isInstalling ? "正在安装 / Installing" : "执行安装 / Install & Start",
                        systemImage: appState.isInstalling ? "hourglass" : "play.fill"
                    )
                    .frame(minWidth: 210)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!appState.canRunInstallation)

                Button {
                    Task {
                        await appState.recheckInstallation()
                    }
                } label: {
                    Label(
                        appState.isVerifyingInstallation ? "验证中 / Rechecking" : "重新验证 / Recheck",
                        systemImage: appState.isVerifyingInstallation ? "hourglass" : "arrow.clockwise"
                    )
                    .frame(minWidth: 170)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(appState.isInstalling || appState.isVerifyingInstallation)
            }

            Label(
                appState.installationDisabledReason,
                systemImage: appState.canRunInstallation ? "checkmark.circle.fill" : "info.circle.fill"
            )
            .font(.headline)
            .foregroundStyle(appState.canRunInstallation ? .green : .orange)

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    Toggle(
                        "已查看差异预览 / Dry-run reviewed",
                        isOn: $appState.installationConfirmation.reviewedDryRun
                    )
                    .toggleStyle(.checkbox)

                    Toggle(
                        "允许创建备份 / Backups allowed",
                        isOn: $appState.installationConfirmation.createdBackups
                    )
                    .toggleStyle(.checkbox)

                    Toggle(
                        "理解系统变更 / System changes understood",
                        isOn: $appState.installationConfirmation.understandsSystemChanges
                    )
                    .toggleStyle(.checkbox)
                }
                GridRow {
                    Text("确认词 / Confirm")
                        .foregroundStyle(.secondary)
                    TextField("输入大写 INSTALL / Type INSTALL", text: $appState.installationConfirmation.typedPhrase)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.large)
                        .frame(minWidth: 260)
                    Text("按钮会在配置检查通过并输入 INSTALL 后启用。")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout.weight(.semibold))

            if let backupManifestPath = appState.backupManifestPath {
                Label("备份 manifest / Backup manifest: \(backupManifestPath)", systemImage: "archivebox.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.green)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }

            if !appState.installationCommandRecords.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("执行记录 / Command Log")
                        .font(.headline)
                    ForEach(appState.installationCommandRecords) { record in
                        VStack(alignment: .leading, spacing: 4) {
                            Label(
                                record.title,
                                systemImage: record.succeeded ? "checkmark.circle.fill" : "xmark.octagon.fill"
                            )
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(record.succeeded ? .green : .red)
                            Text(record.command.joined(separator: " "))
                                .font(.system(.callout, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .textSelection(.enabled)
                            if !record.stderr.isEmpty {
                                Text(record.stderr)
                                    .font(.callout)
                                    .foregroundStyle(.red)
                                    .lineLimit(3)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
        }
    }

    private var installationStatusIcon: String {
        if appState.isInstalling || appState.isVerifyingInstallation { return "hourglass" }
        if appState.installationStatusMessage.contains("完成") ||
            appState.installationStatusMessage.contains("验证通过") {
            return "checkmark.seal.fill"
        }
        if appState.installationStatusMessage.contains("失败") ||
            appState.installationStatusMessage.contains("未通过") {
            return "xmark.octagon.fill"
        }
        return "info.circle.fill"
    }

    private var installationStatusTint: Color {
        if appState.isInstalling || appState.isVerifyingInstallation { return .blue }
        if appState.installationStatusMessage.contains("完成") ||
            appState.installationStatusMessage.contains("验证通过") {
            return .green
        }
        if appState.installationStatusMessage.contains("失败") ||
            appState.installationStatusMessage.contains("未通过") {
            return .red
        }
        return .orange
    }

    private func verificationIcon(_ status: VerificationStatus) -> String {
        switch status {
        case .notRun: return "circle.dashed"
        case .passed: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        }
    }

    private func verificationTint(_ status: VerificationStatus) -> Color {
        switch status {
        case .notRun: return .secondary
        case .passed: return .green
        case .failed: return .red
        }
    }

    private func diffIcon(_ kind: ManagedFileChangeKind) -> String {
        switch kind {
        case .create: return "plus.circle"
        case .update: return "pencil.circle"
        case .unchanged: return "checkmark.circle"
        }
    }

    private func diffTint(_ kind: ManagedFileChangeKind) -> Color {
        switch kind {
        case .create: return .blue
        case .update: return .orange
        case .unchanged: return .green
        }
    }

    private func safetyRow(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.shield")
                .foregroundStyle(.green)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func commandRow(_ label: String, command: [String]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                Text(label)
                    .foregroundStyle(.secondary)
                Text(command.joined(separator: " "))
                    .font(.system(.title3, design: .monospaced))
                    .lineLimit(1)
                    .textSelection(.enabled)
            }
        }
    }

    private func pathRow(_ label: String, value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title3, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    private func previewText(_ text: String) -> some View {
        ScrollView(.horizontal) {
            Text(text)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 180)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.top, 8)
    }
}
