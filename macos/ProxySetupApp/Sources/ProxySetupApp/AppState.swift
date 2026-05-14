import AppKit
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var proxyStatusLabel: String = "未检测 / Not Checked"

    var menuBarSystemImage: String {
        proxyStatusLabel.contains("运行") ? "bolt.horizontal.circle.fill" : "bolt.horizontal.circle"
    }

    func openDashboard() {
        guard let url = URL(string: "https://127.0.0.1:38443/dashboard") else { return }
        NSWorkspace.shared.open(url)
    }
}
