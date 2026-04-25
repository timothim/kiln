import XCTest
@testable import KilnCore

/// Tests for the M9.A local encrypted-backup service.
///
/// Strategy: write a tiny synthetic project to a tmp dir, back it up,
/// restore into a different tmp dir, assert byte-equality of every file.
/// All crypto runs in-process — no Keychain dependency in these tests
/// (the ``KeychainPassphraseStore`` has its own behaviour-only smoke).
final class BackupServiceTests: XCTestCase {

    private var tmpRoot: URL!

    override func setUpWithError() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kiln-backup-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tmpRoot = dir
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpRoot)
    }

    private func makeProject(_ files: [String: String]) throws -> URL {
        let projectURL = tmpRoot.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        for (relativePath, contents) in files {
            let fileURL = projectURL.appendingPathComponent(relativePath)
            let parent = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        }
        return projectURL
    }

    // MARK: - Round-trip

    func test_backup_then_restore_preserves_every_file_byte_for_byte() async throws {
        let projectURL = try makeProject([
            "corpus.jsonl": "{\"role\":\"user\",\"content\":\"hello\"}\n",
            "adapters/adapters.safetensors": "fakeweightbytes",
            "manifest.json": "{\"version\":1}",
            "nested/deep/file.txt": "deep contents",
        ])

        let backupsDir = tmpRoot.appendingPathComponent("backups", isDirectory: true)
        let restoreDir = tmpRoot.appendingPathComponent("restored", isDirectory: true)
        let service = DiskBackupService()
        let bundleURL = try await service.backup(
            projectRoot: projectURL,
            projectID: "proj-001",
            passphrase: "correct-horse-battery-staple",
            destinationDirectory: backupsDir
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: bundleURL.path))
        XCTAssertEqual(bundleURL.pathExtension, "kilnbackup")

        _ = try await service.restore(
            bundleURL: bundleURL,
            passphrase: "correct-horse-battery-staple",
            into: restoreDir
        )

        for relative in [
            "corpus.jsonl",
            "adapters/adapters.safetensors",
            "manifest.json",
            "nested/deep/file.txt",
        ] {
            let original = try Data(contentsOf: projectURL.appendingPathComponent(relative))
            let restored = try Data(contentsOf: restoreDir.appendingPathComponent(relative))
            XCTAssertEqual(original, restored, "byte mismatch for \(relative)")
        }
    }

    // MARK: - Wrong passphrase

    func test_restore_with_wrong_passphrase_throws_decryption_failed() async throws {
        let projectURL = try makeProject([
            "a.txt": "the secret content",
        ])
        let backupsDir = tmpRoot.appendingPathComponent("backups", isDirectory: true)
        let restoreDir = tmpRoot.appendingPathComponent("restored", isDirectory: true)
        let service = DiskBackupService()
        let bundleURL = try await service.backup(
            projectRoot: projectURL,
            projectID: "proj-002",
            passphrase: "right-passphrase",
            destinationDirectory: backupsDir
        )

        do {
            _ = try await service.restore(
                bundleURL: bundleURL,
                passphrase: "wrong-passphrase",
                into: restoreDir
            )
            XCTFail("expected decryptionFailed for wrong passphrase")
        } catch BackupError.decryptionFailed {
            // expected
        } catch {
            XCTFail("expected decryptionFailed, got \(error)")
        }
    }

    // MARK: - Bundle on-disk shape

    func test_bundle_starts_with_magic_header_and_required_lengths() async throws {
        let projectURL = try makeProject(["small.txt": "hi"])
        let backupsDir = tmpRoot.appendingPathComponent("backups", isDirectory: true)
        let bundleURL = try await DiskBackupService().backup(
            projectRoot: projectURL,
            projectID: "proj-003",
            passphrase: "passphrase-123",
            destinationDirectory: backupsDir
        )
        let data = try Data(contentsOf: bundleURL)
        // Magic prefix
        XCTAssertEqual(Array(data.prefix(BackupConstants.magic.count)), BackupConstants.magic)
        // Total ≥ header + at least one byte of ciphertext + 16-byte tag
        XCTAssertGreaterThan(data.count, BackupConstants.headerLength + 16)
    }

    func test_tampered_ciphertext_fails_to_decrypt() async throws {
        let projectURL = try makeProject(["small.txt": "hi"])
        let backupsDir = tmpRoot.appendingPathComponent("backups", isDirectory: true)
        let restoreDir = tmpRoot.appendingPathComponent("restored", isDirectory: true)
        let service = DiskBackupService()
        let bundleURL = try await service.backup(
            projectRoot: projectURL,
            projectID: "proj-tamper",
            passphrase: "passphrase-123",
            destinationDirectory: backupsDir
        )

        // Flip a single byte deep in the ciphertext (past the 36-byte header).
        var data = try Data(contentsOf: bundleURL)
        let target = data.endIndex - 8 // safely before the tag we can't reason about exactly
        data[target] ^= 0xFF
        try data.write(to: bundleURL, options: .atomic)

        do {
            _ = try await service.restore(
                bundleURL: bundleURL,
                passphrase: "passphrase-123",
                into: restoreDir
            )
            XCTFail("expected decryptionFailed after tampering")
        } catch BackupError.decryptionFailed {
            // expected — ChaChaPoly's AEAD detects the tamper
        } catch {
            XCTFail("expected decryptionFailed, got \(error)")
        }
    }

    func test_metadata_round_trips_project_id_and_entry_count() async throws {
        let projectURL = try makeProject([
            "a.txt": "1",
            "b/c.txt": "2",
            "b/d.txt": "3",
        ])
        let backupsDir = tmpRoot.appendingPathComponent("backups", isDirectory: true)
        let service = DiskBackupService()
        let bundleURL = try await service.backup(
            projectRoot: projectURL,
            projectID: "meta-test",
            passphrase: "passphrase-123",
            destinationDirectory: backupsDir
        )
        let meta = try await service.metadata(
            bundleURL: bundleURL,
            passphrase: "passphrase-123"
        )
        XCTAssertEqual(meta.projectID, "meta-test")
        XCTAssertEqual(meta.entryCount, 3)
        XCTAssertFalse(meta.createdAt.isEmpty)
    }

    // MARK: - Error edges

    func test_passphrase_too_short_rejects() async throws {
        let projectURL = try makeProject(["a.txt": "x"])
        do {
            _ = try await DiskBackupService().backup(
                projectRoot: projectURL,
                projectID: "p",
                passphrase: "short",
                destinationDirectory: nil
            )
            XCTFail("expected passphraseTooShort")
        } catch BackupError.passphraseTooShort {
            // expected
        } catch {
            XCTFail("expected passphraseTooShort, got \(error)")
        }
    }

    func test_missing_source_throws_sourceUnavailable() async throws {
        let missing = tmpRoot.appendingPathComponent("does-not-exist")
        do {
            _ = try await DiskBackupService().backup(
                projectRoot: missing,
                projectID: "p",
                passphrase: "passphrase-123",
                destinationDirectory: nil
            )
            XCTFail("expected sourceUnavailable")
        } catch BackupError.sourceUnavailable {
            // expected
        } catch {
            XCTFail("expected sourceUnavailable, got \(error)")
        }
    }

    func test_malformed_header_rejects_non_kiln_file() async throws {
        let restoreDir = tmpRoot.appendingPathComponent("restored", isDirectory: true)
        let bogus = tmpRoot.appendingPathComponent("not-a-bundle.kilnbackup")
        try Data("hello world".utf8).write(to: bogus)
        do {
            _ = try await DiskBackupService().restore(
                bundleURL: bogus,
                passphrase: "passphrase-123",
                into: restoreDir
            )
            XCTFail("expected malformedHeader")
        } catch BackupError.malformedHeader {
            // expected
        } catch {
            XCTFail("expected malformedHeader, got \(error)")
        }
    }

    // MARK: - Settings persistence (UserDefaults)

    func test_settings_keys_round_trip_through_user_defaults() {
        let suite = "kiln-backup-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(true, forKey: BackupSettings.enabledKey)
        defaults.set("2026-04-25T10:30:00Z", forKey: BackupSettings.lastBackupISO8601Key)

        XCTAssertTrue(defaults.bool(forKey: BackupSettings.enabledKey))
        XCTAssertEqual(
            defaults.string(forKey: BackupSettings.lastBackupISO8601Key),
            "2026-04-25T10:30:00Z"
        )
    }

    // MARK: - In-memory passphrase store

    func test_in_memory_passphrase_store_round_trips() throws {
        let store = InMemoryPassphraseStore()
        XCTAssertNil(try store.getPassphrase(account: "alice"))
        try store.setPassphrase("hunter2-secret", account: "alice")
        XCTAssertEqual(try store.getPassphrase(account: "alice"), "hunter2-secret")
        try store.deletePassphrase(account: "alice")
        XCTAssertNil(try store.getPassphrase(account: "alice"))
    }
}
