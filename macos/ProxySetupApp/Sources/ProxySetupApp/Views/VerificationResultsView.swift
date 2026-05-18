import SwiftUI
import Darwin

struct VerificationResultsView: View {
    let config: SetupConfiguration
    private let configService = ClientConfigService()
    private var summary: VerificationSummary {
        VerificationService.pendingSummary(config: config)
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
                        ForEach(summary.checks, id: \.name) { check in
                            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                                GridRow {
                                    Label(check.name, systemImage: "circle.dashed")
                                        .foregroundStyle(.secondary)
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
                    subtitle: "App 后续执行这些命令；当前预览不自动运行 launchctl 或 security。",
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
                    subtitle: "当前页面只展示计划和预览；真实安装必须由用户显式触发。",
                    systemImage: "hand.raised"
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        safetyRow("不自动修改 ~/.codex/config.toml")
                        safetyRow("不自动修改 ~/.claude/settings.json")
                        safetyRow("不自动写真实 ~/Library/LaunchAgents")
                        safetyRow("不执行 launchctl、security 或 openssl")
                        safetyRow("真实 API Key 只通过保存 Key 按钮进入 Keychain")
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
                    title: "执行门禁 / Execution Gate",
                    subtitle: "未来接入真实安装按钮前必须满足这些确认条件。",
                    systemImage: "checkmark.shield"
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(InstallationConfirmation.requirements) { item in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title)
                                    .font(.headline)
                                Text(item.detail)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
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
