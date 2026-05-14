import Foundation
import Testing
@testable import ProxySetupApp

struct ClientConfigServiceTests {
    @Test
    func claudeSettingsUsesCliPrefixAndLocalToken() throws {
        let service = ClientConfigService()
        let json = try service.renderClaudeSettings(config: .default)

        #expect(json.contains("https://127.0.0.1:38443/claude-cli"))
        #expect(json.contains("CJ_LOCAL_PROXY_TOKEN"))
        #expect(!json.contains("doubao-real-secret"))
        #expect(!json.contains("Bearer "))
    }

    @Test
    func claudeDesktopGatewayUsesDesktopPrefixAndLocalToken() throws {
        let service = ClientConfigService()
        let json = try service.renderClaudeDesktopGatewayConfig(config: .default)

        #expect(json.contains("https://127.0.0.1:38443/claude-desktop"))
        #expect(json.contains("CJ_LOCAL_PROXY_TOKEN"))
        #expect(json.contains("claude-sonnet-4-6"))
        #expect(!json.contains("Bearer "))
    }

    @Test
    func codexConfigSeparatesAppAndCliProviders() {
        let service = ClientConfigService()
        let toml = service.renderCodexConfig(config: .default)

        #expect(toml.contains("[model_providers.ark-coding-app]"))
        #expect(toml.contains("base_url = \"https://127.0.0.1:38443/codex-app/v1\""))
        #expect(toml.contains("[model_providers.ark-coding-cli]"))
        #expect(toml.contains("base_url = \"https://127.0.0.1:38443/codex-cli/v1\""))
        #expect(toml.contains("[profiles.ark-doubao]"))
        #expect(!toml.contains("sk-"))
        #expect(!toml.contains("Bearer "))
    }

    @Test
    func tomlEscapesQuotesAndBackslashes() {
        var config = SetupConfiguration.default
        config.codexProfiles = [
            CodexProfile(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
                name: "quoted",
                model: #"model"with\chars"#,
                reasoningEffort: "medium"
            ),
        ]

        let toml = ClientConfigService().renderCodexConfig(config: config)
        #expect(toml.contains(#"model = "model\"with\\chars""#))
    }
}
