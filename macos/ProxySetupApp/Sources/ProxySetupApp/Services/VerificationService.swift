import Foundation

enum VerificationStatus: Equatable {
    case notRun
    case passed
    case failed
}

struct VerificationCheck: Equatable {
    var name: String
    var url: URL?
    var status: VerificationStatus
    var detail: String
}

struct VerificationSummary: Equatable {
    var checks: [VerificationCheck]

    var passedCount: Int {
        checks.filter { $0.status == .passed }.count
    }

    var failedCount: Int {
        checks.filter { $0.status == .failed }.count
    }

    var isPassing: Bool {
        !checks.isEmpty && failedCount == 0 && checks.allSatisfy { $0.status == .passed }
    }
}

struct VerificationService {
    static func healthURLs(config: SetupConfiguration) -> [URL] {
        let base = "https://\(config.listenHost):\(config.listenPort)"
        return [
            "\(base)/health",
            "\(base)/dashboard",
            "\(base)/telemetry/summary",
            "\(base)/claude-desktop/health",
            "\(base)/claude-cli/health",
            "\(base)/codex-app/health",
            "\(base)/codex-cli/health",
        ].compactMap(URL.init(string:))
    }
}
