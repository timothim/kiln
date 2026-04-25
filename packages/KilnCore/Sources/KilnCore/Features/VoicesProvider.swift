import Foundation
import OSLog

/// Source of truth for the user's saved voices (fused adapters served by
/// Ollama). Abstracted so the UI's `VoicesModel` doesn't care whether the
/// data comes from `ollama list`, disk metadata, or a future REST client.
///
/// M8 ships `DiskVoicesProvider` — reads voice metadata JSONs under
/// `~/Library/Application Support/Kiln/Voices/`. The Ollama-backed provider
/// (GET /api/tags against localhost:11434) is blocked on coordination with
/// LEAD's M7 chat work — see `docs/architecture/ollama-client-proposal.md`.
public protocol VoicesProvider: Sendable {
    func list() async throws -> [KilnVoices.Voice]
    func activate(_ id: UUID) async throws
}

/// On-disk metadata shape. One JSON per saved voice under
/// `~/Library/Application Support/Kiln/Voices/<uuid>.json`. Post-training
/// pipelines (M6 fuse/export) will write these; M8 only reads.
public struct VoiceMetadata: Sendable, Codable, Equatable {
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

    public var voice: KilnVoices.Voice {
        KilnVoices.Voice(id: id, name: name, ollamaTag: ollamaTag, createdAt: createdAt)
    }
}

public enum VoicesProviderError: Error, Equatable {
    case voiceNotFound(UUID)
    case decodingFailed(String)
    case notImplemented
}

/// M8 stub: scans `~/Library/Application Support/Kiln/Voices/*.json` and
/// returns sorted-by-recency voices. Returns an empty array if the directory
/// is absent — that's the "no voices saved yet" first-run state, not an error.
///
/// `activate(_:)` is a placeholder that records the active voice to
/// `.../Voices/active.json`. Real activation (loading the adapter into
/// Ollama) lands once `OllamaClient` exists.
public actor DiskVoicesProvider: VoicesProvider {
    private let log = Logger(subsystem: "app.kiln.core", category: "DiskVoicesProvider")
    private let voicesDir: URL

    public init(voicesDir: URL? = nil) {
        self.voicesDir = voicesDir ?? Self.defaultVoicesDir()
    }

    public func list() async throws -> [KilnVoices.Voice] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: voicesDir.path) else {
            return []
        }
        let contents = try fm.contentsOfDirectory(
            at: voicesDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        let jsons = contents.filter { $0.pathExtension == "json" && $0.lastPathComponent != "active.json" }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var voices: [KilnVoices.Voice] = []
        for url in jsons {
            do {
                let data = try Data(contentsOf: url)
                let meta = try decoder.decode(VoiceMetadata.self, from: data)
                voices.append(meta.voice)
            } catch {
                log.warning("skipping malformed voice metadata at \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return voices.sorted { $0.createdAt > $1.createdAt }
    }

    public func activate(_ id: UUID) async throws {
        let all = try await list()
        guard all.contains(where: { $0.id == id }) else {
            throw VoicesProviderError.voiceNotFound(id)
        }
        let fm = FileManager.default
        try fm.createDirectory(at: voicesDir, withIntermediateDirectories: true)
        let activeURL = voicesDir.appendingPathComponent("active.json", isDirectory: false)
        let payload = try JSONEncoder().encode(["id": id.uuidString])
        try payload.write(to: activeURL, options: [.atomic])
    }

    /// Expose the storage directory so test harnesses can seed fixtures.
    public var directory: URL { voicesDir }

    private static func defaultVoicesDir() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Kiln", isDirectory: true)
            .appendingPathComponent("Voices", isDirectory: true)
    }
}

/// In-memory provider for tests and previews. Not for shipping.
public actor InMemoryVoicesProvider: VoicesProvider {
    private var voices: [KilnVoices.Voice]
    private var activeID: UUID?
    private let throwsOnList: Bool

    public init(seed: [KilnVoices.Voice] = [], throwsOnList: Bool = false) {
        self.voices = seed
        self.throwsOnList = throwsOnList
    }

    public func list() async throws -> [KilnVoices.Voice] {
        if throwsOnList { throw VoicesProviderError.notImplemented }
        return voices
    }

    public func activate(_ id: UUID) async throws {
        guard voices.contains(where: { $0.id == id }) else {
            throw VoicesProviderError.voiceNotFound(id)
        }
        activeID = id
    }

    public func currentActiveID() -> UUID? { activeID }
}
