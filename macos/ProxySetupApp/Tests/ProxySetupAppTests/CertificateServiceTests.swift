import Foundation
import Testing
@testable import ProxySetupApp

struct CertificateServiceTests {
    @Test
    func openSSLConfigContainsLocalSANs() {
        let config = CertificateService.renderOpenSSLConfig()

        #expect(config.contains("IP.1 = 127.0.0.1"))
        #expect(config.contains("DNS.1 = localhost"))
        #expect(config.contains("IP.2 = ::1"))
    }

    @Test
    func generationCommandsTargetCertificateDirectory() {
        let directory = URL(fileURLWithPath: "/tmp/proxy/certs")
        let commands = CertificateService().generationCommands(certsDirectory: directory)

        #expect(commands.count == 5)
        #expect(commands[0] == ["openssl", "genrsa", "-out", "/tmp/proxy/certs/ca.key", "2048"])
        #expect(commands[4].contains("/tmp/proxy/certs/server.crt"))
        #expect(commands[4].contains("-extensions"))
        #expect(commands[4].contains("req_ext"))
    }

    @Test
    func trustCommandTargetsLoginKeychainWithoutRunningSecurity() {
        let directory = URL(fileURLWithPath: "/tmp/proxy/certs")
        let command = CertificateService().trustCommand(
            certsDirectory: directory,
            loginKeychainPath: "/Users/cj/Library/Keychains/login.keychain-db"
        )

        #expect(command == [
            "security",
            "add-trusted-cert",
            "-d",
            "-r",
            "trustRoot",
            "-k",
            "/Users/cj/Library/Keychains/login.keychain-db",
            "/tmp/proxy/certs/ca.crt",
        ])
    }
}
