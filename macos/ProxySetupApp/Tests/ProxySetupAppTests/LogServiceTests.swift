import Testing
@testable import ProxySetupApp

struct LogServiceTests {
    @Test
    func redactMasksCommonSecretHeadersAndTokens() {
        let redacted = LogService.redact(
            """
            Authorization: Bearer abc.def
            x-api-key: secret123
            ANTHROPIC_AUTH_TOKEN=token123
            Cookie: sid=secret
            Set-Cookie: sid=secret
            model=glm
            sk-real-secret
            """
        )

        #expect(!redacted.contains("abc.def"))
        #expect(!redacted.contains("secret123"))
        #expect(!redacted.contains("token123"))
        #expect(!redacted.contains("sid=secret"))
        #expect(!redacted.contains("sk-real-secret"))
        #expect(redacted.contains("model=glm"))
    }
}
