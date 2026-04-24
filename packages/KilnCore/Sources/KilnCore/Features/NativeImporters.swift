import Foundation

/// macOS-native importers — Messages (chat.db), Notes (AppleScript),
/// Mail (mbox), Obsidian (wikilinks/frontmatter). Each importer emits
/// the same `IngestChunk` type the drop-folder pipeline produces, so
/// downstream stages (dedup → quality filter → train) are unchanged.
/// Behaviour is specified in `.claude/skills/macos-data-sources/SKILL.md`.
public enum NativeImporters {
    public static let isImplemented = false

    public enum Source: String, Sendable, CaseIterable {
        case messages
        case notes
        case mail
        case obsidian
    }

    public struct ImportProgress: Sendable, Equatable {
        public let source: Source
        public let itemsSeen: Int
        public let itemsAccepted: Int
    }

    public enum ImporterError: Error, Equatable {
        case notImplemented
        case missingPermission(Source)
    }

    public static func importFrom(_: Source, progress _: @Sendable (ImportProgress) -> Void) async throws {
        throw ImporterError.notImplemented
    }
}
