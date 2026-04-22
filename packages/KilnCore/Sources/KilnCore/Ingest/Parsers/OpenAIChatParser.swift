import Foundation

public struct OpenAIChatParser: CorpusParser {
    public init() {}

    private struct Envelope: Decodable {
        let messages: [Message]
    }

    private struct Message: Decodable {
        let role: String
        let content: String
    }

    public func canParse(url: URL, probe: Data?) -> Bool {
        guard url.pathExtension.lowercased() == "json" else { return false }
        guard let data = probe ?? (try? Data(contentsOf: url)) else { return false }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        // iMessage claim wins — delegate to that parser.
        if root["threads"] != nil { return false }
        if let schema = root["schema"] as? String, schema.hasPrefix("kiln.imessage") { return false }
        guard let messages = root["messages"] as? [[String: Any]], !messages.isEmpty else { return false }
        return messages.allSatisfy { $0["role"] is String && $0["content"] is String }
    }

    public func parse(url: URL, config: IngestConfig) throws -> [Chunk] {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw IngestError.parserFailed(path: url, message: "unreadable")
        }
        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: data)
        } catch {
            throw IngestError.parserFailed(path: url, message: "invalid OpenAI chat JSON")
        }

        var chunks: [Chunk] = []
        let messages = envelope.messages
        for i in messages.indices where messages[i].role == "user" {
            guard i > 0, messages[i - 1].role == "assistant" else { continue }
            let prompt = messages[i - 1].content
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let answer = messages[i].content
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if prompt.isEmpty || answer.isEmpty { continue }
            chunks.append(Chunk(
                sourcePath: url.path,
                kind: .chat,
                userPrompt: prompt,
                assistantText: answer
            ))
        }
        return chunks
    }
}
