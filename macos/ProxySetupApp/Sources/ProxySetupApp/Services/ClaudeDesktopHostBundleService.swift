import Foundation

struct ClaudeDesktopEnvironment: Equatable {
    var supportDirectoryName: String
    var homeDirectory: URL

    init(
        supportDirectoryName: String = SetupConfiguration.default.claudeDesktopSupportDirectoryName,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.supportDirectoryName = supportDirectoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.homeDirectory = homeDirectory
    }

    var supportRoot: URL {
        homeDirectory
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(supportDirectoryName, isDirectory: true)
    }

    var configLibraryURL: URL {
        supportRoot.appendingPathComponent("configLibrary", isDirectory: true)
    }

    var desktopModeURL: URL {
        supportRoot.appendingPathComponent("claude_desktop_config.json")
    }

    var hostBundleRootURL: URL {
        supportRoot.appendingPathComponent("claude-code", isDirectory: true)
    }

    var hostVMRootURL: URL {
        supportRoot.appendingPathComponent("claude-code-vm", isDirectory: true)
    }

    var vmBundleURL: URL {
        supportRoot.appendingPathComponent("vm_bundles/claudevm.bundle", isDirectory: true)
    }

    var logURL: URL {
        homeDirectory
            .appendingPathComponent("Library/Logs", isDirectory: true)
            .appendingPathComponent(supportDirectoryName, isDirectory: true)
            .appendingPathComponent("main.log")
    }
}

enum ClaudeDesktopHostCheckStatus: String, Equatable {
    case ok
    case warning
    case missing
}

struct ClaudeDesktopHostCheck: Identifiable, Equatable {
    var id: String { title }
    var title: String
    var path: String
    var status: ClaudeDesktopHostCheckStatus
    var detail: String
}

struct ClaudeDesktopHostBundleStatus: Equatable {
    var environment: ClaudeDesktopEnvironment
    var version: String?
    var checks: [ClaudeDesktopHostCheck]

    var isHostBinaryReady: Bool {
        version != nil &&
            checkStatus("Desktop host verified marker") == .ok &&
            checkStatus("Desktop host executable") == .ok &&
            checkStatus("Desktop direct executable") == .ok
    }

    var summary: String {
        guard let version else {
            return "未找到 Desktop host 版本；请先打开 Claude Desktop 一次。"
        }
        return isHostBinaryReady
            ? "Desktop host \(version) 已就绪。"
            : "Desktop host \(version) 缺少运行组件，可执行离线初始化。"
    }

    private func checkStatus(_ title: String) -> ClaudeDesktopHostCheckStatus? {
        checks.first { $0.title == title }?.status
    }
}

struct ClaudeDesktopHostBundleResult: Equatable {
    var status: ClaudeDesktopHostBundleStatus
    var commandRecords: [InstallationCommandRecord]
}

struct ClaudeDesktopHostBundleService {
    func inspect(environment: ClaudeDesktopEnvironment) throws -> ClaudeDesktopHostBundleStatus {
        let version = try resolveVersion(environment: environment)
        var checks: [ClaudeDesktopHostCheck] = [
            ClaudeDesktopHostCheck(
                title: "Desktop data root",
                path: environment.supportRoot.path,
                status: FileManager.default.fileExists(atPath: environment.supportRoot.path) ? .ok : .warning,
                detail: "当前使用的 Claude Desktop 3P 数据目录。"
            ),
            ClaudeDesktopHostCheck(
                title: "Desktop log",
                path: environment.logURL.path,
                status: FileManager.default.fileExists(atPath: environment.logURL.path) ? .ok : .warning,
                detail: version == nil ? "未找到可解析 host 版本的日志。" : "已从日志解析 host 版本。"
            ),
        ]

        guard let version else {
            checks.append(
                ClaudeDesktopHostCheck(
                    title: "Desktop host version",
                    path: environment.logURL.path,
                    status: .missing,
                    detail: "未解析到版本号。请先启动 Claude Desktop，或稍后重试。"
                )
            )
            return ClaudeDesktopHostBundleStatus(environment: environment, version: nil, checks: checks)
        }

        let versionRoot = hostVersionRoot(environment: environment, version: version)
        let verifiedURL = versionRoot.appendingPathComponent(".verified")
        let desktopExecutableURL = desktopExecutableURL(environment: environment, version: version)
        let directExecutableURL = directExecutableURL(environment: environment, version: version)
        let vmVersionURL = environment.hostVMRootURL.appendingPathComponent(version, isDirectory: true)

        checks.append(contentsOf: [
            fileCheck(
                title: "Desktop host verified marker",
                url: verifiedURL,
                missingStatus: .missing,
                okDetail: "已存在 .verified，Desktop 不会把目录当作未完成下载。",
                missingDetail: "缺少 .verified，Desktop 可能继续 repair/download。"
            ),
            fileCheck(
                title: "Desktop host executable",
                url: desktopExecutableURL,
                missingStatus: .missing,
                okDetail: "Desktop 期望的 claude.app 入口已存在。",
                missingDetail: "缺少 claude.app/Contents/MacOS/claude。"
            ),
            fileCheck(
                title: "Desktop direct executable",
                url: directExecutableURL,
                missingStatus: .missing,
                okDetail: "同级 claude 入口已存在。",
                missingDetail: "缺少同级 claude 入口。"
            ),
            fileCheck(
                title: "Desktop VM version directory",
                url: vmVersionURL,
                missingStatus: .warning,
                okDetail: "VM 版本目录存在。",
                missingDetail: "VM 版本目录缺失；Cowork/VM 能力可能仍需官方 bundle。"
            ),
            fileCheck(
                title: "Desktop VM bundle",
                url: environment.vmBundleURL,
                missingStatus: .warning,
                okDetail: "VM bundle 目录存在。",
                missingDetail: "VM bundle 缺失；Cowork/VM 能力可能仍需官方 bundle。"
            ),
        ])

        return ClaudeDesktopHostBundleStatus(environment: environment, version: version, checks: checks)
    }

    func initializeFromLocalCLI(
        environment: ClaudeDesktopEnvironment,
        proxyDirectory: URL,
        config: SetupConfiguration,
        runner: CommandRunning = CommandRunner(),
        progress: InstallationProgressHandler? = nil
    ) async throws -> ClaudeDesktopHostBundleResult {
        await emit(
            title: "初始化 Claude Desktop Host / Initialize Desktop Host",
            detail: "正在检查 Desktop host 版本和本机 claude CLI",
            status: .running,
            progress: progress
        )
        let initialStatus = try inspect(environment: environment)
        guard let version = initialStatus.version else {
            await emit(
                title: "初始化 Claude Desktop Host / Initialize Desktop Host",
                detail: "未解析到 Desktop host 版本；请先打开 Claude Desktop 一次。",
                status: .skipped,
                progress: progress
            )
            return ClaudeDesktopHostBundleResult(status: initialStatus, commandRecords: [])
        }
        if initialStatus.isHostBinaryReady {
            await emit(
                title: "初始化 Claude Desktop Host / Initialize Desktop Host",
                detail: "Desktop host \(version) 已就绪，跳过初始化。",
                status: .skipped,
                progress: progress
            )
            return ClaudeDesktopHostBundleResult(status: initialStatus, commandRecords: [])
        }

        let cliPathResult = await runner.run("command", ["-v", "claude"])
        let claudeCLIPath = cliPathResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cliPathResult.exitCode == 0, !claudeCLIPath.isEmpty else {
            await emit(
                title: "初始化 Claude Desktop Host / Initialize Desktop Host",
                detail: "未找到 claude CLI，无法离线初始化 Desktop host。",
                status: .failed,
                progress: progress
            )
            throw HostBundleError.missingClaudeCLI
        }

        let launcherURL = proxyDirectory.appendingPathComponent("bin/claude-ca-launcher")
        let versionRoot = hostVersionRoot(environment: environment, version: version)
        let desktopExecutableURL = desktopExecutableURL(environment: environment, version: version)
        let directExecutableURL = directExecutableURL(environment: environment, version: version)

        try writeLauncher(
            launcherURL: launcherURL,
            claudeCLIPath: claudeCLIPath,
            caURL: proxyDirectory.appendingPathComponent("certs/ca.crt"),
            baseURL: config.claudeDesktopBaseURL
        )
        try FileManager.default.createDirectory(
            at: desktopExecutableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: versionRoot, withIntermediateDirectories: true)
        try replaceSymlink(at: desktopExecutableURL, destination: launcherURL)
        try replaceSymlink(at: directExecutableURL, destination: launcherURL)
        try Data().write(to: versionRoot.appendingPathComponent(".verified"), options: .atomic)

        let records = [
            InstallationCommandRecord(
                title: "Initialize Claude Desktop Host",
                command: ["ln", "-sfn", launcherURL.path, desktopExecutableURL.path],
                exitCode: 0,
                stdout: "ok",
                stderr: ""
            ),
            InstallationCommandRecord(
                title: "Initialize Claude Desktop Host",
                command: ["ln", "-sfn", launcherURL.path, directExecutableURL.path],
                exitCode: 0,
                stdout: "ok",
                stderr: ""
            ),
        ]
        let finalStatus = try inspect(environment: environment)
        await emit(
            title: "初始化 Claude Desktop Host / Initialize Desktop Host",
            detail: "已初始化 Desktop host \(version)，并写入 .verified。",
            status: .succeeded,
            progress: progress
        )
        return ClaudeDesktopHostBundleResult(status: finalStatus, commandRecords: records)
    }

    enum HostBundleError: LocalizedError, Equatable {
        case missingClaudeCLI
        case targetAlreadyExists(String)

        var errorDescription: String? {
            switch self {
            case .missingClaudeCLI:
                return "未找到 claude CLI。请先安装 Claude Code CLI，或后续使用离线 bundle 导入。"
            case .targetAlreadyExists(let path):
                return "目标文件已存在且不是本 App 可安全替换的软链：\(path)"
            }
        }
    }

    private func resolveVersion(environment: ClaudeDesktopEnvironment) throws -> String? {
        if let logVersion = try versionFromLog(environment.logURL) {
            return logVersion
        }
        return versionFromDirectory(environment.hostBundleRootURL)
    }

    private func versionFromLog(_ url: URL) throws -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let content = try String(contentsOf: url, encoding: .utf8)
        let patterns = [
            #"\[CCD\]\s+Initialized with version\s+([0-9]+(?:\.[0-9]+)+)"#,
            #"claude-code-releases/([0-9]+(?:\.[0-9]+)+)/"#,
            #"claude-code-vm/([0-9]+(?:\.[0-9]+)+)"#,
        ]
        var matches: [String] = []
        for pattern in patterns {
            let regex = try NSRegularExpression(pattern: pattern)
            let range = NSRange(content.startIndex..<content.endIndex, in: content)
            for match in regex.matches(in: content, range: range) {
                guard match.numberOfRanges > 1,
                      let versionRange = Range(match.range(at: 1), in: content) else {
                    continue
                }
                matches.append(String(content[versionRange]))
            }
        }
        return matches.last
    }

    private func versionFromDirectory(_ url: URL) -> String? {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        return contents
            .map(\.lastPathComponent)
            .filter { $0.range(of: #"^[0-9]+(?:\.[0-9]+)+$"#, options: .regularExpression) != nil }
            .sorted { $0.compare($1, options: .numeric) == .orderedAscending }
            .last
    }

    private func hostVersionRoot(environment: ClaudeDesktopEnvironment, version: String) -> URL {
        environment.hostBundleRootURL.appendingPathComponent(version, isDirectory: true)
    }

    private func desktopExecutableURL(environment: ClaudeDesktopEnvironment, version: String) -> URL {
        hostVersionRoot(environment: environment, version: version)
            .appendingPathComponent("claude.app/Contents/MacOS/claude")
    }

    private func directExecutableURL(environment: ClaudeDesktopEnvironment, version: String) -> URL {
        hostVersionRoot(environment: environment, version: version)
            .appendingPathComponent("claude")
    }

    private func fileCheck(
        title: String,
        url: URL,
        missingStatus: ClaudeDesktopHostCheckStatus,
        okDetail: String,
        missingDetail: String
    ) -> ClaudeDesktopHostCheck {
        let exists = FileManager.default.fileExists(atPath: url.path)
        return ClaudeDesktopHostCheck(
            title: title,
            path: url.path,
            status: exists ? .ok : missingStatus,
            detail: exists ? okDetail : missingDetail
        )
    }

    private func writeLauncher(
        launcherURL: URL,
        claudeCLIPath: String,
        caURL: URL,
        baseURL: URL
    ) throws {
        try FileManager.default.createDirectory(
            at: launcherURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let script = """
        #!/bin/zsh
        export NODE_USE_SYSTEM_CA=1
        export NODE_EXTRA_CA_CERTS=\(shellQuote(caURL.path))
        export SSL_CERT_FILE=\(shellQuote(caURL.path))
        export ANTHROPIC_BASE_URL=\(shellQuote(baseURL.absoluteString))
        export ANTHROPIC_AUTH_TOKEN=CJ_LOCAL_PROXY_TOKEN
        exec \(shellQuote(claudeCLIPath)) "$@"
        """
        try script.write(to: launcherURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: launcherURL.path
        )
    }

    private func replaceSymlink(at url: URL, destination: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: url.path) || isSymlink(url) {
            if isSymlink(url) {
                try fileManager.removeItem(at: url)
            } else {
                throw HostBundleError.targetAlreadyExists(url.path)
            }
        }
        try fileManager.createSymbolicLink(at: url, withDestinationURL: destination)
    }

    private func isSymlink(_ url: URL) -> Bool {
        ((try? FileManager.default.attributesOfItem(atPath: url.path)[.type]) as? FileAttributeType) == .typeSymbolicLink
    }

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func emit(
        title: String,
        detail: String,
        status: InstallationProgressStatus,
        progress: InstallationProgressHandler?
    ) async {
        await progress?(
            InstallationProgressEvent(
                title: title,
                detail: detail,
                status: status
            )
        )
    }
}
