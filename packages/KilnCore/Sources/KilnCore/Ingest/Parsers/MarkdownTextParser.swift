import Foundation

public struct MarkdownTextParser: CorpusParser {
    public init() {}

    public func canParse(url: URL, probe: Data?) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "md" || ext == "markdown" || ext == "txt"
    }

    public func parse(url: URL, config: IngestConfig) throws -> [Chunk] {
        let raw = try ParserUtilities.readString(url)
        let stripped = config.stripFrontmatter
            ? TextNormalization.stripYAMLFrontmatter(raw)
            : raw

        let (title, body) = extractTitle(stripped)
        let cleaned = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return [] }

        let prompt: String
        if let title = title, !title.isEmpty {
            prompt = "Write something in your voice about: \(title)"
        } else {
            prompt = "Continue in your own voice."
        }
        return [Chunk(
            sourcePath: url.path,
            kind: .text,
            userPrompt: prompt,
            assistantText: cleaned
        )]
    }

    /// Returns (title, remainder). If the first non-blank line is an H1 (`# ...`),
    /// its text is returned as `title` and stripped from `body`.
    func extractTitle(_ text: String) -> (String?, String) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var firstNonBlank: Int?
        for (i, line) in lines.enumerated() {
            if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                firstNonBlank = i
                break
            }
        }
        guard let start = firstNonBlank else { return (nil, text) }
        let line = lines[start].trimmingCharacters(in: .whitespaces)
        guard line.hasPrefix("# ") else { return (nil, text) }
        let title = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        let rest = lines.dropFirst(start + 1).joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (title, rest)
    }
}
