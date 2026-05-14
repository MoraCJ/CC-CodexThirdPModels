import Foundation

struct ProviderConfiguration: Equatable, Codable {
    var isEnabled: Bool
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
    var claudeProvider: ProviderConfiguration
    var codexProvider: ProviderConfiguration
    var claudeModels: ClaudeModelMapping
    var codexProfiles: [CodexProfile]

    static let `default` = SetupConfiguration(
        listenHost: "127.0.0.1",
        listenPort: 38443,
        keychainService: "CJLocalProxy",
        claudeProvider: ProviderConfiguration(
            isEnabled: true,
            baseURL: "https://ark.cn-beijing.volces.com/api/coding",
            keychainAccount: "claude-upstream-api-key"
        ),
        codexProvider: ProviderConfiguration(
            isEnabled: true,
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
        if claudeProvider.isEnabled {
            try validateHTTPS(claudeProvider.baseURL)
        }
        if codexProvider.isEnabled {
            try validateHTTPS(codexProvider.baseURL)
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

    enum ValidationError: Error, Equatable {
        case noEnabledProvider
        case invalidProviderURL(String)
        case invalidPort
    }
}
