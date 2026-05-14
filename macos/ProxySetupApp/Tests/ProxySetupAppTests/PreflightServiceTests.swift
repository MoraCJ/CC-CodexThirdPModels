import Testing
@testable import ProxySetupApp

struct PreflightServiceTests {
    @Test
    func parsesCommandAvailability() async {
        let runner = MockCommandRunner(outputs: [
            "command -v node": CommandResult(exitCode: 0, stdout: "/opt/homebrew/bin/node\n", stderr: ""),
            "command -v claude": CommandResult(exitCode: 1, stdout: "", stderr: ""),
            "command -v codex": CommandResult(exitCode: 0, stdout: "/opt/homebrew/bin/codex\n", stderr: ""),
        ])
        let service = PreflightService(runner: runner)
        let result = await service.checkTools()

        #expect(result.node.path == "/opt/homebrew/bin/node")
        #expect(result.node.status == .ok)
        #expect(result.claude.status == .missing)
        #expect(result.codex.path == "/opt/homebrew/bin/codex")
        #expect(result.codex.status == .ok)
    }

    @Test
    func reportsMissingCommandWhenOutputIsEmpty() async {
        let runner = MockCommandRunner(outputs: [
            "command -v node": CommandResult(exitCode: 0, stdout: "", stderr: ""),
        ])
        let service = PreflightService(runner: runner)
        let result = await service.checkTools()

        #expect(result.node.status == .missing)
        #expect(result.node.path == "")
    }
}
