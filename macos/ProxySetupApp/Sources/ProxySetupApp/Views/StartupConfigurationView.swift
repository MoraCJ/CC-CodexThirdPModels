import SwiftUI

struct StartupConfigurationView: View {
    @EnvironmentObject private var appState: AppState

    private var summary: VerificationSummary {
        appState.installationVerificationSummary ?? VerificationService.pendingSummary(config: appState.setupConfiguration)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    SetupPanel(
                        title: "启动总览 / Start Overview",
                        subtitle: "从这里完成依赖探测、配置检查、安装启动和重新验证。",
                        systemImage: "power.circle.fill"
                    ) {
                        VStack(alignment: .leading, spacing: 16) {
                            actionButtons
                            readinessGrid
                            verificationStrip
                        }
                    }

                    SetupPanel(
                        title: "外部依赖 / External Dependencies",
                        subtitle: "安装前会先探测 node/npm/brew/claude/codex 的真实路径；node 缺失会阻断安装。",
                        systemImage: "point.3.connected.trianglepath.dotted"
                    ) {
                        DependencyChecksView(result: appState.toolCheckResult)
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
                                TextField("127.0.0.1", text: $appState.setupConfiguration.listenHost)
                                    .textFieldStyle(.roundedBorder)
                                    .controlSize(.large)
                            }
                            GridRow {
                                Text("Port")
                                    .foregroundStyle(.secondary)
                                Stepper(value: $appState.setupConfiguration.listenPort, in: 1024...65535) {
                                    Text("\(appState.setupConfiguration.listenPort)")
                                        .monospacedDigit()
                                }
                                .controlSize(.large)
                            }
                            GridRow {
                                Text("Keychain")
                                    .foregroundStyle(.secondary)
                                TextField("CJLocalProxy", text: $appState.setupConfiguration.keychainService)
                                    .textFieldStyle(.roundedBorder)
                                    .controlSize(.large)
                            }
                        }
                        .font(.body)
                    }

                    SetupPanel(
                        title: "安装并启动 / Install & Start",
                        subtitle: "备份文件后写入配置、生成证书、启动 LaunchAgent，并立即验证代理端点。",
                        systemImage: "play.circle.fill"
                    ) {
                        InstallStartControlsView()
                    }

                    SetupPanel(
                        title: "客户端路径 / Client Paths",
                        subtitle: "安装后 dashboard 会按这些路径区分 Claude Desktop、Claude CLI、Codex App、Codex CLI。",
                        systemImage: "point.3.connected.trianglepath.dotted"
                    ) {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                            pathRow("Claude Desktop", value: appState.setupConfiguration.claudeDesktopBaseURL.absoluteString)
                            pathRow("Claude CLI", value: appState.setupConfiguration.claudeCLIBaseURL.absoluteString)
                            pathRow("Codex App", value: appState.setupConfiguration.codexAppBaseURL.absoluteString)
                            pathRow("Codex CLI", value: appState.setupConfiguration.codexCLIBaseURL.absoluteString)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("启动配置 / Start Configuration")
                    .font(.title.bold())
                Text("依赖探测、启动安装和配置验证集中在这里；Base URL 与模型在设置页完成。")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            InfoBadge(
                text: appState.proxyStatusLabel,
                systemImage: appState.menuBarSystemImage,
                tint: appState.proxyStatusLabel.contains("运行") ? .green : .orange
            )
        }
        .padding(24)
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                Task {
                    await appState.checkConfiguration()
                }
            } label: {
                Label(
                    appState.isCheckingConfiguration ? "检查中 / Checking" : "检查配置 / Check",
                    systemImage: appState.isCheckingConfiguration ? "hourglass" : (appState.isConfigurationValid ? "checkmark.seal.fill" : "checkmark.circle")
                )
                    .frame(minWidth: 150)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(appState.hasValidatedConfiguration ? (appState.isConfigurationValid ? .green : .orange) : .blue)
            .disabled(appState.isCheckingConfiguration)

            Button {
                Task {
                    await appState.recheckInstallation()
                }
            } label: {
                Label(
                    appState.isVerifyingInstallation ? "验证中 / Rechecking" : "重新验证 / Recheck",
                    systemImage: appState.isVerifyingInstallation ? "hourglass" : "arrow.clockwise"
                )
                .frame(minWidth: 160)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(appState.isInstalling || appState.isVerifyingInstallation)

            Button {
                appState.openDashboard()
            } label: {
                Label("打开 Dashboard / Open Dashboard", systemImage: "safari")
                    .frame(minWidth: 230)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Spacer()
        }
    }

    private var readinessGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 30, verticalSpacing: 12) {
            GridRow {
                ForEach(appState.readinessItems.prefix(2)) { item in
                    ReadinessRow(item: item)
                }
            }
            GridRow {
                ForEach(appState.readinessItems.dropFirst(2)) { item in
                    ReadinessRow(item: item)
                }
            }
        }
    }

    private var verificationStrip: some View {
        HStack(spacing: 10) {
            ForEach(summary.checks.prefix(4), id: \.name) { check in
                InfoBadge(
                    text: "\(check.name): \(check.status.shortTitle)",
                    systemImage: verificationIcon(check.status),
                    tint: verificationTint(check.status)
                )
            }
            Spacer()
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
}

private struct DependencyChecksView: View {
    let result: ToolCheckResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let result {
                ForEach(result.allTools, id: \.name) { tool in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: icon(for: tool.status))
                            .foregroundStyle(tint(for: tool.status))
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text(tool.name)
                                    .font(.headline)
                                if tool.isRequired {
                                    InfoBadge(text: "必需 / Required", systemImage: "asterisk", tint: .red)
                                } else {
                                    InfoBadge(text: "可选 / Optional", systemImage: "info.circle", tint: .orange)
                                }
                            }
                            Text(tool.path.isEmpty ? tool.detail : "\(tool.path) \(tool.version)")
                                .font(.system(.callout, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .textSelection(.enabled)
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(tint(for: tool.status).opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            } else {
                Label("尚未探测依赖；点击检查配置后会显示真实路径。", systemImage: "info.circle")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func icon(for status: CheckStatus) -> String {
        switch status {
        case .ok: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .missing, .failed: return "xmark.octagon.fill"
        }
    }

    private func tint(for status: CheckStatus) -> Color {
        switch status {
        case .ok: return .green
        case .warning: return .orange
        case .missing, .failed: return .red
        }
    }
}

private extension VerificationStatus {
    var shortTitle: String {
        switch self {
        case .notRun: return "待运行"
        case .passed: return "通过"
        case .failed: return "失败"
        }
    }
}
