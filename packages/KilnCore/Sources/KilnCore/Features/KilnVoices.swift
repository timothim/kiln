import Foundation

/// Library of user-saved "voices" — each voice is a named fused adapter
/// the user can switch between. Implemented in M8 via ``VoicesProvider``
/// (see `apps/Kiln/Sources/Models/VoicesModel.swift`). The legacy
/// ``KilnVoices.list`` / ``activate`` stubs remain as dead code until they
/// are removed in a follow-up sweep — the live path goes through the
/// provider, not these enum methods.
public enum KilnVoices {
    public static let isImplemented = true

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
