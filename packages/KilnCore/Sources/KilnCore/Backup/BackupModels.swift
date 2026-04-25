import Foundation

/// On-disk format and types for the M9.A local backup feature.
///
/// **Constraints from CLAUDE.md scope guardrails ("no cloud sync"):**
/// the directive in M9.A is *local* backup only — encrypted bundles
/// land in `~/Documents/Kiln/Backups/`, no remote upload. The provider
/// pluggability (iCloud Drive / S3) outlined in the M9 plan is
/// intentionally deferred. The shape below leaves room for it: a future
/// uploader takes the same ``BackupBundle`` we already write locally.
///
/// **Bundle wire format (v1):**
///
///     bytes 0..7    magic "KILN0001"  (8B, identifies the file as a Kiln backup)
///     bytes 8..23   salt              (16B, random per-bundle, PBKDF input)
///     bytes 24..35  nonce             (12B, ChaChaPoly nonce)
///     bytes 36..    ciphertext + tag  (ChaChaPoly.SealedBox.combined)
///
/// The ciphertext decrypts to a JSON-encoded ``BackupPayload`` — a flat
/// list of ``BackupEntry`` rows (path + base64-encoded contents). Single-
/// file format keeps the implementation tractable for the demo; a future
/// milestone can swap in a streaming tar layout for projects > ~100 MB.

public enum BackupConstants {
    /// Header magic. Eight ASCII bytes — matches `"KILN0001"`.
    public static let magic: [UInt8] = Array("KILN0001".utf8)

    public static let saltLength: Int = 16
    public static let nonceLength: Int = 12

    /// Header size = magic + salt + nonce.
    public static var headerLength: Int { magic.count + saltLength + nonceLength }

    /// PBKDF2 iteration count for passphrase → key derivation. Tuned for a
    /// ~100 ms cost on Apple Silicon — slow enough to deter trivial brute
    /// force, fast enough that the user doesn't notice on a single backup.
    public static let pbkdf2Iterations: Int = 200_000

    /// Symmetric key length for ChaChaPoly is fixed at 32 bytes.
    public static let keyLengthBytes: Int = 32
}

/// A single file inside a backup bundle. Paths are stored relative to the
/// project root the user backed up; the restorer recreates the layout under
/// a fresh destination.
public struct BackupEntry: Sendable, Hashable, Codable {
    public let path: String
    public let contentsBase64: String
    public let size: Int

    public init(path: String, contentsBase64: String, size: Int) {
        self.path = path
        self.contentsBase64 = contentsBase64
        self.size = size
    }
}

/// What the encrypted blob decodes to.
public struct BackupPayload: Sendable, Hashable, Codable {
    public let formatVersion: Int
    public let projectID: String
    public let createdAtISO8601: String
    public let entries: [BackupEntry]

    public init(formatVersion: Int = 1, projectID: String, createdAtISO8601: String, entries: [BackupEntry]) {
        self.formatVersion = formatVersion
        self.projectID = projectID
        self.createdAtISO8601 = createdAtISO8601
        self.entries = entries
    }
}

public enum BackupError: Error, Equatable, Sendable {
    /// Bundle read but header magic doesn't match. Probably the wrong file.
    case malformedHeader
    /// Decryption failed — almost always wrong passphrase.
    case decryptionFailed
    /// Bundle decrypted but JSON didn't parse. Should not happen for files
    /// we wrote ourselves; included so a corrupted bundle surfaces cleanly.
    case payloadDecodeFailed(message: String)
    /// Source path didn't exist or wasn't readable.
    case sourceUnavailable(path: String)
    /// The destination directory couldn't be created.
    case destinationUnavailable(path: String)
    /// User passphrase was empty or under the minimum length.
    case passphraseTooShort
}

public enum BackupSettings {
    /// UserDefaults key for the user's "backups enabled" toggle. Off by
    /// default. The toggle is opt-in; M9.A never writes a backup without
    /// the user having flipped this on AND clicked "Back up now".
    public static let enabledKey = "dev.kiln.backups.enabled"

    /// UserDefaults key holding the ISO-8601 timestamp of the last
    /// successful backup. Drives the "Last backup: 2 days ago" line in
    /// the Settings panel.
    public static let lastBackupISO8601Key = "dev.kiln.backups.lastBackupISO8601"

    /// Default location for backup bundles. Under `~/Documents/Kiln/Backups/`
    /// so they survive an app reinstall and are visible in Finder.
    public static func defaultBackupsDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents")
        return docs.appendingPathComponent("Kiln/Backups", isDirectory: true)
    }

    /// Minimum acceptable passphrase length. 8 chars is a low bar; the goal
    /// is to catch accidental empty submissions, not enforce real entropy
    /// (the user is responsible for that — UI nudges them but we don't gate).
    public static let minPassphraseLength: Int = 8
}
