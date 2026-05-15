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
                                        .font(.system(.body, design: .monospaced))
                                        .lineLimit(1)
                                        .textSelection(.enabled)
                                }
                                GridRow {
                                    Text("")
                                    Text(check.detail)
                                        .font(.caption)
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
                                        .font(.subheadline.weight(.medium))
                                    Text(item.detail)
                                        .font(.caption)
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
                                .font(.caption)
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

    private func safetyRow(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.shield")
                .foregroundStyle(.green)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func commandRow(_ label: String, command: [String]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                Text(label)
                    .foregroundStyle(.secondary)
                Text(command.joined(separator: " "))
                    .font(.system(.body, design: .monospaced))
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
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    private func previewText(_ text: String) -> some View {
        ScrollView(.horizontal) {
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 180)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.top, 8)
    }
}
