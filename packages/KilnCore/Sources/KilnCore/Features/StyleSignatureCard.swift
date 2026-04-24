import Foundation

/// Human-readable card summarizing the user's voice signature — produced
/// by the `style-extractor` distilled component (SPEC §7.3). Renders as
/// a markdown card in the UI. Depends on the style-extractor artifact
/// shipping above bar (cosine ≥ 0.75); gated off until it does.
public enum StyleSignatureCard {
    public static let isImplemented = false

    public struct Signature: Sendable, Equatable {
        public let embedding: [Float]
        public let markdownCard: String
        public let topLexicalMarkers: [String]

        public init(embedding: [Float], markdownCard: String, topLexicalMarkers: [String]) {
            self.embedding = embedding
            self.markdownCard = markdownCard
            self.topLexicalMarkers = topLexicalMarkers
        }
    }

    public enum SignatureError: Error, Equatable {
        case notImplemented
        case artifactBelowBar
    }

    public static func generate(forCorpus _: URL) async throws -> Signature {
        throw SignatureError.notImplemented
    }
}
