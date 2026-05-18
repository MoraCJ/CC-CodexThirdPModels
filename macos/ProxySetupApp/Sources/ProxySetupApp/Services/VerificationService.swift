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
    static func pendingSummary(config: SetupConfiguration) -> VerificationSummary {
        let names = [
            "Proxy health",
            "Dashboard",
            "Telemetry summary",
            "Claude Desktop health",
            "Claude CLI health",
            "Codex App health",
            "Codex CLI health",
        ]
        let checks = zip(names, healthURLs(config: config)).map { name, url in
            VerificationCheck(
                name: name,
                url: url,
                status: .notRun,
                detail: "待运行 / Not run"
            )
        }
        return VerificationSummary(checks: checks)
    }

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

    func run(config: SetupConfiguration, runner: CommandRunning = CommandRunner()) async -> VerificationSummary {
        let names = [
            "Proxy health",
            "Dashboard",
            "Telemetry summary",
            "Claude Desktop health",
            "Claude CLI health",
            "Codex App health",
            "Codex CLI health",
        ]
        let checks = await zip(names, VerificationService.healthURLs(config: config)).asyncMap { name, url in
            let result = await runner.run(
                "curl",
                ["-sk", "-o", "/dev/null", "-w", "%{http_code}", url.absoluteString]
            )
            let code = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let passed = result.exitCode == 0 && (code.hasPrefix("2") || code.hasPrefix("3"))
            return VerificationCheck(
                name: name,
                url: url,
                status: passed ? .passed : .failed,
                detail: passed ? "HTTP \(code)" : "失败 / \(result.stderr.isEmpty ? "HTTP \(code)" : result.stderr)"
            )
        }
        return VerificationSummary(checks: checks)
    }
}

private extension Sequence {
    func asyncMap<T>(_ transform: (Element) async -> T) async -> [T] {
        var values: [T] = []
        for element in self {
            let value = await transform(element)
            values.append(value)
        }
        return values
    }
}
