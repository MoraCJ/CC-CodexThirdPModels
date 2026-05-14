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
}

struct ToolCheckResult: Equatable {
    var node: ToolCheck
    var claude: ToolCheck
    var codex: ToolCheck
}
