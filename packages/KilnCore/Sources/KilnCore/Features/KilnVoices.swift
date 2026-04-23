import Foundation

/// Library of user-saved "voices" — each voice is a named fused adapter
/// the user can switch between. Lands post-M6 once fuse-export is stable.
public enum KilnVoices {
    public static let isImplemented = false

    public struct Voice: Sendable, Equatable, Identifiable {
        public let id: UUID
        public let name: String
        public let ollamaTag: String
        public let createdAt: Date

        public init(id: UUID, name: String, ollamaTag: String, createdAt: Date) {
            self.id = id
            self.name = name
            self.ollamaTag = ollamaTag
            self.createdAt = createdAt
        }
    }

    public enum VoicesError: Error, Equatable {
        case notImplemented
    }

    public static func list() async throws -> [Voice] {
        throw VoicesError.notImplemented
    }

    public static func activate(_: Voice.ID) async throws {
        throw VoicesError.notImplemented
    }
}
