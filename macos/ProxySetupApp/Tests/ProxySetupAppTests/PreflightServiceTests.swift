import Testing
@testable import ProxySetupApp

struct PreflightServiceTests {
    @Test
    func resolvesRequiredNodeAndOptionalToolsWithVersions() async {
        let runner = MockCommandRunner(outputs: [
            "command -v node": CommandResult(exitCode: 0, stdout: "/usr/local/bin/node\n", stderr: ""),
            "/usr/local/bin/node --version": CommandResult(exitCode: 0, stdout: "v24.15.0\n", stderr: ""),
            "command -v npm": CommandResult(exitCode: 0, stdout: "/usr/local/bin/npm\n", stderr: ""),
            "/usr/local/bin/npm --version": CommandResult(exitCode: 0, stdout: "11.6.2\n", stderr: ""),
            "command -v brew": CommandResult(exitCode: 1, stdout: "", stderr: ""),
            "command -v claude": CommandResult(exitCode: 1, stdout: "", stderr: ""),
            "command -v codex": CommandResult(exitCode: 0, stdout: "/usr/local/bin/codex\n", stderr: ""),
            "/usr/local/bin/codex --version": CommandResult(exitCode: 0, stdout: "codex 1.0.0\n", stderr: ""),
        ])
        let service = PreflightService(runner: runner)
        let result = await service.checkTools()

        #expect(result.node.path == "/usr/local/bin/node")
        #expect(result.node.version == "v24.15.0")
        #expect(result.node.status == .ok)
        #expect(result.requiredToolsReady)
        #expect(result.npm.status == .ok)
        #expect(result.brew.status == .warning)
        #expect(result.claude.status == .warning)
        #expect(result.codex.path == "/usr/local/bin/codex")
        #expect(result.codex.status == .ok)
    }

    @Test
    func fallsBackToKnownNodeCandidateWhenShellPathIsMissing() async {
        let runner = MockCommandRunner(outputs: [
            "command -v node": CommandResult(exitCode: 0, stdout: "", stderr: ""),
            "/usr/local/bin/node --version": CommandResult(exitCode: 0, stdout: "v24.15.0\n", stderr: ""),
            "command -v npm": CommandResult(exitCode: 1, stdout: "", stderr: ""),
            "command -v brew": CommandResult(exitCode: 1, stdout: "", stderr: ""),
            "command -v claude": CommandResult(exitCode: 1, stdout: "", stderr: ""),
            "command -v codex": CommandResult(exitCode: 1, stdout: "", stderr: ""),
        ])
        let service = PreflightService(
            runner: runner,
            isExecutableFile: { $0 == "/usr/local/bin/node" }
        )
        let result = await service.checkTools()

        #expect(result.node.path == "/usr/local/bin/node")
        #expect(result.node.status == .ok)
        #expect(result.node.version == "v24.15.0")
        #expect(result.requiredToolsReady)
    }

    @Test
    func missingRequiredNodeBlocksInstallButMissingOptionalToolsWarnOnly() async {
        let runner = MockCommandRunner(outputs: [
            "command -v node": CommandResult(exitCode: 1, stdout: "", stderr: ""),
            "command -v npm": CommandResult(exitCode: 1, stdout: "", stderr: ""),
            "command -v brew": CommandResult(exitCode: 1, stdout: "", stderr: ""),
            "command -v claude": CommandResult(exitCode: 1, stdout: "", stderr: ""),
            "command -v codex": CommandResult(exitCode: 1, stdout: "", stderr: ""),
        ])
        let service = PreflightService(runner: runner, isExecutableFile: { _ in false })
        let result = await service.checkTools()

        #expect(result.node.status == .missing)
        #expect(result.node.isRequired)
        #expect(!result.requiredToolsReady)
        #expect(result.npm.status == .warning)
        #expect(!result.npm.isRequired)
        #expect(result.brew.status == .warning)
        #expect(result.claude.status == .warning)
        #expect(result.codex.status == .warning)
    }
}
