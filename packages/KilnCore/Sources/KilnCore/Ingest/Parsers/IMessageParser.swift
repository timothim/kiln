import Foundation

public struct IMessageParser: CorpusParser {
    public init() {}

    private struct Envelope: Decodable {
        let schema: String?
        let exported_at: String?
        let threads: [Thread]
    }

    private struct Thread: Decodable {
        let handle: String?
        let display_name: String?
        let messages: [Message]
    }

    private struct Message: Decodable {
        let ts: String?
        let from: String
        let text: String
    }

    public func canParse(url: URL, probe: Data?) -> Bool {
        guard url.pathExtension.lowercased() == "json" else { return false }
        guard let data = probe ?? (try? Data(contentsOf: url)) else { return false }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        if let schema = root["schema"] as? String, schema.hasPrefix("kiln.imessage") { return true }
        return root["threads"] is [[String: Any]]
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
            throw IngestError.parserFailed(path: url, message: "invalid iMessage JSON")
        }

        let anchor = parseISO8601(envelope.exported_at) ?? Date()
        let cutoff = anchor.addingTimeInterval(
            -Double(config.iMessageMaxAgeDays) * 86_400
        )

        var chunks: [Chunk] = []
        for thread in envelope.threads {
            let kept = thread.messages.filter { msg in
                guard let ts = msg.ts, let d = parseISO8601(ts) else { return true }
                return d >= cutoff
            }
            for i in kept.indices where kept[i].from == "me" {
                guard i > 0, kept[i - 1].from != "me" else { continue }
                let prompt = kept[i - 1].text.trimmingCharacters(in: .whitespacesAndNewlines)
                let answer = kept[i].text.trimmingCharacters(in: .whitespacesAndNewlines)
                if prompt.isEmpty || answer.isEmpty { continue }
                chunks.append(Chunk(
                    sourcePath: url.path,
                    kind: .chat,
                    userPrompt: prompt,
                    assistantText: answer
                ))
            }
        }
        return chunks
    }

    private func parseISO8601(_ s: String?) -> Date? {
        guard let s = s else { return nil }
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        if let d = fmt.date(from: s) { return d }
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fmt.date(from: s)
    }
}
