import AppKit
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var proxyStatusLabel: String = "未检测 / Not Checked"
    @Published var setupConfiguration: SetupConfiguration = .default
    @Published var selectedSection: Section? = .status

    enum Section: String, CaseIterable, Identifiable, Hashable {
        case status
        case setup
        case logs

        var id: String { rawValue }

        var title: String {
            switch self {
            case .status: return "状态 / Status"
            case .setup: return "设置向导 / Setup"
            case .logs: return "日志 / Logs"
            }
        }

        var systemImage: String {
            switch self {
            case .status: return "gauge.with.dots.needle.67percent"
            case .setup: return "wand.and.stars"
            case .logs: return "doc.text.magnifyingglass"
            }
        }
    }

    var menuBarSystemImage: String {
        proxyStatusLabel.contains("运行") ? "bolt.horizontal.circle.fill" : "bolt.horizontal.circle"
    }

    func openDashboard() {
        guard let url = URL(string: "https://127.0.0.1:38443/dashboard") else { return }
        NSWorkspace.shared.open(url)
    }
}
