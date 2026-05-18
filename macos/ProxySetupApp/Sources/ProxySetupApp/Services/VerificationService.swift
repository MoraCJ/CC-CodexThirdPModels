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

    func run(
        config: SetupConfiguration,
        runner: CommandRunning = CommandRunner(),
        attempts: Int = 8,
        retryDelayNanoseconds: UInt64 = 500_000_000
    ) async -> VerificationSummary {
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
            await runCheck(
                name: name,
                url: url,
                runner: runner,
                attempts: attempts,
                retryDelayNanoseconds: retryDelayNanoseconds
            )
        }
        return VerificationSummary(checks: checks)
    }

    private func runCheck(
        name: String,
        url: URL,
        runner: CommandRunning,
        attempts: Int,
        retryDelayNanoseconds: UInt64
    ) async -> VerificationCheck {
        let maxAttempts = max(1, attempts)
        var lastResult = CommandResult(exitCode: 127, stdout: "", stderr: "not run")

        for attempt in 1...maxAttempts {
            let result = await runner.run(
                "curl",
                [
                    "-skS",
                    "--connect-timeout", "2",
                    "--max-time", "5",
                    "-o", "/dev/null",
                    "-w", "%{http_code}",
                    url.absoluteString,
                ]
            )
            lastResult = result

            let code = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if result.exitCode == 0 && (code.hasPrefix("2") || code.hasPrefix("3")) {
                return VerificationCheck(
                    name: name,
                    url: url,
                    status: .passed,
                    detail: maxAttempts == 1 ? "HTTP \(code)" : "HTTP \(code) / attempt \(attempt)"
                )
            }

            if attempt < maxAttempts, retryDelayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: retryDelayNanoseconds)
            }
        }

        let code = lastResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = lastResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let reason = detail.isEmpty ? "HTTP \(code.isEmpty ? "000" : code)" : detail
        return VerificationCheck(
            name: name,
            url: url,
            status: .failed,
            detail: "失败 / \(reason)"
        )
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
