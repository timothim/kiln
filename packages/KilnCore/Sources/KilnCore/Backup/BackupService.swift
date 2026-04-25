import CryptoKit
import Foundation
import OSLog

/// Local encrypted-backup service for Kiln projects (M9.A).
///
/// Reads a project directory, walks every file under it, encrypts the
/// flattened contents into a single ``.kilnbackup`` bundle on disk under
/// ``~/Documents/Kiln/Backups/`` (or a caller-supplied directory). The
/// reverse — ``restore(bundleURL:passphrase:into:)`` — decrypts the bundle
/// and writes the files back beneath a destination directory.
///
/// **Threat model.** Bundles sit on the user's filesystem; the threat we're
/// defending against is "someone copies my Kiln Backups folder off-disk
/// (cloud sync, stolen laptop) and tries to read voice training data."
/// The passphrase is the only secret; it lives in Keychain (see
/// ``PassphraseStore``) and is never written to a bundle.
///
/// **Crypto choices.** PBKDF2-HMAC-SHA256 with 200k iterations to derive
/// a 32-byte key from passphrase + per-bundle salt; ChaChaPoly seals the
/// flattened payload. CryptoKit's HKDF is for key-from-key derivation, not
/// passphrase-stretching — that's why we use CommonCrypto's PBKDF2 instead.
public protocol BackupService: Sendable {
    /// Backs up everything under ``projectRoot`` into a single encrypted
    /// bundle. Returns the URL of the bundle. ``destinationDirectory`` is
    /// the directory the bundle lands in; defaults to
    /// ``BackupSettings.defaultBackupsDirectory()``.
    func backup(
        projectRoot: URL,
        projectID: String,
        passphrase: String,
        destinationDirectory: URL?
    ) async throws -> URL

    /// Decrypts a previously-written bundle into ``destinationDirectory``,
    /// recreating the project's relative layout. Returns the destination
    /// directory (which the implementation creates if needed).
    func restore(
        bundleURL: URL,
        passphrase: String,
        into destinationDirectory: URL
    ) async throws -> URL

    /// Reads ``BackupPayload.createdAtISO8601`` and ``projectID`` from a
    /// bundle without decrypting the entries. The payload still has to be
    /// decrypted because we don't write either field outside the encrypted
    /// blob — but the operation is cheap once the passphrase is known.
    func metadata(
        bundleURL: URL,
        passphrase: String
    ) async throws -> (projectID: String, createdAt: String, entryCount: Int)
}

public final class DiskBackupService: BackupService, @unchecked Sendable {
    private let log = Logger(subsystem: "dev.kiln.core", category: "backup")

    public init() {}

    public func backup(
        projectRoot: URL,
        projectID: String,
        passphrase: String,
        destinationDirectory: URL? = nil
    ) async throws -> URL {
        try Self.guardPassphrase(passphrase)
        let fm = FileManager.default
        guard fm.fileExists(atPath: projectRoot.path) else {
            throw BackupError.sourceUnavailable(path: projectRoot.path)
        }

        let entries = try Self.collectEntries(under: projectRoot)
        let payload = BackupPayload(
            projectID: projectID,
            createdAtISO8601: Self.iso8601Now(),
            entries: entries
        )
        let plaintext = try JSONEncoder().encode(payload)

        var saltBytes = [UInt8](repeating: 0, count: BackupConstants.saltLength)
        let saltStatus = SecRandomCopyBytes(kSecRandomDefault, saltBytes.count, &saltBytes)
        guard saltStatus == errSecSuccess else {
            throw BackupError.decryptionFailed
        }
        let salt = Data(saltBytes)
        let key = try Self.deriveKey(passphrase: passphrase, salt: salt)
        let nonce = ChaChaPoly.Nonce()
        let sealed = try ChaChaPoly.seal(plaintext, using: key, nonce: nonce)

        var bundleData = Data()
        bundleData.append(contentsOf: BackupConstants.magic)
        bundleData.append(salt)
        bundleData.append(Data(nonce))
        bundleData.append(sealed.ciphertext)
        bundleData.append(sealed.tag)

        let dir = destinationDirectory ?? BackupSettings.defaultBackupsDirectory()
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            throw BackupError.destinationUnavailable(path: dir.path)
        }

        let stamp = Self.timestampForFilename()
        let url = dir.appendingPathComponent("\(projectID)-\(stamp).kilnbackup")
        try bundleData.write(to: url, options: .atomic)
        log.debug("backup written: \(url.path, privacy: .public) (\(bundleData.count) bytes)")
        return url
    }

    public func restore(
        bundleURL: URL,
        passphrase: String,
        into destinationDirectory: URL
    ) async throws -> URL {
        try Self.guardPassphrase(passphrase)
        let payload = try Self.decryptPayload(bundleURL: bundleURL, passphrase: passphrase)

        let fm = FileManager.default
        do {
            try fm.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        } catch {
            throw BackupError.destinationUnavailable(path: destinationDirectory.path)
        }

        for entry in payload.entries {
            // Verifier T3 (PR #16): reject any entry whose path is
            // absolute or contains a ``..`` segment. Self-DoS in the
            // single-user threat model, but a tampered/hand-crafted
            // bundle would otherwise land bytes outside the destination.
            try Self.assertSafeEntryPath(entry.path)
            guard let bytes = Data(base64Encoded: entry.contentsBase64) else {
                throw BackupError.payloadDecodeFailed(
                    message: "entry \(entry.path) had invalid base64"
                )
            }
            let target = destinationDirectory.appendingPathComponent(entry.path)
            let parent = target.deletingLastPathComponent()
            try fm.createDirectory(at: parent, withIntermediateDirectories: true)
            try bytes.write(to: target, options: .atomic)
        }
        return destinationDirectory
    }

    /// Reject absolute paths or any path containing a ``..`` component.
    /// Per-entry guard called before ``URL.appendingPathComponent`` so a
    /// malformed bundle can't escape ``destinationDirectory``.
    static func assertSafeEntryPath(_ path: String) throws {
        if path.hasPrefix("/") {
            throw BackupError.unsafeEntryPath(path: path)
        }
        for component in path.split(separator: "/") {
            if component == ".." {
                throw BackupError.unsafeEntryPath(path: path)
            }
        }
    }

    public func metadata(
        bundleURL: URL,
        passphrase: String
    ) async throws -> (projectID: String, createdAt: String, entryCount: Int) {
        try Self.guardPassphrase(passphrase)
        let payload = try Self.decryptPayload(bundleURL: bundleURL, passphrase: passphrase)
        return (
            projectID: payload.projectID,
            createdAt: payload.createdAtISO8601,
            entryCount: payload.entries.count
        )
    }

    // MARK: - Internals

    static func collectEntries(under root: URL) throws -> [BackupEntry] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return []
        }
        var entries: [BackupEntry] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let data = try Data(contentsOf: url)
            let relative = Self.relativePath(of: url, against: root)
            entries.append(
                BackupEntry(
                    path: relative,
                    contentsBase64: data.base64EncodedString(),
                    size: data.count
                )
            )
        }
        // Stable order across runs — the encrypted JSON payload is then
        // deterministic for the same input, which makes round-trip tests
        // possible to assert on byte-equality.
        entries.sort { $0.path < $1.path }
        return entries
    }

    private static func relativePath(of url: URL, against root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        if filePath.hasPrefix(rootPath + "/") {
            return String(filePath.dropFirst(rootPath.count + 1))
        }
        return url.lastPathComponent
    }

    static func decryptPayload(bundleURL: URL, passphrase: String) throws -> BackupPayload {
        let fm = FileManager.default
        guard fm.fileExists(atPath: bundleURL.path) else {
            throw BackupError.sourceUnavailable(path: bundleURL.path)
        }
        let data = try Data(contentsOf: bundleURL)
        guard data.count >= BackupConstants.headerLength else {
            throw BackupError.malformedHeader
        }
        let magicSlice = data[..<BackupConstants.magic.count]
        guard Array(magicSlice) == BackupConstants.magic else {
            throw BackupError.malformedHeader
        }
        let saltStart = BackupConstants.magic.count
        let saltEnd = saltStart + BackupConstants.saltLength
        let salt = data[saltStart..<saltEnd]
        let nonceStart = saltEnd
        let nonceEnd = nonceStart + BackupConstants.nonceLength
        let nonceData = data[nonceStart..<nonceEnd]
        let ciphertext = data[nonceEnd...]

        let key = try deriveKey(passphrase: passphrase, salt: Data(salt))
        let nonce: ChaChaPoly.Nonce
        do {
            nonce = try ChaChaPoly.Nonce(data: Data(nonceData))
        } catch {
            throw BackupError.malformedHeader
        }

        // SealedBox combined = ciphertext || 16-byte tag, but our layout is
        // separate header || ciphertext || tag. Reconstruct via init(nonce:ciphertext:tag:).
        guard ciphertext.count >= 16 else {
            throw BackupError.decryptionFailed
        }
        let tagStart = ciphertext.endIndex - 16
        let body = ciphertext[..<tagStart]
        let tag = ciphertext[tagStart...]

        let sealed: ChaChaPoly.SealedBox
        do {
            sealed = try ChaChaPoly.SealedBox(nonce: nonce, ciphertext: Data(body), tag: Data(tag))
        } catch {
            throw BackupError.malformedHeader
        }

        let plaintext: Data
        do {
            plaintext = try ChaChaPoly.open(sealed, using: key)
        } catch {
            throw BackupError.decryptionFailed
        }

        do {
            return try JSONDecoder().decode(BackupPayload.self, from: plaintext)
        } catch {
            throw BackupError.payloadDecodeFailed(message: error.localizedDescription)
        }
    }

    static func deriveKey(passphrase: String, salt: Data) throws -> SymmetricKey {
        // CryptoKit doesn't ship PBKDF2 directly. CommonCrypto does — wrapped
        // here as a synchronous call. Cost is ~100 ms on Apple Silicon at
        // 200k iterations.
        guard let passphraseData = passphrase.data(using: .utf8) else {
            throw BackupError.passphraseTooShort
        }
        var derived = [UInt8](repeating: 0, count: BackupConstants.keyLengthBytes)
        let status = passphraseData.withUnsafeBytes { passBuf -> Int32 in
            let passPtr = passBuf.bindMemory(to: Int8.self).baseAddress
            return salt.withUnsafeBytes { saltBuf -> Int32 in
                let saltPtr = saltBuf.bindMemory(to: UInt8.self).baseAddress
                return CCKeyDerivationPBKDF(
                    UInt32(kCCPBKDF2),
                    passPtr,
                    passphraseData.count,
                    saltPtr,
                    salt.count,
                    UInt32(kCCPRFHmacAlgSHA256),
                    UInt32(BackupConstants.pbkdf2Iterations),
                    &derived,
                    derived.count
                )
            }
        }
        guard status == kCCSuccess else {
            throw BackupError.decryptionFailed
        }
        return SymmetricKey(data: Data(derived))
    }

    private static func guardPassphrase(_ passphrase: String) throws {
        if passphrase.count < BackupSettings.minPassphraseLength {
            throw BackupError.passphraseTooShort
        }
    }

    static func iso8601Now() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: Date())
    }

    private static func timestampForFilename() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMddTHHmmss"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: Date())
    }
}

// MARK: - CommonCrypto bridging

import CommonCrypto
