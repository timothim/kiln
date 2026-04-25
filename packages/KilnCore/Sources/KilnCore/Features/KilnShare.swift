import Foundation

/// One-click export of a trained voice as a self-contained bundle
/// (`.kiln` = zipped fused adapter + Modelfile + signature card +
/// manifest). Sharing is purely file-based; no cloud upload happens
/// here. Local encrypted backup is a separate feature — see
/// ``Backup/BackupService.swift``. Cloud upload (iCloud Drive / S3)
/// remains out of scope per CLAUDE.md.
public enum KilnShare {
    /// True once the M8 `ShareExporter` wiring landed — lets feature
    /// flags / tests short-circuit the old stub path.
    public static let isImplemented = true

    public struct Bundle: Sendable, Equatable {
        public let bundleURL: URL
        public let sizeBytes: Int
        public let sha256: String

        public init(bundleURL: URL, sizeBytes: Int, sha256: String) {
            self.bundleURL = bundleURL
            self.sizeBytes = sizeBytes
            self.sha256 = sha256
        }
    }

    public enum ShareError: Error, Equatable {
        case notImplemented
        case voiceNotFused
    }

    /// Rich export path — the UI assembles a `ShareManifest` from the user's
    /// include-options and current voice artifacts, then calls this.
    public static func export(
        manifest: ShareManifest,
        to destinationURL: URL,
        using exporter: ShareExporter = ShareExporter()
    ) async throws -> Bundle {
        try await exporter.export(manifest, to: destinationURL)
    }

    /// Legacy signature kept for callers that only have a voice name — not
    /// wired up for production; `import` is still pending the post-M8
    /// ingest path. Throws `voiceNotFused` to make the gap visible in UI.
    public static func export(voiceName _: String, to _: URL) async throws -> Bundle {
        throw ShareError.voiceNotFused
    }

    public static func `import`(bundleAt _: URL) async throws -> String {
        throw ShareError.notImplemented
    }
}
