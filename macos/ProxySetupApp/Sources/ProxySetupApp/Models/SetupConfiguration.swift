import Foundation

enum ProviderProtocol: String, CaseIterable, Codable, Identifiable {
    case anthropicCompatible
    case openAICompatible

    var id: String { rawValue }

    var title: String {
        switch self {
        case .anthropicCompatible:
            return "Anthropic 兼容 / Anthropic-compatible"
        case .openAICompatible:
            return "OpenAI 兼容 / OpenAI-compatible"
        }
    }

    var shortTitle: String {
        switch self {
        case .anthropicCompatible:
            return "Anthropic"
        case .openAICompatible:
            return "OpenAI"
        }
    }
}

struct ProviderConfiguration: Equatable, Codable {
    var isEnabled: Bool
    var protocolType: ProviderProtocol
    var baseURL: String
    var keychainAccount: String
}

struct ClaudeModelMapping: Equatable, Codable {
    var opus: String
    var sonnet: String
    var haiku: String
}

struct CodexProfile: Identifiable, Equatable, Codable {
    var id: UUID
    var name: String
    var model: String
    var reasoningEffort: String
}

struct SetupConfiguration: Equatable, Codable {
    var listenHost: String
    var listenPort: Int
    var keychainService: String
    var claudeDesktopSupportDirectoryName: String
    var claudeProvider: ProviderConfiguration
    var codexProvider: ProviderConfiguration
    var claudeModels: ClaudeModelMapping
    var codexProfiles: [CodexProfile]

    static let `default` = SetupConfiguration(
        listenHost: "127.0.0.1",
        listenPort: 38443,
        keychainService: "CJLocalProxy",
        claudeDesktopSupportDirectoryName: "Claude-3p",
        claudeProvider: ProviderConfiguration(
            isEnabled: true,
            protocolType: .anthropicCompatible,
            baseURL: "https://ark.cn-beijing.volces.com/api/coding",
            keychainAccount: "claude-upstream-api-key"
        ),
        codexProvider: ProviderConfiguration(
            isEnabled: true,
            protocolType: .openAICompatible,
            baseURL: "https://ark.cn-beijing.volces.com/api/coding/v3",
            keychainAccount: "codex-upstream-api-key"
        ),
        claudeModels: ClaudeModelMapping(
            opus: "glm-5.1",
            sonnet: "kimi-k2.6",
            haiku: "doubao-seed-2.0-pro"
        ),
        codexProfiles: [
            CodexProfile(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                name: "ark-doubao",
                model: "doubao-seed-2.0-pro",
                reasoningEffort: "medium"
            ),
            CodexProfile(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                name: "ark-kimi",
                model: "kimi-k2.6",
                reasoningEffort: "high"
            ),
            CodexProfile(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
                name: "ark-glm",
                model: "glm-5.1",
                reasoningEffort: "high"
            )
        ]
    )

    var claudeDesktopBaseURL: URL {
        URL(string: "https://\(listenHost):\(listenPort)/claude-desktop")!
    }

    var claudeCLIBaseURL: URL {
        URL(string: "https://\(listenHost):\(listenPort)/claude-cli")!
    }

    var codexAppBaseURL: URL {
        URL(string: "https://\(listenHost):\(listenPort)/codex-app/v1")!
    }

    var codexCLIBaseURL: URL {
        URL(string: "https://\(listenHost):\(listenPort)/codex-cli/v1")!
    }

    func validate() throws {
        guard claudeProvider.isEnabled || codexProvider.isEnabled else {
            throw ValidationError.noEnabledProvider
        }
        guard !listenHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError.emptyListenHost
        }
        try validateDesktopSupportDirectoryName(claudeDesktopSupportDirectoryName)
        if claudeProvider.isEnabled {
            try validateHTTPS(claudeProvider.baseURL)
            guard !claudeModels.opus.trimmed.isEmpty,
                  !claudeModels.sonnet.trimmed.isEmpty,
                  !claudeModels.haiku.trimmed.isEmpty else {
                throw ValidationError.emptyClaudeModel
            }
        }
        if codexProvider.isEnabled {
            try validateHTTPS(codexProvider.baseURL)
            guard !codexProfiles.isEmpty else {
                throw ValidationError.emptyCodexProfiles
            }
            for profile in codexProfiles {
                guard !profile.name.trimmed.isEmpty,
                      !profile.model.trimmed.isEmpty,
                      !profile.reasoningEffort.trimmed.isEmpty else {
                    throw ValidationError.emptyCodexProfile
                }
            }
        }
        guard (1...65535).contains(listenPort) else {
            throw ValidationError.invalidPort
        }
    }

    private func validateHTTPS(_ value: String) throws {
        guard let url = URL(string: value),
              url.scheme == "https",
              url.host?.isEmpty == false else {
            throw ValidationError.invalidProviderURL(value)
        }
    }

    private func validateDesktopSupportDirectoryName(_ value: String) throws {
        let trimmed = value.trimmed
        guard !trimmed.isEmpty else {
            throw ValidationError.emptyClaudeDesktopSupportDirectoryName
        }
        guard trimmed.rangeOfCharacter(from: CharacterSet(charactersIn: "/:")) == nil,
              trimmed != ".",
              trimmed != ".." else {
            throw ValidationError.invalidClaudeDesktopSupportDirectoryName(value)
        }
    }

    enum ValidationError: Error, Equatable {
        case noEnabledProvider
        case invalidProviderURL(String)
        case invalidPort
        case emptyListenHost
        case emptyClaudeDesktopSupportDirectoryName
        case invalidClaudeDesktopSupportDirectoryName(String)
        case emptyClaudeModel
        case emptyCodexProfiles
        case emptyCodexProfile
    }
}

extension SetupConfiguration.ValidationError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .noEnabledProvider:
            return "至少启用 Claude 或 Codex 一个 provider / Enable at least one provider"
        case .invalidProviderURL(let value):
            return "Provider Base URL 必须是 HTTPS：\(value)"
        case .invalidPort:
            return "端口必须在 1...65535 / Port must be 1...65535"
        case .emptyListenHost:
            return "监听 Host 不能为空 / Listen host is required"
        case .emptyClaudeDesktopSupportDirectoryName:
            return "Claude Desktop 数据目录名不能为空 / Claude Desktop data directory name is required"
        case .invalidClaudeDesktopSupportDirectoryName(let value):
            return "Claude Desktop 数据目录名不能包含路径分隔符：\(value)"
        case .emptyClaudeModel:
            return "Claude 三个模型名都不能为空 / Claude model names are required"
        case .emptyCodexProfiles:
            return "至少保留一个 Codex profile / Add at least one Codex profile"
        case .emptyCodexProfile:
            return "Codex profile、model、reasoning 都不能为空 / Complete every Codex profile"
        }
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
