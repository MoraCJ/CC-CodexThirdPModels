import Foundation

enum CheckStatus: Equatable {
    case ok
    case warning
    case missing
    case failed
}

struct ToolCheck: Equatable {
    var name: String
    var path: String
    var status: CheckStatus
    var isRequired: Bool = false
    var version: String = ""
    var detail: String = ""
}

struct ToolCheckResult: Equatable {
    var node: ToolCheck
    var npm: ToolCheck
    var brew: ToolCheck
    var claude: ToolCheck
    var codex: ToolCheck

    var allTools: [ToolCheck] {
        [node, npm, brew, claude, codex]
    }

    var requiredToolsReady: Bool {
        allTools
            .filter(\.isRequired)
            .allSatisfy { $0.status == .ok }
    }
}
