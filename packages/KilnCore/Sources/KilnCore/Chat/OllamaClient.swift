import Foundation
import OSLog

/// HTTP client for the local Ollama daemon (``http://127.0.0.1:11434``).
///
/// The daemon's ``/api/chat`` endpoint streams newline-delimited JSON objects
/// in response; each object carries either ``message.content`` (one token /
/// chunk) or ``done: true`` with timing metadata. We transform those into
/// ``ChatStreamEvent`` so the UI can render tokens as they arrive and display
/// "N tok/s" once the stream closes.
///
/// This is an IPC module, not a feature module — it ships no prompts and no
/// system messages; callers build the ``ChatRequest`` and the daemon applies
/// whatever ``SYSTEM`` prompt is baked into the Modelfile that export wrote.
public protocol OllamaClient: Sendable {
    func streamChat(request: ChatRequest) -> AsyncThrowingStream<ChatStreamEvent, Error>
    func listModels() async throws -> [String]
}

public final class URLSessionOllamaClient: OllamaClient, @unchecked Sendable {
    /// Default daemon host — the Ollama installer binds to this by default. The
    /// string is constructed once and validated by the tests so the force
    /// parse stays out of every call site.
    public static let defaultBaseURLString = "http://127.0.0.1:11434"

    private let baseURL: URL
    private let session: URLSession
    private let log = Logger(subsystem: "dev.kiln.core", category: "ollama-chat")

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    /// Convenience initializer using the literal default URL we control
    /// at compile time. ``defaultBaseURLString`` is a constant; if its
    /// parse ever returns nil that's a programmer error in the constant
    /// itself, not a runtime condition we should disguise behind a
    /// silent ``/dev/null`` fallback (Saturday audit T2: the previous
    /// fallback would have surfaced as "cannot connect to /dev/null"
    /// instead of failing loudly at app start).
    public convenience init(session: URLSession = .shared) {
        guard let url = URL(string: Self.defaultBaseURLString) else {
            preconditionFailure(
                "OllamaClient.defaultBaseURLString failed to parse as URL: \(Self.defaultBaseURLString)"
            )
        }
        self.init(baseURL: url, session: session)
    }

    public func streamChat(request: ChatRequest) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let consumer = Task {
                do {
                    let urlRequest = try Self.buildChatURLRequest(baseURL: self.baseURL, chat: request)
                    let (bytes, response) = try await self.session.bytes(for: urlRequest)
                    try Self.validate(response: response, bodyHint: "")
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        guard !line.isEmpty else { continue }
                        do {
                            let event = try Self.decode(line: line)
                            continuation.yield(event)
                            if case .done = event {
                                break
                            }
                        } catch {
                            self.log.error("decode failed: \(error.localizedDescription, privacy: .public) line=\(line, privacy: .public)")
                        }
                    }
                    continuation.finish()
                } catch {
                    // URLSession surfaces connection refused as NSURLErrorDomain
                    // -1004 (cannot connect to host). Translate to a friendlier
                    // typed error so the UI can suggest starting `ollama serve`.
                    if let nsErr = error as NSError?,
                       nsErr.domain == NSURLErrorDomain,
                       nsErr.code == NSURLErrorCannotConnectToHost || nsErr.code == NSURLErrorCannotFindHost {
                        continuation.finish(throwing: ChatError.daemonUnreachable(host: self.baseURL.host ?? "127.0.0.1"))
                    } else {
                        continuation.finish(throwing: error)
                    }
                }
            }

            continuation.onTermination = { @Sendable _ in
                consumer.cancel()
            }
        }
    }

    public func listModels() async throws -> [String] {
        let url = baseURL.appendingPathComponent("api/tags")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let nsErr as NSError where nsErr.domain == NSURLErrorDomain &&
            (nsErr.code == NSURLErrorCannotConnectToHost || nsErr.code == NSURLErrorCannotFindHost) {
            throw ChatError.daemonUnreachable(host: baseURL.host ?? "127.0.0.1")
        }
        try Self.validate(response: response, bodyHint: String(data: data, encoding: .utf8) ?? "")

        struct TagsResponse: Decodable {
            let models: [Model]
            struct Model: Decodable { let name: String }
        }
        let decoded = try JSONDecoder().decode(TagsResponse.self, from: data)
        return decoded.models.map(\.name)
    }

    // MARK: - Helpers

    static func buildChatURLRequest(baseURL: URL, chat: ChatRequest) throws -> URLRequest {
        let endpoint = baseURL.appendingPathComponent("api/chat")
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ChatBody(from: chat)
        req.httpBody = try JSONEncoder().encode(body)
        return req
    }

    static func validate(response: URLResponse, bodyHint: String) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw ChatError.httpStatus(http.statusCode, body: bodyHint)
        }
    }

    static func decode(line: String) throws -> ChatStreamEvent {
        guard let data = line.data(using: .utf8) else {
            throw ChatError.decodingFailed(line: line, underlying: "not UTF-8")
        }
        let frame: StreamFrame
        do {
            frame = try JSONDecoder().decode(StreamFrame.self, from: data)
        } catch {
            throw ChatError.decodingFailed(line: line, underlying: error.localizedDescription)
        }
        if frame.done == true {
            return .done(
                totalTokens: frame.evalCount ?? 0,
                evalDurationNanos: frame.evalDuration ?? 0
            )
        }
        if let content = frame.message?.content {
            return .token(content)
        }
        throw ChatError.decodingFailed(
            line: line,
            underlying: "frame has neither message.content nor done=true"
        )
    }

    // MARK: - Wire shapes

    /// Request body matching Ollama's ``/api/chat`` spec. ``stream`` is always
    /// true — we stream tokens up to the UI.
    private struct ChatBody: Encodable {
        let model: String
        let messages: [Turn]
        let stream: Bool
        let options: Options?

        init(from request: ChatRequest) {
            self.model = request.model
            self.messages = request.messages.map {
                Turn(role: $0.role.rawValue, content: $0.content)
            }
            self.stream = true
            // Only emit an options object when the caller supplied at least
            // one override; otherwise the daemon falls back to the Modelfile
            // PARAMETERs we baked in during export.
            if request.temperature != nil || request.topP != nil || request.seed != nil {
                self.options = Options(
                    temperature: request.temperature,
                    topP: request.topP,
                    seed: request.seed
                )
            } else {
                self.options = nil
            }
        }

        struct Turn: Encodable {
            let role: String
            let content: String
        }

        struct Options: Encodable {
            let temperature: Double?
            let topP: Double?
            let seed: UInt64?

            enum CodingKeys: String, CodingKey {
                case temperature
                case topP = "top_p"
                case seed
            }
        }
    }

    private struct StreamFrame: Decodable {
        let message: Message?
        let done: Bool?
        let evalCount: Int?
        let evalDuration: UInt64?

        struct Message: Decodable {
            let role: String?
            let content: String?
        }

        enum CodingKeys: String, CodingKey {
            case message, done
            case evalCount = "eval_count"
            case evalDuration = "eval_duration"
        }
    }
}
