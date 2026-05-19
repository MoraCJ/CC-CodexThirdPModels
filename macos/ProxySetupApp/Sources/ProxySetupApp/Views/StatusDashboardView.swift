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
                    StatusCard(
                        title: "Desktop Host / 运行组件",
                        value: appState.claudeDesktopHostStatus?.isHostBinaryReady == true
                            ? "Ready"
                            : "Needs check",
                        systemImage: "desktopcomputer.and.arrow.down",
                        tint: appState.claudeDesktopHostStatus?.isHostBinaryReady == true ? .green : .orange
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
                    title: "Token 用量 / Token Usage",
                    subtitle: appState.telemetryStatusMessage,
                    systemImage: "chart.bar.xaxis"
                ) {
                    UsageSummaryView(snapshot: appState.telemetrySnapshot)
                }

                SetupPanel(
                    title: "用量监控路径 / Usage Segmentation",
                    subtitle: "代理 dashboard 会按客户端来源拆分统计模型和用量。",
                    systemImage: "point.3.connected.trianglepath.dotted"
                ) {
                    clientPathGrid
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .task {
            await appState.refreshTelemetrySummary()
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
                    Task {
                        await appState.checkConfiguration()
                    }
                } label: {
                    Label("检查配置 / Check Setup", systemImage: "checkmark.circle")
                }
                .controlSize(.large)

                Button {
                    Task {
                        await appState.refreshTelemetrySummary()
                    }
                } label: {
                    Label(
                        appState.isRefreshingTelemetry ? "刷新中 / Refreshing" : "刷新用量 / Refresh Usage",
                        systemImage: appState.isRefreshingTelemetry ? "hourglass" : "arrow.clockwise"
                    )
                }
                .controlSize(.large)
                .disabled(appState.isRefreshingTelemetry)
            }
        }
    }

    private var clientPathGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
            endpointRow("Claude Desktop", value: appState.setupConfiguration.claudeDesktopBaseURL.absoluteString)
            endpointRow("Claude CLI", value: appState.setupConfiguration.claudeCLIBaseURL.absoluteString)
            endpointRow("Codex App", value: appState.setupConfiguration.codexAppBaseURL.absoluteString)
            endpointRow("Codex CLI", value: appState.setupConfiguration.codexCLIBaseURL.absoluteString)
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

private struct UsageSummaryView: View {
    let snapshot: TelemetrySnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let snapshot {
                HStack(spacing: 12) {
                    UsageMetricCard(title: "Requests / 请求", value: snapshot.summary.total.requests)
                    UsageMetricCard(title: "Failures / 失败", value: snapshot.summary.total.failures)
                    UsageMetricCard(title: "Input / 输入", value: snapshot.summary.total.inputTokens)
                    UsageMetricCard(title: "Output / 输出", value: snapshot.summary.total.outputTokens)
                    UsageMetricCard(title: "Total / 总计", value: snapshot.summary.total.totalTokens)
                }

                UsageBucketTable(
                    title: "按客户端 / By Client",
                    rows: orderedRows(snapshot.summary.byClient, preferredKeys: [
                        "claude_desktop",
                        "claude_cli",
                        "codex_app",
                        "codex_cli",
                    ])
                )

                UsageBucketTable(
                    title: "按模型 / By Model",
                    rows: orderedRows(snapshot.summary.byModel, preferredKeys: [])
                )
            } else {
                Label("还没有读取到用量数据；代理启动后可点击刷新用量。", systemImage: "chart.bar")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func orderedRows(
        _ buckets: [String: TelemetryBucket],
        preferredKeys: [String]
    ) -> [(String, TelemetryBucket)] {
        let preferred = preferredKeys.compactMap { key in
            buckets[key].map { (clientTitle(key), $0) }
        }
        let remaining = buckets
            .filter { !preferredKeys.contains($0.key) }
            .sorted { $0.key < $1.key }
            .map { (clientTitle($0.key), $0.value) }
        return preferred + remaining
    }

    private func clientTitle(_ key: String) -> String {
        switch key {
        case "claude_desktop": return "Claude Desktop / Claude 桌面端"
        case "claude_cli": return "Claude CLI / Claude 命令行"
        case "codex_app": return "Codex App / Codex 桌面端"
        case "codex_cli": return "Codex CLI / Codex 命令行"
        default: return key
        }
    }
}

private struct UsageMetricCard: View {
    let title: String
    let value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value.formatted())
                .font(.title2.bold())
                .monospacedDigit()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct UsageBucketTable: View {
    let title: String
    let rows: [(String, TelemetryBucket)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                GridRow {
                    Text("名称 / Name")
                    Text("请求 / Req")
                    Text("失败 / Fail")
                    Text("输入 / In")
                    Text("输出 / Out")
                    Text("总计 / Total")
                    Text("耗时 / Latency")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                ForEach(rows, id: \.0) { name, bucket in
                    GridRow {
                        Text(name)
                        Text(bucket.requests.formatted())
                        Text(bucket.failures.formatted())
                        Text(bucket.inputTokens.formatted())
                        Text(bucket.outputTokens.formatted())
                        Text(bucket.totalTokens.formatted())
                        Text("\(bucket.latencyMsAverage)ms")
                    }
                    .font(.callout)
                }
            }
            if rows.isEmpty {
                Text("暂无数据 / No data")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
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
