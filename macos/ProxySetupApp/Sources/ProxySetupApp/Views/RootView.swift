import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationSplitView {
            List(AppState.Section.allCases, selection: $appState.selectedSection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .font(.title3.weight(.semibold))
                    .padding(.vertical, 4)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 250, ideal: 280, max: 320)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    InfoBadge(
                        text: "本机部署 / Local only",
                        systemImage: "desktopcomputer",
                        tint: .green
                    )
                    Text("真实 API Key 只进入 Keychain。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } detail: {
            switch appState.selectedSection ?? .status {
            case .status:
                StatusDashboardView()
            case .settings:
                SetupWizardView()
            case .start:
                StartupConfigurationView()
            case .restore:
                RestoreConfigurationView()
            case .logs:
                LogsView()
            }
        }
        .frame(minWidth: 920, minHeight: 620)
    }
}

private struct RestoreConfigurationView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("还原配置 / Restore Configuration")
                        .font(.title.bold())
                    Text("把 Claude 与 Codex 从本机代理配置恢复到官方默认服务；真实 API Key 会继续保留在 Keychain。")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                InfoBadge(
                    text: appState.factoryRestoreStatusMessage,
                    systemImage: "arrow.uturn.backward.circle.fill",
                    tint: appState.factoryRestoreStatusMessage.contains("已还原") ? .green : .orange
                )
            }
            .padding(24)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    SetupPanel(
                        title: "还原原厂服务 / Restore Official Defaults",
                        subtitle: "停止本机 LaunchAgent，移除 Claude/Codex 中由本 App 写入的代理片段，并保留 Keychain 中的真实 API Key。",
                        systemImage: "arrow.uturn.backward.circle.fill"
                    ) {
                        FactoryRestoreControlsView()
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }
}

private struct LogsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("日志 / Logs")
                        .font(.title.bold())
                    Text("查看安装/还原步骤和代理运行日志；所有展示内容都会避免暴露 API Key。")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(24)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    SetupPanel(
                        title: "安装日志 / Install Log",
                        subtitle: "本次 App 会话内的安装执行状态。",
                        systemImage: "wrench.and.screwdriver"
                    ) {
                        ProgressEventsView(events: appState.installationProgressEvents)
                        CommandRecordsView(records: appState.installationCommandRecords)
                    }

                    SetupPanel(
                        title: "还原日志 / Restore Log",
                        subtitle: "本次 App 会话内的原厂配置还原状态。",
                        systemImage: "arrow.uturn.backward.circle"
                    ) {
                        ProgressEventsView(events: appState.factoryRestoreProgressEvents)
                        CommandRecordsView(records: appState.factoryRestoreCommandRecords)
                    }

                    SetupPanel(
                        title: "Desktop Host 日志 / Desktop Host Log",
                        subtitle: "查看 Claude Desktop 3P main.log，排查 host bundle、下载和初始化问题。",
                        systemImage: "desktopcomputer.and.arrow.down"
                    ) {
                        ClaudeDesktopLogTailView()
                    }

                    SetupPanel(
                        title: "运行日志 / Runtime Logs",
                        subtitle: "只读查看代理运行日志，内容展示前会做基础脱敏。",
                        systemImage: "doc.text.magnifyingglass"
                    ) {
                        RuntimeLogsTailView()
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }
}

private struct ClaudeDesktopLogTailView: View {
    @EnvironmentObject private var appState: AppState
    @State private var content = "尚未读取 / Not loaded"

    private var logURL: URL {
        LogService.claudeDesktopLogURL(
            supportDirectoryName: appState.setupConfiguration.claudeDesktopSupportDirectoryName
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    reload()
                } label: {
                    Label("刷新 / Refresh", systemImage: "arrow.clockwise")
                }
                .controlSize(.large)

                Button {
                    Task {
                        await appState.checkClaudeDesktopHost()
                        reload()
                    }
                } label: {
                    Label("检查 Host / Check Host", systemImage: "checkmark.circle")
                }
                .controlSize(.large)
            }

            Text(logURL.path)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            ScrollView([.vertical, .horizontal]) {
                Text(content)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(minHeight: 220)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .onAppear(perform: reload)
    }

    private func reload() {
        content = LogService.tailFile(logURL)
    }
}

private struct RuntimeLogsTailView: View {
    @State private var selectedLog = "proxy.log"
    @State private var content = "尚未读取 / Not loaded"
    private let names = ["proxy.log", "proxy.err.log", "telemetry.jsonl"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Picker("Log", selection: $selectedLog) {
                    ForEach(names, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 520)

                Button {
                    reload()
                } label: {
                    Label("刷新 / Refresh", systemImage: "arrow.clockwise")
                }
                .controlSize(.large)
            }

            Text(LogService.runtimeLogURL(selectedLog).path)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            ScrollView([.vertical, .horizontal]) {
                Text(content)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(minHeight: 220)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .onAppear(perform: reload)
        .onChange(of: selectedLog) {
            reload()
        }
    }

    private func reload() {
        content = LogService.tailFile(LogService.runtimeLogURL(selectedLog))
    }
}
