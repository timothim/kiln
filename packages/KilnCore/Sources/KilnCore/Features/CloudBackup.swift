import Foundation

/// Opt-in cloud backup for `.kiln` bundles. Strictly out of scope for
/// the hackathon demo per `CLAUDE.md` ("no cloud sync, no telemetry");
/// scaffolded here as a placeholder so the UI can wire the toggle at
/// compile time and the surface stays explicitly disabled. Enabling
/// this feature will require a dedicated `DECISIONS.md` entry spelling
/// out the provider, on-device encryption, consent flow, and key
/// custody model. Until then every entry point throws `.disabledByScope`.
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
