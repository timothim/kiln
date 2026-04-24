import Foundation

/// One turn in a chat conversation. Roles match Ollama's wire format.
public enum ChatRole: String, Sendable, Hashable, Codable {
    case system
    case user
    case assistant
}

public struct ChatMessage: Sendable, Hashable, Identifiable, Codable {
    public let id: UUID
    public let role: ChatRole
    public var content: String
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        role: ChatRole,
        content: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

/// Request we ship to the Ollama daemon. Mirrors the ``/api/chat`` body: we
/// keep only the fields the UI actually drives. Everything else (`template`,
/// `system`, stop tokens) is baked into the Modelfile that the export stage
/// wrote.
public struct ChatRequest: Sendable, Hashable {
    public let model: String
    public let messages: [ChatMessage]
    public let temperature: Double?
    public let topP: Double?
    public let seed: UInt64?

    public init(
        model: String,
        messages: [ChatMessage],
        temperature: Double? = nil,
        topP: Double? = nil,
        seed: UInt64? = nil
    ) {
        self.model = model
        self.messages = messages
        self.temperature = temperature
        self.topP = topP
        self.seed = seed
    }
}

/// One unit the ``OllamaClient`` hands up to the UI as the daemon streams
/// bytes. The final ``done`` carries total counts so the UI can show
/// "42 tokens / 18 tok/s" once generation stops.
public enum ChatStreamEvent: Sendable, Hashable {
    case token(String)
    case done(totalTokens: Int, evalDurationNanos: UInt64)
}

public enum ChatError: Error, Sendable, Equatable {
    case daemonUnreachable(host: String)
    case httpStatus(Int, body: String)
    case decodingFailed(line: String, underlying: String)
    case missingModel(String)
}
