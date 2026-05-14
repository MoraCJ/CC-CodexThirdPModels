import Foundation

struct PreflightService {
    var runner: CommandRunning

    func checkTools() async -> ToolCheckResult {
        async let node = commandCheck("node")
        async let claude = commandCheck("claude")
        async let codex = commandCheck("codex")
        return await ToolCheckResult(node: node, claude: claude, codex: codex)
    }

    private func commandCheck(_ name: String) async -> ToolCheck {
        let result = await runner.run("command", ["-v", name])
        let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.exitCode == 0, !path.isEmpty {
            return ToolCheck(name: name, path: path, status: .ok)
        }
        return ToolCheck(name: name, path: "", status: .missing)
    }
}
