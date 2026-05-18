import SwiftUI

struct StatusDashboardView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                HStack(spacing: 12) {
                    StatusCard(
                        title: "Proxy / 代理",
                        value: appState.proxyStatusLabel,
                        systemImage: "bolt.horizontal.circle",
                        tint: .blue
                    )
                    StatusCard(
                        title: "LaunchAgent / 开机启动",
                        value: "RunAtLoad + KeepAlive",
                        systemImage: "powerplug",
                        tint: .green
                    )
                    StatusCard(
                        title: "Certificate / 证书",
                        value: "本机 CA + SAN",
                        systemImage: "lock.shield",
                        tint: .purple
                    )
                }

                SetupPanel(
                    title: "准备状态 / Setup Readiness",
                    subtitle: "开始安装前最关键的几项检查。",
                    systemImage: "list.bullet.clipboard"
                ) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 14)], spacing: 14) {
                        ForEach(appState.readinessItems) { item in
                            ReadinessRow(item: item)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                SetupPanel(
                    title: "用量监控路径 / Usage Segmentation",
                    subtitle: "代理 dashboard 会按客户端来源拆分统计模型和用量。",
                    systemImage: "chart.bar.xaxis"
                ) {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                        endpointRow("Claude Desktop", value: appState.setupConfiguration.claudeDesktopBaseURL.absoluteString)
                        endpointRow("Claude CLI", value: appState.setupConfiguration.claudeCLIBaseURL.absoluteString)
                        endpointRow("Codex App", value: appState.setupConfiguration.codexAppBaseURL.absoluteString)
                        endpointRow("Codex CLI", value: appState.setupConfiguration.codexCLIBaseURL.absoluteString)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("CJ Local Proxy")
                    .font(.largeTitle.bold())
                Text("Claude Code 与 Codex 的本机第三方模型代理。")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    InfoBadge(text: "Desktop / CLI 分流", systemImage: "arrow.triangle.branch", tint: .blue)
                    InfoBadge(text: "Keychain 安全存储", systemImage: "key.fill", tint: .green)
                    InfoBadge(text: "开机自启", systemImage: "power", tint: .purple)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 10) {
                Button {
                    appState.openDashboard()
                } label: {
                    Label("打开 Dashboard / Open Dashboard", systemImage: "safari")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    appState.validateConfiguration()
                } label: {
                    Label("检查配置 / Check Setup", systemImage: "checkmark.circle")
                }
                .controlSize(.large)
            }
        }
    }

    private func endpointRow(_ label: String, value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title3, design: .monospaced))
                .textSelection(.enabled)
        }
    }
}

private struct StatusCard: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(tint)
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .lineLimit(2)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
