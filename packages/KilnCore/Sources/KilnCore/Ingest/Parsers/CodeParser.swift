import Foundation

public struct CodeParser: CorpusParser {
    public init() {}

    public func canParse(url: URL, probe: Data?) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["py", "swift", "ts", "js", "rs", "go"].contains(ext)
    }

    public func parse(url: URL, config: IngestConfig) throws -> [Chunk] {
        let source = try ParserUtilities.readString(url)
        let ext = url.pathExtension.lowercased()
        let language = languageName(for: ext)

        let docs: [(signature: String, body: String)]
        switch ext {
        case "py":
            docs = extractPythonDocs(source)
        case "swift":
            docs = extractTripleSlashDocs(source)
        case "ts", "js":
            docs = extractJSDocs(source)
        case "rs", "go":
            docs = extractTripleSlashDocs(source)
        default:
            docs = []
        }

        return docs.compactMap { entry -> Chunk? in
            let body = entry.body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { return nil }
            let prompt: String
            if entry.signature.isEmpty {
                prompt = "Write a module-level documentation comment for a \(language) file."
            } else {
                prompt = "Write a documentation comment for this \(language) code:\n\(entry.signature)"
            }
            return Chunk(
                sourcePath: url.path,
                kind: .code,
                userPrompt: prompt,
                assistantText: body
            )
        }
    }

    // MARK: - Language dispatch

    private func languageName(for ext: String) -> String {
        switch ext {
        case "py": return "Python"
        case "swift": return "Swift"
        case "ts": return "TypeScript"
        case "js": return "JavaScript"
        case "rs": return "Rust"
        case "go": return "Go"
        default: return ext
        }
    }

    // MARK: - Python

    private func extractPythonDocs(_ source: String) -> [(signature: String, body: String)] {
        var results: [(String, String)] = []
        let chars = Array(source)
        var i = 0

        // Module docstring: skip shebang + blank lines, then look for a triple quote at col 0.
        var moduleStart = 0
        while moduleStart < chars.count {
            let lineEnd = nextLineEnd(in: chars, from: moduleStart)
            let line = String(chars[moduleStart..<lineEnd]).trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#!") || line.isEmpty {
                moduleStart = lineEnd + 1
                continue
            }
            break
        }
        if moduleStart < chars.count {
            if let (body, end) = readTripleQuoted(chars, from: moduleStart) {
                results.append(("", body))
                i = end
            }
        }

        // Function/class docstrings.
        let decl = try? NSRegularExpression(
            pattern: #"^([ \t]*)(def|class)\s+\w+[^\n]*:[ \t]*$"#,
            options: [.anchorsMatchLines]
        )
        guard let decl else { return results }
        let ns = source as NSString
        let all = decl.matches(in: source, range: NSRange(location: 0, length: ns.length))
        for m in all {
            let signatureRange = m.range(at: 0)
            let afterDecl = signatureRange.location + signatureRange.length
            if afterDecl >= chars.count { continue }
            var cursor = afterDecl
            while cursor < chars.count, chars[cursor] == "\n" { cursor += 1 }
            while cursor < chars.count, chars[cursor] == " " || chars[cursor] == "\t" { cursor += 1 }
            if let (body, _) = readTripleQuoted(chars, from: cursor) {
                let sig = ns.substring(with: signatureRange)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                results.append((sig, body))
            }
        }
        _ = i
        return results
    }

    /// Reads a `"""..."""` or `'''...'''` block starting at `from`. Returns body (unindented
    /// loosely) and index after the closing quote. Returns nil if not a triple-quoted literal.
    private func readTripleQuoted(_ chars: [Character], from: Int) -> (String, Int)? {
        guard from + 2 < chars.count else { return nil }
        let q = chars[from]
        guard (q == "\"" || q == "'"), chars[from + 1] == q, chars[from + 2] == q else { return nil }
        let start = from + 3
        var i = start
        while i + 2 < chars.count {
            if chars[i] == q, chars[i + 1] == q, chars[i + 2] == q {
                let body = String(chars[start..<i])
                return (dedent(body), i + 3)
            }
            i += 1
        }
        return nil
    }

    /// Remove leading whitespace shared across non-empty lines.
    private func dedent(_ s: String) -> String {
        let lines = s.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let indents = lines.compactMap { line -> Int? in
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            var n = 0
            for c in line { if c == " " { n += 1 } else if c == "\t" { n += 4 } else { break } }
            return n
        }
        guard let minIndent = indents.min(), minIndent > 0 else {
            return s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let out = lines.map { line -> String in
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return "" }
            var dropped = 0
            var result = ""
            for c in line {
                if dropped < minIndent, c == " " { dropped += 1; continue }
                if dropped < minIndent, c == "\t" { dropped += 4; continue }
                result.append(c)
            }
            return result
        }
        return out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func nextLineEnd(in chars: [Character], from: Int) -> Int {
        var i = from
        while i < chars.count, chars[i] != "\n" { i += 1 }
        return i
    }

    // MARK: - Swift / Rust / Go triple-slash

    private func extractTripleSlashDocs(_ source: String) -> [(signature: String, body: String)] {
        var results: [(String, String)] = []
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var block: [String] = []
        var blockStart: Int?
        var i = 0
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("///") {
                if blockStart == nil { blockStart = i }
                var clean = String(trimmed.dropFirst(3))
                if clean.hasPrefix(" ") { clean.removeFirst() }
                block.append(clean)
                i += 1
                continue
            }
            if !block.isEmpty {
                var j = i
                while j < lines.count, lines[j].trimmingCharacters(in: .whitespaces).isEmpty { j += 1 }
                if j < lines.count, isDeclaration(lines[j]) {
                    let signature = lines[j].trimmingCharacters(in: .whitespacesAndNewlines)
                    let body = block.joined(separator: "\n")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    results.append((signature, body))
                }
                block = []
                blockStart = nil
            }
            i += 1
        }
        return results
    }

    private func isDeclaration(_ line: String) -> Bool {
        let keywords = ["func ", "struct ", "class ", "enum ", "protocol ",
                        "extension ", "actor ", "var ", "let ", "typealias ",
                        "fn ", "pub fn ", "pub struct ", "pub enum ",
                        "func(", "type "]
        let stripped = line.trimmingCharacters(in: .whitespaces)
        for kw in keywords where stripped.contains(kw) {
            return true
        }
        return false
    }

    // MARK: - TypeScript / JavaScript JSDoc

    private func extractJSDocs(_ source: String) -> [(signature: String, body: String)] {
        var results: [(String, String)] = []
        let pattern = #"/\*\*([\s\S]*?)\*/[ \t]*\r?\n[ \t]*([^\n]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = source as NSString
        let matches = regex.matches(in: source, range: NSRange(location: 0, length: ns.length))
        for m in matches {
            guard m.numberOfRanges >= 3 else { continue }
            let raw = ns.substring(with: m.range(at: 1))
            let sig = ns.substring(with: m.range(at: 2))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let body = cleanJSDoc(raw)
            if !body.isEmpty {
                results.append((sig, body))
            }
        }
        return results
    }

    private func cleanJSDoc(_ raw: String) -> String {
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: false)
        let cleaned: [String] = lines.map { line in
            var s = line.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("*") { s.removeFirst() }
            if s.hasPrefix(" ") { s.removeFirst() }
            return s
        }
        return cleaned.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
