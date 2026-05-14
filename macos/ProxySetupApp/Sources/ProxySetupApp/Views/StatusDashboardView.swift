import SwiftUI

struct StatusDashboardView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationSplitView {
            List {
                Label("状态 / Status", systemImage: "gauge.with.dots.needle.67percent")
                Label("设置向导 / Setup", systemImage: "wand.and.stars")
                Label("日志 / Logs", systemImage: "doc.text.magnifyingglass")
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(220)
        } detail: {
            VStack(alignment: .leading, spacing: 18) {
                Text("Claude + Codex Local Proxy / 本机代理")
                    .font(.title2.bold())
                Text(appState.proxyStatusLabel)
                    .font(.body)
                    .foregroundStyle(.secondary)
                Button("打开 Dashboard / Open Dashboard") {
                    appState.openDashboard()
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
