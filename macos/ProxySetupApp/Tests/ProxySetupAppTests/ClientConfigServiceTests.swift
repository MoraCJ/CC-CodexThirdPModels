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
    func codexTopLevelModelUsesFirstProfileAsDefault() {
        var config = SetupConfiguration.default
        config.codexProfiles = [
            CodexProfile(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000020")!,
                name: "ark-kimi",
                model: "kimi-k2.6",
                reasoningEffort: "high"
            ),
            CodexProfile(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000021")!,
                name: "ark-doubao",
                model: "doubao-seed-2.0-pro",
                reasoningEffort: "medium"
            ),
        ]

        let toml = ClientConfigService().renderCodexConfig(config: config)

        #expect(toml.hasPrefix("""
        model_provider = "ark-coding-app"
        model = "kimi-k2.6"
        model_reasoning_effort = "high"
        """))
        #expect(toml.contains("[profiles.ark-doubao]"))
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

    @Test
    func managedClientConfigChangesUseInjectedPathsAndLocalToken() throws {
        let environment = ClientConfigEnvironment(
            claudeSettingsURL: URL(fileURLWithPath: "/tmp/home/.claude/settings.json"),
            claudeDesktopGatewayURL: URL(fileURLWithPath: "/tmp/home/Library/Application Support/Claude-3p/configLibrary/cj-local-proxy.json"),
            claudeDesktopMetaURL: URL(fileURLWithPath: "/tmp/home/Library/Application Support/Claude-3p/configLibrary/_meta.json"),
            claudeDesktopModeURL: URL(fileURLWithPath: "/tmp/home/Library/Application Support/Claude-3p/claude_desktop_config.json"),
            codexConfigURL: URL(fileURLWithPath: "/tmp/home/.codex/config.toml")
        )

        let changes = try ClientConfigService().managedClientConfigChanges(
            config: .default,
            environment: environment
        )
        let joined = changes.map(\.proposedContents).joined(separator: "\n")

        #expect(changes.map(\.title) == [
            "Claude CLI settings",
            "Claude Desktop gateway config",
            "Claude Desktop config library meta",
            "Claude Desktop deployment mode",
            "Codex config",
        ])
        #expect(changes[0].targetURL.path == "/tmp/home/.claude/settings.json")
        #expect(changes[1].targetURL.path.hasSuffix("configLibrary/cj-local-proxy.json"))
        #expect(changes[2].targetURL.path.hasSuffix("configLibrary/_meta.json"))
        #expect(changes[3].targetURL.path.hasSuffix("claude_desktop_config.json"))
        #expect(changes[4].targetURL.path == "/tmp/home/.codex/config.toml")
        #expect(joined.contains("CJ_LOCAL_PROXY_TOKEN"))
        #expect(joined.contains("\"appliedId\""))
        #expect(joined.contains("\"deploymentMode\" : \"3p\""))
        #expect(!joined.contains("Bearer "))
        #expect(!joined.contains("sk-"))
    }
}
