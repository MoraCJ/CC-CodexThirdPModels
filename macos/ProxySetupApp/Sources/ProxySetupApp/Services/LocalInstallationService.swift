import Darwin
import Foundation

struct InstallationEnvironment: Equatable {
    var installRoot: URL
    var launchAgentDirectory: URL
    var nodePath: String
    var userID: Int
    var loginKeychainPath: String

    static func defaultEnvironment() -> InstallationEnvironment {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return InstallationEnvironment(
            installRoot: home.appendingPathComponent(
                "Library/Application Support/CJLocalProxy",
                isDirectory: true
            ),
            launchAgentDirectory: home.appendingPathComponent(
                "Library/LaunchAgents",
                isDirectory: true
            ),
            nodePath: "",
            userID: Int(getuid()),
            loginKeychainPath: home
                .appendingPathComponent("Library/Keychains/login.keychain-db")
                .path
        )
    }
}

struct InstallationPlanItem: Identifiable, Equatable {
    var id: String { title }
    var title: String
    var detail: String
}

struct LocalInstallationResult: Equatable {
    var installRoot: URL
    var proxyDirectory: URL
    var launchAgentPlistURL: URL
    var openSSLConfigURL: URL
    var launchCommands: LaunchAgentService.ControlCommands
    var trustCommand: [String]
    var verificationSummary: VerificationSummary
}

struct LocalInstallationService {
    var label: String = "com.cj.claude-local-https-proxy"

    func buildPlan(
        config: SetupConfiguration,
        environment: InstallationEnvironment = .defaultEnvironment()
    ) throws -> [InstallationPlanItem] {
        try config.validate()

        let installer = ProxyInstaller(installRoot: environment.installRoot)
        let launchAgentURL = environment.launchAgentDirectory
            .appendingPathComponent("\(label).plist")
        let launchCommands = LaunchAgentService(label: label).controlCommands(
            plistURL: launchAgentURL,
            userID: environment.userID
        )
        let trustCommand = CertificateService().trustCommand(
            certsDirectory: installer.proxyDirectory.appendingPathComponent("certs", isDirectory: true),
            loginKeychainPath: environment.loginKeychainPath
        )

        return [
            InstallationPlanItem(
                title: "校验配置 / Validate configuration",
                detail: "确认 provider URL、模型名、端口和 profile 可用。"
            ),
            InstallationPlanItem(
                title: "复制代理文件 / Copy proxy files",
                detail: installer.proxyDirectory.path
            ),
            InstallationPlanItem(
                title: "写入运行配置 / Write runtime config",
                detail: environment.installRoot.appendingPathComponent("config/proxy.env").path
            ),
            InstallationPlanItem(
                title: "生成证书配置 / Prepare certificate config",
                detail: installer.proxyDirectory
                    .appendingPathComponent("certs/openssl-server.cnf")
                    .path
            ),
            InstallationPlanItem(
                title: "写入 LaunchAgent / Write LaunchAgent",
                detail: "\(launchAgentURL.path) with RunAtLoad + KeepAlive"
            ),
            InstallationPlanItem(
                title: "准备启动命令 / Prepare launchctl commands",
                detail: launchCommands.bootstrap.joined(separator: " ")
            ),
            InstallationPlanItem(
                title: "准备证书信任命令 / Prepare certificate trust",
                detail: trustCommand.joined(separator: " ")
            ),
            InstallationPlanItem(
                title: "准备验证端点 / Prepare verification",
                detail: VerificationService.healthURLs(config: config)
                    .map(\.absoluteString)
                    .joined(separator: ", ")
            ),
        ]
    }

    func prepareLocalFiles(
        config: SetupConfiguration,
        environment: InstallationEnvironment,
        proxySourceDirectory: URL? = nil
    ) throws -> LocalInstallationResult {
        try config.validate()

        let fileManager = FileManager.default
        let installer = ProxyInstaller(installRoot: environment.installRoot)
        try installer.createDirectories()

        if let proxySourceDirectory {
            try installer.copyProxyFiles(from: proxySourceDirectory)
        } else {
            try installer.copyBundledProxyFiles()
        }

        try installer.writeRuntimeConfig(config)

        let certsDirectory = installer.proxyDirectory
            .appendingPathComponent("certs", isDirectory: true)
        let openSSLConfigURL = certsDirectory
            .appendingPathComponent("openssl-server.cnf")
        try CertificateService.renderOpenSSLConfig()
            .write(to: openSSLConfigURL, atomically: true, encoding: .utf8)

        try fileManager.createDirectory(
            at: environment.launchAgentDirectory,
            withIntermediateDirectories: true
        )
        let launchAgentPlistURL = environment.launchAgentDirectory
            .appendingPathComponent("\(label).plist")
        let launchAgentService = LaunchAgentService(label: label)
        let plist = launchAgentService.renderPlist(
            nodePath: environment.nodePath,
            proxyDirectory: installer.proxyDirectory,
            config: config
        )
        try plist.write(to: launchAgentPlistURL, atomically: true, encoding: .utf8)

        let launchCommands = launchAgentService.controlCommands(
            plistURL: launchAgentPlistURL,
            userID: environment.userID
        )
        let trustCommand = CertificateService().trustCommand(
            certsDirectory: certsDirectory,
            loginKeychainPath: environment.loginKeychainPath
        )

        return LocalInstallationResult(
            installRoot: environment.installRoot,
            proxyDirectory: installer.proxyDirectory,
            launchAgentPlistURL: launchAgentPlistURL,
            openSSLConfigURL: openSSLConfigURL,
            launchCommands: launchCommands,
            trustCommand: trustCommand,
            verificationSummary: VerificationService.pendingSummary(config: config)
        )
    }

    func managedFileChanges(
        config: SetupConfiguration,
        environment: InstallationEnvironment = .defaultEnvironment()
    ) throws -> [ManagedFileChange] {
        try config.validate()

        let installer = ProxyInstaller(installRoot: environment.installRoot)
        let launchAgentURL = environment.launchAgentDirectory
            .appendingPathComponent("\(label).plist")
        let plist = LaunchAgentService(label: label).renderPlist(
            nodePath: environment.nodePath,
            proxyDirectory: installer.proxyDirectory,
            config: config
        )

        return [
            ManagedFileChange(
                title: "Proxy runtime config",
                targetURL: environment.installRoot.appendingPathComponent("config/proxy.env"),
                proposedContents: installer.renderRuntimeConfig(config)
            ),
            ManagedFileChange(
                title: "OpenSSL server config",
                targetURL: installer.proxyDirectory
                    .appendingPathComponent("certs/openssl-server.cnf"),
                proposedContents: CertificateService.renderOpenSSLConfig()
            ),
            ManagedFileChange(
                title: "LaunchAgent plist",
                targetURL: launchAgentURL,
                proposedContents: plist
            ),
        ]
    }
}
