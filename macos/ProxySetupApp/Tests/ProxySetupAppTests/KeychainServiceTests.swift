import Foundation
import Testing
@testable import ProxySetupApp

struct KeychainServiceTests {
    @Test
    func masksSecrets() {
        #expect(
            LogService.redact("Authorization: Bearer abcdefghijklmnopqrstuvwxyz")
                == "Authorization: Bearer <REDACTED>"
        )
        #expect(LogService.maskKey("sk-1234567890abcdef") == "sk-1…cdef")
        #expect(LogService.maskKey("short") == "<REDACTED>")
    }

    @Test
    func keychainRoundTripUsesDedicatedService() throws {
        let service = KeychainService(serviceName: "CJLocalProxyTests")
        let account = "unit-test-\(UUID().uuidString)"
        defer {
            try? service.delete(account: account)
        }

        try service.save("secret-value", account: account)
        #expect(try service.read(account: account) == "secret-value")

        try service.delete(account: account)
        #expect(try service.read(account: account) == nil)
    }
}
