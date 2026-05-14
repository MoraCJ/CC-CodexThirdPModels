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
}
