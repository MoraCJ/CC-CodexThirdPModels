import Foundation

struct ClientConfigEnvironment: Equatable {
    static let claudeDesktopConfigID = "9f5d0b76-5b35-4c9e-9d5d-2f2a8f8f8c01"

    var claudeSettingsURL: URL
    var claudeDesktopGatewayURL: URL
    var claudeDesktopMetaURL: URL
    var claudeDesktopModeURL: URL
    var codexConfigURL: URL

    static func defaultEnvironment() -> ClientConfigEnvironment {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let claudeDesktopRoot = home.appendingPathComponent(
            "Library/Application Support/Claude-3p"
        )
        let configLibrary = claudeDesktopRoot.appendingPathComponent(
            "configLibrary",
            isDirectory: true
        )
        return ClientConfigEnvironment(
            claudeSettingsURL: home.appendingPathComponent(".claude/settings.json"),
            claudeDesktopGatewayURL: configLibrary.appendingPathComponent("\(claudeDesktopConfigID).json"),
            claudeDesktopMetaURL: configLibrary.appendingPathComponent("_meta.json"),
            claudeDesktopModeURL: claudeDesktopRoot.appendingPathComponent("claude_desktop_config.json"),
            codexConfigURL: home.appendingPathComponent(".codex/config.toml")
        )
    }
}

struct ClientConfigService {
    private let claudeDesktopConfigID = ClientConfigEnvironment.claudeDesktopConfigID
    let localToken = "CJ_LOCAL_PROXY_TOKEN"

    func renderClaudeSettings(config: SetupConfiguration) throws -> String {
        let object: [String: Any] = [
            "env": [
                "ANTHROPIC_BASE_URL": config.claudeCLIBaseURL.absoluteString,
                "ANTHROPIC_AUTH_TOKEN": localToken,
                "ANTHROPIC_DEFAULT_OPUS_MODEL": "claude-opus-4-6",
                "ANTHROPIC_DEFAULT_SONNET_MODEL": "claude-sonnet-4-6",
                "ANTHROPIC_DEFAULT_HAIKU_MODEL": "claude-haiku-4-5",
                "NODE_USE_SYSTEM_CA": "1",
            ],
        ]
        return try prettyJSONString(object)
    }

    func renderClaudeDesktopGatewayConfig(config: SetupConfiguration) throws -> String {
        let object: [String: Any] = [
            "disableDeploymentModeChooser": true,
            "inferenceGatewayApiKey": localToken,
            "inferenceGatewayAuthScheme": "bearer",
            "inferenceGatewayBaseUrl": config.claudeDesktopBaseURL.absoluteString,
            "inferenceProvider": "gateway",
            "inferenceModels": [
                ["labelOverride": "Sonnet 4.6", "name": "claude-sonnet-4-6"],
                ["labelOverride": "Opus 4.6", "name": "claude-opus-4-6"],
                ["labelOverride": "Haiku 4.5", "name": "claude-haiku-4-5"],
            ],
            "unstableDisableModelVerification": true,
        ]
        return try prettyJSONString(object)
    }

    func renderClaudeDesktopMetaConfig() throws -> String {
        let entry: [String: Any] = [
            "id": claudeDesktopConfigID,
            "name": "CJ Local Proxy",
            "provider": "gateway",
        ]
        let object: [String: Any] = [
            "appliedId": claudeDesktopConfigID,
            "entries": [entry],
            "configs": [entry],
            "isManaged": false,
        ]
        return try prettyJSONString(object)
    }

    func renderClaudeDesktopDeploymentModeConfig() throws -> String {
        try prettyJSONString(["deploymentMode": "3p"])
    }

    func renderCodexConfig(config: SetupConfiguration) -> String {
        let defaultProfile = config.codexProfiles.first
        let profiles = config.codexProfiles.map { profile in
            """
            [profiles.\(tomlBareKey(profile.name))]
            model_provider = "ark-coding-cli"
            model = "\(tomlString(profile.model))"
            model_reasoning_effort = "\(tomlString(profile.reasoningEffort))"
            """
        }.joined(separator: "\n\n")

        return """
        model_provider = "ark-coding-app"
        model = "\(tomlString(defaultProfile?.model ?? "doubao-seed-2.0-pro"))"
        model_reasoning_effort = "\(tomlString(defaultProfile?.reasoningEffort ?? "medium"))"
        disable_response_storage = true

        [model_providers.ark-coding-app]
        name = "Third-party provider via CJ Local Proxy - Codex App"
        wire_api = "responses"
        requires_openai_auth = true
        base_url = "\(config.codexAppBaseURL.absoluteString)"
        supports_websockets = false

        [model_providers.ark-coding-cli]
        name = "Third-party provider via CJ Local Proxy - Codex CLI"
        wire_api = "responses"
        requires_openai_auth = true
        base_url = "\(config.codexCLIBaseURL.absoluteString)"
        supports_websockets = false

        \(profiles)
        """
    }

    func managedClientConfigChanges(
        config: SetupConfiguration,
        environment: ClientConfigEnvironment = .defaultEnvironment()
    ) throws -> [ManagedFileChange] {
        [
            ManagedFileChange(
                title: "Claude CLI settings",
                targetURL: environment.claudeSettingsURL,
                proposedContents: try renderClaudeSettings(config: config)
            ),
            ManagedFileChange(
                title: "Claude Desktop gateway config",
                targetURL: environment.claudeDesktopGatewayURL,
                proposedContents: try renderClaudeDesktopGatewayConfig(config: config)
            ),
            ManagedFileChange(
                title: "Claude Desktop config library meta",
                targetURL: environment.claudeDesktopMetaURL,
                proposedContents: try renderClaudeDesktopMetaConfig()
            ),
            ManagedFileChange(
                title: "Claude Desktop deployment mode",
                targetURL: environment.claudeDesktopModeURL,
                proposedContents: try renderClaudeDesktopDeploymentModeConfig()
            ),
            ManagedFileChange(
                title: "Codex config",
                targetURL: environment.codexConfigURL,
                proposedContents: renderCodexConfig(config: config)
            ),
        ]
    }

    private func prettyJSONString(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func tomlString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func tomlBareKey(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
        if value.unicodeScalars.allSatisfy({ allowed.contains($0) }), !value.isEmpty {
            return value
        }
        return "\"\(tomlString(value))\""
    }
}
