import Foundation

/// Legacy cloud-upload entry point. M9.A delivers *local* encrypted
/// backup via ``DiskBackupService`` in
/// ``packages/KilnCore/Sources/KilnCore/Backup/BackupService.swift``;
/// production callers wanting backup should construct a
/// ``DiskBackupService`` directly. Cloud upload (iCloud Drive / S3) is
/// intentionally still out of scope per CLAUDE.md ("no cloud sync, no
/// telemetry"); the methods below remain disabled until a fresh
/// `DECISIONS.md` entry spells out provider, on-device encryption,
/// consent flow, and key custody. ``isImplemented`` therefore stays
/// false — it tracks *cloud* upload, not local backup.
public enum CloudBackup {
    public static let isImplemented = false

    public enum Provider: String, Sendable, CaseIterable {
        case iCloudDrive
        case userProvidedS3
    }

    public enum BackupError: Error, Equatable {
        case disabledByScope
    }

    public static func upload(bundleAt _: URL, to _: Provider) async throws {
        throw BackupError.disabledByScope
    }

    public static func listBackups(_: Provider) async throws -> [URL] {
        throw BackupError.disabledByScope
    }
}
