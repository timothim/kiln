import Foundation
import CryptoKit

public enum TextNormalization {
    /// Canonical form used as the key for exact dedup. Collapses whitespace runs,
    /// lowercases, trims, and applies NFC so that visually identical strings hash identically.
    public static func canonical(_ text: String) -> String {
        let folded = text.lowercased().precomposedStringWithCanonicalMapping
        var out = String()
        out.reserveCapacity(folded.count)
        var inWhitespace = false
        for scalar in folded.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                if !inWhitespace, !out.isEmpty { out.append(" ") }
                inWhitespace = true
            } else {
                out.unicodeScalars.append(scalar)
                inWhitespace = false
            }
        }
        if out.hasSuffix(" ") { out.removeLast() }
        return out
    }

    /// SHA-256 digest of the canonical form, hex-encoded.
    public static func canonicalHash(_ text: String) -> String {
        let c = canonical(text)
        let digest = SHA256.hash(data: Data(c.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Strip a YAML frontmatter block if the document starts with one.
    /// A YAML block is `---` on its own line, any content, then `---` on its own line.
    public static func stripYAMLFrontmatter(_ text: String) -> String {
        let trimmed = text.drop { $0 == "\u{FEFF}" }
        var lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            return String(trimmed)
        }
        lines.removeFirst()
        var closeIndex: Int?
        for (i, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces) == "---" {
                closeIndex = i
                break
            }
        }
        guard let close = closeIndex else { return String(trimmed) }
        let body = lines.dropFirst(close + 1)
        return body.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
