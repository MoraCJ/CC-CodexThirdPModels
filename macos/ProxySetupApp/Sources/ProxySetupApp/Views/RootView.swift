import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationSplitView {
            List(AppState.Section.allCases, selection: $appState.selectedSection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(220)
        } detail: {
            switch appState.selectedSection ?? .status {
            case .status:
                StatusDashboardView()
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
            description: Text("代理日志查看会在后续任务接入。")
        )
    }
}
