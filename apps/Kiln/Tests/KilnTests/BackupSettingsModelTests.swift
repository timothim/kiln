import KilnCore
import XCTest
@testable import Kiln

/// Tests for the M9.A Settings panel's backing model.
///
/// Two surfaces under test:
///   1. Toggle persistence — flipping the switch writes to UserDefaults.
///   2. ``backupNow(passphrase:projectID:)`` round-trips status correctly,
///      using a real ``DiskBackupService`` against a tmp project.
@MainActor
final class BackupSettingsModelTests: XCTestCase {

    private func makeDefaults() -> UserDefaults {
        let suite = "kiln-backup-settings-test-\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    private func makeProject(_ files: [String: String]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kiln-bsm-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let project = dir.appendingPathComponent("p", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        for (rel, contents) in files {
            try contents.write(
                to: project.appendingPathComponent(rel),
                atomically: true,
                encoding: .utf8
            )
        }
        return project
    }

    func test_toggle_persists_to_user_defaults() throws {
        let defaults = makeDefaults()
        let model = BackupSettingsModel(defaults: defaults)
        XCTAssertFalse(model.enabled, "default should be off")

        model.enabled = true
        XCTAssertTrue(defaults.bool(forKey: BackupSettings.enabledKey))

        model.enabled = false
        XCTAssertFalse(defaults.bool(forKey: BackupSettings.enabledKey))
    }

    func test_backup_now_succeeds_and_writes_lastBackup_timestamp() async throws {
        let projectURL = try makeProject(["corpus.jsonl": "{\"hi\":1}\n"])
        defer { try? FileManager.default.removeItem(at: projectURL.deletingLastPathComponent()) }
        let defaults = makeDefaults()
        let model = BackupSettingsModel(
            defaults: defaults,
            projectRootProvider: { projectURL }
        )

        await model.backupNow(passphrase: "passphrase-123", projectID: "test-proj")

        switch model.status {
        case .succeeded(let url, let stamp):
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
            XCTAssertFalse(stamp.isEmpty)
            XCTAssertEqual(defaults.string(forKey: BackupSettings.lastBackupISO8601Key), stamp)
        default:
            XCTFail("expected .succeeded, got \(model.status)")
        }
    }

    func test_backup_now_with_no_project_root_reports_failure() async {
        let model = BackupSettingsModel(
            defaults: makeDefaults(),
            projectRootProvider: { nil }
        )
        await model.backupNow(passphrase: "passphrase-123", projectID: "test-proj")

        if case .failed(let message) = model.status {
            XCTAssertTrue(message.lowercased().contains("project"))
        } else {
            XCTFail("expected .failed, got \(model.status)")
        }
    }

    func test_backup_now_with_short_passphrase_reports_failure() async throws {
        let projectURL = try makeProject(["a.txt": "1"])
        defer { try? FileManager.default.removeItem(at: projectURL.deletingLastPathComponent()) }
        let model = BackupSettingsModel(
            defaults: makeDefaults(),
            projectRootProvider: { projectURL }
        )
        await model.backupNow(passphrase: "short", projectID: "p")

        if case .failed(let message) = model.status {
            XCTAssertTrue(message.contains("\(BackupSettings.minPassphraseLength)"))
        } else {
            XCTFail("expected .failed, got \(model.status)")
        }
    }
}
