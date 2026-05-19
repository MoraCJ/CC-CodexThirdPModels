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
            switch appState.selectedSection ?? .start {
            case .status:
                StatusDashboardView()
            case .start:
                StartupConfigurationView()
            case .setup:
                SetupWizardView()
            case .logs:
                LogsPlaceholderView()
            }
        }
        .frame(minWidth: 920, minHeight: 620)
    }
}

private struct LogsPlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "日志 / Logs",
            systemImage: "doc.text.magnifyingglass",
            description: Text("代理日志查看会在后续任务接入；日志不得包含 API Key、prompt 或 response。")
        )
    }
}
