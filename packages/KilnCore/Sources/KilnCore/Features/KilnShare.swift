import Foundation

/// One-click export of a trained voice as a self-contained bundle
/// (`.kiln` = zipped fused adapter + Modelfile + signature card +
/// manifest). Sharing is purely file-based; no cloud upload happens
/// here. Cloud backup (opt-in) is a separate feature — see
/// `CloudBackup.swift`.
public enum KilnShare {
    public static let isImplemented = false

    public struct Bundle: Sendable, Equatable {
        public let bundleURL: URL
        public let sizeBytes: Int
        public let sha256: String
    }

    public enum ShareError: Error, Equatable {
        case notImplemented
        case voiceNotFused
    }

    public static func export(voiceName _: String, to _: URL) async throws -> Bundle {
        throw ShareError.notImplemented
    }

    public static func `import`(bundleAt _: URL) async throws -> String {
        throw ShareError.notImplemented
    }
}
