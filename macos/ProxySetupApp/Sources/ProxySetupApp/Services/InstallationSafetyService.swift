import Foundation

enum ManagedFileChangeKind: String, Codable, Equatable {
    case create
    case update
    case unchanged
}

struct ManagedFileChange: Identifiable, Equatable {
    var id: String { targetURL.path }
    var title: String
    var targetURL: URL
    var proposedContents: String
}

struct DryRunFileDiff: Identifiable, Equatable {
    var id: String { change.id }
    var change: ManagedFileChange
    var kind: ManagedFileChangeKind
    var preview: String
}

struct BackupManifest: Codable, Equatable {
    var version: Int
    var createdAt: String
    var entries: [BackupEntry]
}

struct BackupEntry: Codable, Equatable {
    var title: String
    var targetPath: String
    var backupPath: String?
    var existed: Bool
}

struct BackupResult: Equatable {
    var manifest: BackupManifest
    var manifestURL: URL
}

struct InstallationConfirmation: Equatable {
    var reviewedDryRun = false
    var createdBackups = false
    var understandsSystemChanges = false
    var typedPhrase = ""

    static let requirements: [InstallationConfirmationRequirement] = [
        InstallationConfirmationRequirement(
            title: "查看 dry-run diff / Review dry-run diff",
            detail: "确认即将写入的文件、路径和内容差异。"
        ),
        InstallationConfirmationRequirement(
            title: "创建备份 / Create backups",
            detail: "写入真实配置前先生成 backup manifest。"
        ),
        InstallationConfirmationRequirement(
            title: "理解系统变更 / Understand system changes",
            detail: "确认将涉及客户端配置、LaunchAgent 或证书信任。"
        ),
        InstallationConfirmationRequirement(
            title: "输入确认词 / Type INSTALL",
            detail: "真实安装按钮接入前必须要求用户输入 INSTALL。"
        ),
    ]

    var canProceed: Bool {
        reviewedDryRun &&
            createdBackups &&
            understandsSystemChanges &&
            typedPhrase == "INSTALL"
    }
}

struct InstallationConfirmationRequirement: Identifiable, Equatable {
    var id: String { title }
    var title: String
    var detail: String
}

struct KeychainWriteConfirmation: Equatable {
    var reviewedAccounts = false
    var understandsKeychainWrite = false
    var typedPhrase = ""

    var canSave: Bool {
        reviewedAccounts &&
            understandsKeychainWrite &&
            typedPhrase == "KEYCHAIN"
    }
}

struct InstallationSafetyService {
    func dryRun(changes: [ManagedFileChange]) throws -> [DryRunFileDiff] {
        try changes.map { change in
            let current = try currentContents(at: change.targetURL)
            let kind: ManagedFileChangeKind
            if current == nil {
                kind = .create
            } else if current == change.proposedContents {
                kind = .unchanged
            } else {
                kind = .update
            }
            return DryRunFileDiff(
                change: change,
                kind: kind,
                preview: preview(current: current, proposed: change.proposedContents)
            )
        }
    }

    func createBackups(
        for changes: [ManagedFileChange],
        backupDirectory: URL,
        timestamp: String
    ) throws -> BackupResult {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)

        var entries: [BackupEntry] = []
        for (index, change) in changes.enumerated() {
            let existed = fileManager.fileExists(atPath: change.targetURL.path)
            let backupURL: URL?

            if existed {
                let filename = backupFilename(index: index, change: change)
                let destination = backupDirectory.appendingPathComponent(filename)
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.removeItem(at: destination)
                }
                try fileManager.copyItem(at: change.targetURL, to: destination)
                backupURL = destination
            } else {
                backupURL = nil
            }

            entries.append(
                BackupEntry(
                    title: change.title,
                    targetPath: change.targetURL.path,
                    backupPath: backupURL?.path,
                    existed: existed
                )
            )
        }

        let manifest = BackupManifest(version: 1, createdAt: timestamp, entries: entries)
        let manifestURL = backupDirectory.appendingPathComponent("manifest-\(timestamp).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        try data.write(to: manifestURL, options: .atomic)

        return BackupResult(manifest: manifest, manifestURL: manifestURL)
    }

    func rollback(manifest: BackupManifest, allowedTargetRoots: [URL]) throws {
        let fileManager = FileManager.default

        for entry in manifest.entries {
            let targetURL = URL(fileURLWithPath: entry.targetPath)
            guard isAllowed(targetURL, roots: allowedTargetRoots) else {
                throw SafetyError.disallowedTarget(entry.targetPath)
            }

            if entry.existed {
                guard let backupPath = entry.backupPath else {
                    throw SafetyError.missingBackup(entry.targetPath)
                }
                let backupURL = URL(fileURLWithPath: backupPath)
                try fileManager.createDirectory(
                    at: targetURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                if fileManager.fileExists(atPath: targetURL.path) {
                    try fileManager.removeItem(at: targetURL)
                }
                try fileManager.copyItem(at: backupURL, to: targetURL)
            } else if fileManager.fileExists(atPath: targetURL.path) {
                try fileManager.removeItem(at: targetURL)
            }
        }
    }

    enum SafetyError: Error, Equatable {
        case missingBackup(String)
        case disallowedTarget(String)
    }

    private func currentContents(at url: URL) throws -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func preview(current: String?, proposed: String) -> String {
        guard let current else {
            return proposedLines(proposed).map { "+ \(redact($0))" }.joined(separator: "\n")
        }
        guard current != proposed else {
            return "No changes / 无变化"
        }

        let removed = currentLines(current).map { "- \(redact($0))" }
        let added = proposedLines(proposed).map { "+ \(redact($0))" }
        return (removed + added).joined(separator: "\n")
    }

    private func redact(_ value: String) -> String {
        LogService.redact(value)
            .replacingOccurrences(
                of: #"(?i)Bearer\s+[A-Za-z0-9._\-]+"#,
                with: "Bearer <REDACTED>",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"sk-[A-Za-z0-9._\-]+"#,
                with: "<REDACTED>",
                options: .regularExpression
            )
    }

    private func currentLines(_ value: String) -> [String] {
        value.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    private func proposedLines(_ value: String) -> [String] {
        value.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    private func backupFilename(index: Int, change: ManagedFileChange) -> String {
        let title = sanitize(change.title)
        let basename = sanitize(change.targetURL.lastPathComponent)
        return "\(index + 1)-\(title)-\(basename).bak"
    }

    private func sanitize(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let scalars = value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        return String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private func isAllowed(_ url: URL, roots: [URL]) -> Bool {
        let path = url.standardizedFileURL.path
        return roots.contains { root in
            let rootPath = root.standardizedFileURL.path
            return path == rootPath || path.hasPrefix(rootPath + "/")
        }
    }
}
