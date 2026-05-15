import Foundation
import Testing
@testable import ProxySetupApp

struct InstallationSafetyServiceTests {
    @Test
    func dryRunShowsCreateUpdateAndUnchangedWithoutWritingTargets() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)

        let existing = temp.appendingPathComponent("settings.json")
        let missing = temp.appendingPathComponent("config.toml")
        let unchanged = temp.appendingPathComponent("unchanged.txt")
        try "old\n".write(to: existing, atomically: true, encoding: .utf8)
        try "same\n".write(to: unchanged, atomically: true, encoding: .utf8)

        let changes = [
            ManagedFileChange(title: "Claude CLI", targetURL: existing, proposedContents: "new\n"),
            ManagedFileChange(title: "Codex", targetURL: missing, proposedContents: "created\n"),
            ManagedFileChange(title: "No-op", targetURL: unchanged, proposedContents: "same\n"),
        ]

        let diffs = try InstallationSafetyService().dryRun(changes: changes)

        #expect(diffs.map(\.kind) == [.update, .create, .unchanged])
        #expect(diffs[0].preview.contains("- old"))
        #expect(diffs[0].preview.contains("+ new"))
        #expect(diffs[1].preview.contains("+ created"))
        #expect(try String(contentsOf: existing, encoding: .utf8) == "old\n")
        #expect(!FileManager.default.fileExists(atPath: missing.path))
    }

    @Test
    func dryRunRedactsSecretsFromPreview() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)

        let existing = temp.appendingPathComponent("settings.json")
        try #"{"Authorization":"Bearer old-secret","api_key":"sk-oldsecret"}"#
            .write(to: existing, atomically: true, encoding: .utf8)

        let changes = [
            ManagedFileChange(
                title: "Secrets",
                targetURL: existing,
                proposedContents: #"{"Authorization":"Bearer new-secret","api_key":"sk-newsecret"}"#
            ),
        ]

        let diff = try #require(InstallationSafetyService().dryRun(changes: changes).first)

        #expect(diff.preview.contains("<REDACTED>"))
        #expect(!diff.preview.contains("old-secret"))
        #expect(!diff.preview.contains("new-secret"))
        #expect(!diff.preview.contains("sk-oldsecret"))
        #expect(!diff.preview.contains("sk-newsecret"))
    }

    @Test
    func createBackupsWritesManifestAndLeavesTargetsUntouched() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let backups = temp.appendingPathComponent("backups")
        defer { try? FileManager.default.removeItem(at: temp) }
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)

        let existing = temp.appendingPathComponent("settings.json")
        let missing = temp.appendingPathComponent("missing.toml")
        try "current settings".write(to: existing, atomically: true, encoding: .utf8)

        let changes = [
            ManagedFileChange(title: "Claude CLI", targetURL: existing, proposedContents: "next"),
            ManagedFileChange(title: "Codex", targetURL: missing, proposedContents: "created"),
        ]

        let result = try InstallationSafetyService().createBackups(
            for: changes,
            backupDirectory: backups,
            timestamp: "20260515203000"
        )

        #expect(FileManager.default.fileExists(atPath: result.manifestURL.path))
        #expect(result.manifest.entries.count == 2)
        #expect(result.manifest.entries[0].existed)
        #expect(!result.manifest.entries[1].existed)
        #expect(result.manifest.entries[0].backupPath != nil)
        #expect(result.manifest.entries[1].backupPath == nil)
        #expect(try String(contentsOf: existing, encoding: .utf8) == "current settings")

        let backupPath = try #require(result.manifest.entries[0].backupPath)
        #expect(try String(contentsOfFile: backupPath, encoding: .utf8) == "current settings")

        let manifestText = try String(contentsOf: result.manifestURL, encoding: .utf8)
        #expect(manifestText.contains("Claude CLI"))
        #expect(!manifestText.contains("next"))
    }

    @Test
    func rollbackRestoresExistingFilesAndRemovesCreatedFiles() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let backups = temp.appendingPathComponent("backups")
        defer { try? FileManager.default.removeItem(at: temp) }
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)

        let existing = temp.appendingPathComponent("settings.json")
        let created = temp.appendingPathComponent("new.toml")
        try "original".write(to: existing, atomically: true, encoding: .utf8)

        let changes = [
            ManagedFileChange(title: "Existing", targetURL: existing, proposedContents: "changed"),
            ManagedFileChange(title: "Created", targetURL: created, proposedContents: "new"),
        ]
        let result = try InstallationSafetyService().createBackups(
            for: changes,
            backupDirectory: backups,
            timestamp: "20260515203100"
        )

        try "changed".write(to: existing, atomically: true, encoding: .utf8)
        try "new".write(to: created, atomically: true, encoding: .utf8)

        try InstallationSafetyService().rollback(manifest: result.manifest, allowedTargetRoots: [temp])

        #expect(try String(contentsOf: existing, encoding: .utf8) == "original")
        #expect(!FileManager.default.fileExists(atPath: created.path))
    }

    @Test
    func rollbackRejectsTargetsOutsideAllowedRoots() throws {
        let manifest = BackupManifest(
            version: 1,
            createdAt: "20260515203200",
            entries: [
                BackupEntry(
                    title: "Outside",
                    targetPath: "/tmp/outside-config.toml",
                    backupPath: nil,
                    existed: false
                ),
            ]
        )

        #expect(throws: InstallationSafetyService.SafetyError.disallowedTarget("/tmp/outside-config.toml")) {
            try InstallationSafetyService().rollback(
                manifest: manifest,
                allowedTargetRoots: [URL(fileURLWithPath: "/tmp/allowed")]
            )
        }
    }

    @Test
    func confirmationRequiresEveryAcknowledgementAndPhrase() {
        var confirmation = InstallationConfirmation()
        #expect(!confirmation.canProceed)
        #expect(InstallationConfirmation.requirements.count == 4)
        #expect(InstallationConfirmation.requirements[0].title.contains("dry-run"))

        confirmation.reviewedDryRun = true
        confirmation.createdBackups = true
        confirmation.understandsSystemChanges = true
        confirmation.typedPhrase = "INSTALL"

        #expect(confirmation.canProceed)
    }

    @Test
    func keychainWriteConfirmationRequiresPhrase() {
        var confirmation = KeychainWriteConfirmation()
        confirmation.reviewedAccounts = true
        confirmation.understandsKeychainWrite = true
        confirmation.typedPhrase = "INSTALL"

        #expect(!confirmation.canSave)

        confirmation.typedPhrase = "KEYCHAIN"
        #expect(confirmation.canSave)
    }
}
