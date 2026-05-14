import SwiftUI

struct StatusDashboardView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Claude + Codex Local Proxy / 本机代理")
                        .font(.title2.bold())
                    Text("本页当前只展示 App 内部状态，不会修改本机配置。")
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    StatusPill(title: "Proxy / 代理", value: appState.proxyStatusLabel)
                    StatusPill(title: "LaunchAgent / 开机启动", value: "未检测 / Not Checked")
                    StatusPill(title: "Certificate / 证书", value: "未检测 / Not Checked")
                }

                HStack {
                    Button("打开 Dashboard / Open Dashboard") {
                        appState.openDashboard()
                    }
                    Button("运行验证 / Run Verification") {
                        appState.proxyStatusLabel = "待接入 / Pending"
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private struct StatusPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.weight(.medium))
                .lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
