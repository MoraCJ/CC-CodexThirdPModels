import Foundation
import Testing
@testable import ProxySetupApp

struct VerificationServiceTests {
    @Test
    func buildsExpectedHealthURLs() {
        let urls = VerificationService.healthURLs(config: .default).map(\.absoluteString)

        #expect(urls == [
            "https://127.0.0.1:38443/health",
            "https://127.0.0.1:38443/dashboard",
            "https://127.0.0.1:38443/telemetry/summary",
            "https://127.0.0.1:38443/claude-desktop/health",
            "https://127.0.0.1:38443/claude-cli/health",
            "https://127.0.0.1:38443/codex-app/health",
            "https://127.0.0.1:38443/codex-cli/health",
        ])
    }

    @Test
    func summarizesVerificationStatuses() {
        let results = [
            VerificationCheck(name: "health", url: nil, status: .passed, detail: "ok"),
            VerificationCheck(name: "dashboard", url: nil, status: .failed, detail: "404"),
            VerificationCheck(name: "telemetry", url: nil, status: .notRun, detail: ""),
        ]

        #expect(VerificationSummary(checks: results).passedCount == 1)
        #expect(VerificationSummary(checks: results).failedCount == 1)
        #expect(VerificationSummary(checks: results).isPassing == false)
    }

    @Test
    func pendingSummaryNamesDesktopCliAppCliChecks() {
        let summary = VerificationService.pendingSummary(config: .default)
        let names = summary.checks.map(\.name)

        #expect(names.contains("Claude Desktop health"))
        #expect(names.contains("Claude CLI health"))
        #expect(names.contains("Codex App health"))
        #expect(names.contains("Codex CLI health"))
        #expect(summary.checks.allSatisfy { $0.status == .notRun })
    }

    @Test
    func runRetriesTransientHTTP000UntilEndpointIsReady() async {
        let runner = TransientCurlRunner(failuresBeforeSuccess: 2)
        let summary = await VerificationService().run(
            config: .default,
            runner: runner,
            attempts: 3,
            retryDelayNanoseconds: 0
        )

        #expect(summary.isPassing)
        #expect(summary.checks.allSatisfy { $0.detail.contains("attempt") })
        #expect(runner.callCount >= VerificationService.healthURLs(config: .default).count + 2)
    }

    @Test
    func runReportsCurlErrorAfterRetriesAreExhausted() async {
        let runner = TransientCurlRunner(failuresBeforeSuccess: .max)
        let summary = await VerificationService().run(
            config: .default,
            runner: runner,
            attempts: 2,
            retryDelayNanoseconds: 0
        )

        #expect(!summary.isPassing)
        #expect(summary.failedCount == summary.checks.count)
        #expect(summary.checks.allSatisfy { $0.detail.contains("connection refused") })
    }

    @Test
    func runReportsProgressForEachVerificationCheck() async {
        let runner = TransientCurlRunner(failuresBeforeSuccess: 0)
        let lock = NSLock()
        var events: [VerificationProgressEvent] = []

        let summary = await VerificationService().run(
            config: .default,
            runner: runner,
            attempts: 1,
            retryDelayNanoseconds: 0,
            progress: { event in
                lock.withLock {
                    events.append(event)
                }
            }
        )

        #expect(summary.isPassing)
        #expect(events.contains { $0.status == .running && $0.name == "Proxy health" })
        #expect(events.contains { $0.status == .passed && $0.name == "Codex CLI health" })
        #expect(events.filter { $0.status == .passed }.count == summary.checks.count)
    }
}

private final class TransientCurlRunner: CommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private let failuresBeforeSuccess: Int
    private var calls = 0

    init(failuresBeforeSuccess: Int) {
        self.failuresBeforeSuccess = failuresBeforeSuccess
    }

    var callCount: Int {
        lock.withLock { calls }
    }

    func run(_ executable: String, _ arguments: [String]) async -> CommandResult {
        lock.withLock {
            calls += 1
            if calls <= failuresBeforeSuccess {
                return CommandResult(exitCode: 7, stdout: "000", stderr: "connection refused")
            }
            return CommandResult(exitCode: 0, stdout: "200", stderr: "")
        }
    }
}
