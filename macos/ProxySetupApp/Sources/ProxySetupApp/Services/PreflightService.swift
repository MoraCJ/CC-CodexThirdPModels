import Foundation

struct PreflightService {
    var runner: CommandRunning
    var isExecutableFile: @Sendable (String) -> Bool = { path in
        FileManager.default.isExecutableFile(atPath: path)
    }

    private let nodeCandidates = [
        "/opt/homebrew/bin/node",
        "/usr/local/bin/node",
        "/usr/bin/node",
    ]

    private let npmCandidates = [
        "/opt/homebrew/bin/npm",
        "/usr/local/bin/npm",
        "/usr/bin/npm",
    ]

    private let brewCandidates = [
        "/opt/homebrew/bin/brew",
        "/usr/local/bin/brew",
    ]

    func checkTools() async -> ToolCheckResult {
        async let node = commandCheck("node", required: true, candidates: nodeCandidates)
        async let npm = commandCheck("npm", required: false, candidates: npmCandidates)
        async let brew = commandCheck("brew", required: false, candidates: brewCandidates)
        async let claude = commandCheck("claude", required: false, candidates: [])
        async let codex = commandCheck("codex", required: false, candidates: [])
        return await ToolCheckResult(node: node, npm: npm, brew: brew, claude: claude, codex: codex)
    }

    private func commandCheck(
        _ name: String,
        required: Bool,
        candidates: [String]
    ) async -> ToolCheck {
        let result = await runner.run("command", ["-v", name])
        var path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        if !(result.exitCode == 0 && !path.isEmpty) {
            path = candidates.first(where: isExecutableFile) ?? ""
        }

        guard !path.isEmpty else {
            return ToolCheck(
                name: name,
                path: "",
                status: required ? .missing : .warning,
                isRequired: required,
                detail: required
                    ? "未找到必需命令 / Required command not found"
                    : "未找到可选命令 / Optional command not found"
            )
        }

        let version = await commandVersion(path: path)
        return ToolCheck(
            name: name,
            path: path,
            status: .ok,
            isRequired: required,
            version: version,
            detail: version.isEmpty
                ? "已找到命令，版本未确认 / Found, version not confirmed"
                : "已找到命令 / Found"
        )
    }

    private func commandVersion(path: String) async -> String {
        let result = await runner.run(path, ["--version"])
        guard result.exitCode == 0 else { return "" }
        return result.stdout
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init) ?? ""
    }
}
