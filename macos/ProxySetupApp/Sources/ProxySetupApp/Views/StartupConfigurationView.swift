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
                        subtitle: "从这里完成检查、安装启动、重新验证；需要回到官方服务时也在这里还原。",
                        systemImage: "power.circle.fill"
                    ) {
                        VStack(alignment: .leading, spacing: 16) {
                            actionButtons
                            readinessGrid
                            verificationStrip
                        }
                    }

                    SetupPanel(
                        title: "安装并启动 / Install & Start",
                        subtitle: "备份文件后写入配置、生成证书、启动 LaunchAgent，并立即验证代理端点。",
                        systemImage: "play.circle.fill"
                    ) {
                        InstallStartControlsView()
                    }

                    SetupPanel(
                        title: "还原原厂服务 / Restore Official Defaults",
                        subtitle: "一键把 Claude 与 Codex 从本机代理配置恢复到官方默认服务，方便随时切回原厂。",
                        systemImage: "arrow.uturn.backward.circle.fill"
                    ) {
                        FactoryRestoreControlsView()
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
                Text("最常用的启动、验证和还原操作集中在这里；设置 Base URL 与模型仍在设置向导中完成。")
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
                appState.validateConfiguration()
            } label: {
                Label("检查配置 / Check", systemImage: appState.isConfigurationValid ? "checkmark.seal.fill" : "checkmark.circle")
                    .frame(minWidth: 150)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(appState.hasValidatedConfiguration ? (appState.isConfigurationValid ? .green : .orange) : .blue)

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

private extension VerificationStatus {
    var shortTitle: String {
        switch self {
        case .notRun: return "待运行"
        case .passed: return "通过"
        case .failed: return "失败"
        }
    }
}
