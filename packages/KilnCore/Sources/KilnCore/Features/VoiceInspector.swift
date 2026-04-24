import Foundation

/// Interpretability surface: for a given generated token, show the
/// user which training chunks most influenced it. Uses log-odds /
/// nearest-neighbor tooling from
/// `.claude/skills/interpretability-helpers/SKILL.md`. Depends on the
/// style-extractor embedding shipping — see `StyleSignatureCard`.
public enum VoiceInspector {
    public static let isImplemented = false

    public struct Attribution: Sendable, Equatable {
        public let generatedSpan: Range<String.Index>
        public let nearestChunkIDs: [String]
        public let logOddsTopTerms: [String]

        public init(
            generatedSpan: Range<String.Index>,
            nearestChunkIDs: [String],
            logOddsTopTerms: [String]
        ) {
            self.generatedSpan = generatedSpan
            self.nearestChunkIDs = nearestChunkIDs
            self.logOddsTopTerms = logOddsTopTerms
        }
    }

    public enum InspectorError: Error, Equatable {
        case notImplemented
    }

    public static func attribute(_: String, against _: URL) async throws -> [Attribution] {
        throw InspectorError.notImplemented
    }
}
