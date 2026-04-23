import Foundation

/// Hand-rolled RFC-822 / mbox parser with just enough MIME to recover the
/// body of personal email exports. Scope is deliberately narrow: we want
/// plain-text messages the user themselves authored. Multipart messages
/// yield the first `text/plain` part; base64 bodies are skipped. No
/// third-party MIME dependency — the stdlib is enough for the shapes we
/// expect out of `osascript` exports and `.mbox` dumps.
public struct EmailParser: CorpusParser {
    public init() {}

    public func canParse(url: URL, probe: Data?) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "eml" || ext == "mbox"
    }

    public func parse(url: URL, config: IngestConfig) throws -> [Chunk] {
        let raw: String
        do {
            raw = try String(contentsOf: url, encoding: .utf8)
        } catch {
            if let data = try? Data(contentsOf: url),
               let s = String(data: data, encoding: .isoLatin1) {
                raw = s
            } else {
                throw IngestError.parserFailed(path: url, message: "unable to read as UTF-8 or Latin-1")
            }
        }

        let ext = url.pathExtension.lowercased()
        let messages: [RawMessage]
        if ext == "mbox" {
            messages = splitMbox(raw)
        } else {
            messages = [RawMessage(text: raw)]
        }

        let allowedSenders = Set(config.userEmails.map { $0.lowercased() })
        var chunks: [Chunk] = []
        for message in messages {
            guard let parsed = parseMessage(message.text) else { continue }
            guard let sender = normalizedSender(parsed.from) else { continue }
            guard allowedSenders.contains(sender) else { continue }
            let subject = parsed.subject.trimmingCharacters(in: .whitespacesAndNewlines)
            let body = parsed.body.trimmingCharacters(in: .whitespacesAndNewlines)
            if body.isEmpty { continue }
            let prompt: String
            if subject.isEmpty {
                prompt = "From: \(sender)"
            } else {
                prompt = "Subject: \(subject)\nFrom: \(sender)"
            }
            chunks.append(Chunk(
                sourcePath: url.path,
                kind: .chat,
                userPrompt: prompt,
                assistantText: body
            ))
        }
        return chunks
    }

    // MARK: - mbox splitting

    private struct RawMessage {
        let text: String
    }

    /// Splits an mbox file on `From ` boundary lines (RFC-4155 "From " must
    /// start at column 0). Each resulting message *excludes* the boundary
    /// line itself.
    private func splitMbox(_ raw: String) -> [RawMessage] {
        var messages: [RawMessage] = []
        var current = ""
        var sawFirstBoundary = false
        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("From ") {
                if sawFirstBoundary, !current.isEmpty {
                    messages.append(RawMessage(text: current))
                }
                current = ""
                sawFirstBoundary = true
                continue
            }
            if sawFirstBoundary {
                if !current.isEmpty { current.append("\n") }
                current.append(String(line))
            }
        }
        if sawFirstBoundary, !current.isEmpty {
            messages.append(RawMessage(text: current))
        }
        return messages
    }

    // MARK: - RFC-822 header + body

    private struct ParsedMessage {
        var subject: String
        var from: String
        var body: String
    }

    private func parseMessage(_ text: String) -> ParsedMessage? {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        guard let split = normalized.range(of: "\n\n") else {
            return nil
        }
        let headerBlock = String(normalized[..<split.lowerBound])
        let bodyBlock = String(normalized[split.upperBound...])
        let headers = parseHeaders(headerBlock)
        let subject = headers["subject"] ?? ""
        let from = headers["from"] ?? ""
        let encoding = headers["content-transfer-encoding"]?.lowercased() ?? "7bit"
        let contentType = headers["content-type"]?.lowercased() ?? "text/plain"

        let decoded: String
        if contentType.hasPrefix("multipart/") {
            decoded = extractFirstTextPlainPart(
                body: bodyBlock,
                contentType: contentType
            )
        } else if encoding == "quoted-printable" {
            decoded = decodeQuotedPrintable(bodyBlock)
        } else if encoding == "base64" {
            return nil
        } else {
            decoded = bodyBlock
        }
        return ParsedMessage(subject: subject, from: from, body: decoded)
    }

    private func parseHeaders(_ headerBlock: String) -> [String: String] {
        var headers: [String: String] = [:]
        var currentKey: String?
        var currentValue = ""
        for line in headerBlock.split(separator: "\n", omittingEmptySubsequences: false) {
            let str = String(line)
            if str.hasPrefix(" ") || str.hasPrefix("\t") {
                currentValue += " " + str.trimmingCharacters(in: .whitespaces)
                continue
            }
            if let key = currentKey {
                headers[key] = currentValue.trimmingCharacters(in: .whitespaces)
            }
            if let colon = str.firstIndex(of: ":") {
                currentKey = String(str[..<colon]).lowercased()
                currentValue = String(str[str.index(after: colon)...])
            } else {
                currentKey = nil
                currentValue = ""
            }
        }
        if let key = currentKey {
            headers[key] = currentValue.trimmingCharacters(in: .whitespaces)
        }
        return headers
    }

    // MARK: - multipart

    private func extractFirstTextPlainPart(
        body: String,
        contentType: String
    ) -> String {
        guard let boundary = boundaryFromContentType(contentType) else {
            return body
        }
        let delimiter = "--\(boundary)"
        let parts = body.components(separatedBy: delimiter)
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed == "--" { continue }
            guard let split = part.range(of: "\n\n") ?? part.range(of: "\r\n\r\n") else { continue }
            let partHeaders = parseHeaders(String(part[..<split.lowerBound]))
            let partBody = String(part[split.upperBound...])
            let partType = partHeaders["content-type"]?.lowercased() ?? "text/plain"
            let partEncoding = partHeaders["content-transfer-encoding"]?.lowercased() ?? "7bit"
            if !partType.hasPrefix("text/plain") { continue }
            if partEncoding == "quoted-printable" {
                return decodeQuotedPrintable(partBody)
            }
            if partEncoding == "base64" { continue }
            return partBody
        }
        return ""
    }

    private func boundaryFromContentType(_ contentType: String) -> String? {
        guard let range = contentType.range(of: "boundary=") else { return nil }
        var tail = String(contentType[range.upperBound...])
        if tail.hasPrefix("\"") {
            tail.removeFirst()
            if let end = tail.firstIndex(of: "\"") {
                return String(tail[..<end])
            }
            return nil
        }
        if let end = tail.firstIndex(where: { $0 == ";" || $0 == " " }) {
            return String(tail[..<end])
        }
        return tail
    }

    // MARK: - quoted-printable

    private func decodeQuotedPrintable(_ text: String) -> String {
        let collapsed = text
            .replacingOccurrences(of: "=\r\n", with: "")
            .replacingOccurrences(of: "=\n", with: "")
        var out: [UInt8] = []
        let scalars = Array(collapsed.unicodeScalars)
        var i = 0
        while i < scalars.count {
            let c = scalars[i]
            if c == "=" && i + 2 < scalars.count {
                let h1 = scalars[i + 1]
                let h2 = scalars[i + 2]
                if let byte = hexPair(h1, h2) {
                    out.append(byte)
                    i += 3
                    continue
                }
            }
            if c.isASCII {
                out.append(UInt8(c.value))
                i += 1
            } else {
                for byte in String(c).utf8 { out.append(byte) }
                i += 1
            }
        }
        return String(decoding: out, as: UTF8.self)
    }

    private func hexPair(_ a: Unicode.Scalar, _ b: Unicode.Scalar) -> UInt8? {
        guard let hi = hexDigit(a), let lo = hexDigit(b) else { return nil }
        return UInt8(hi * 16 + lo)
    }

    private func hexDigit(_ s: Unicode.Scalar) -> Int? {
        switch s {
        case "0"..."9": return Int(s.value - Unicode.Scalar("0").value)
        case "A"..."F": return Int(s.value - Unicode.Scalar("A").value) + 10
        case "a"..."f": return Int(s.value - Unicode.Scalar("a").value) + 10
        default: return nil
        }
    }

    // MARK: - sender normalization

    /// Extracts a bare email from a `From:` header and lowercases it. Accepts
    /// `"Display Name" <addr@host>`, `Display Name <addr@host>`, `<addr@host>`,
    /// or the bare form. Returns nil if nothing address-shaped is present.
    private func normalizedSender(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if let lt = trimmed.firstIndex(of: "<"),
           let gt = trimmed.lastIndex(of: ">"),
           lt < gt {
            let inside = trimmed[trimmed.index(after: lt)..<gt]
            return String(inside).lowercased()
        }
        if trimmed.contains("@") {
            return trimmed.lowercased()
        }
        return nil
    }
}
