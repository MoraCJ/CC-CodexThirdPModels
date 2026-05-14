import Foundation

struct ClientConfigService {
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
            "provider": "gateway",
            "gatewayBaseUrl": config.claudeDesktopBaseURL.absoluteString,
            "inferenceGatewayBaseUrl": config.claudeDesktopBaseURL.absoluteString,
            "gatewayApiKey": localToken,
            "gatewayAuthScheme": "bearer",
            "inferenceModels": [
                ["id": "claude-sonnet-4-6", "name": "Sonnet 4.6"],
                ["id": "claude-opus-4-6", "name": "Opus 4.6"],
                ["id": "claude-haiku-4-5", "name": "Haiku 4.5"],
            ],
            "hideAnthropicSignIn": true,
        ]
        return try prettyJSONString(object)
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
