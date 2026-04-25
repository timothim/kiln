import Foundation

/// Human-readable card summarizing the user's voice signature — produced
/// by the `style-extractor` distilled component (SPEC §7.3). Renders as
/// a markdown card in the UI. The card view itself is live in
/// ``apps/Kiln/Sources/Features/StyleSignature/StyleSignatureCardView.swift``;
/// the legacy ``StyleSignatureCard.generate`` stub remains as dead code.
public enum StyleSignatureCard {
    public static let isImplemented = true

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
