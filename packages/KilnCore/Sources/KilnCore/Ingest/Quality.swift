import Foundation
import NaturalLanguage

public struct QualityMetrics: Sendable, Equatable {
    public let charCount: Int
    public let wordCount: Int
    public let uniqueWordRatio: Double
    public let nonASCIIRatio: Double
    public let detectedLanguage: String?

    public init(
        charCount: Int,
        wordCount: Int,
        uniqueWordRatio: Double,
        nonASCIIRatio: Double,
        detectedLanguage: String?
    ) {
        self.charCount = charCount
        self.wordCount = wordCount
        self.uniqueWordRatio = uniqueWordRatio
        self.nonASCIIRatio = nonASCIIRatio
        self.detectedLanguage = detectedLanguage
    }
}

public enum QualityTier: String, Codable, Sendable, Equatable {
    case accept
    case softReject
    case hardReject
}

public enum QualityVerdict: Sendable, Equatable {
    case accepted
    case softRejected(SkipReason)
    case hardRejected(SkipReason)

    public var tier: QualityTier {
        switch self {
        case .accepted: return .accept
        case .softRejected: return .softReject
        case .hardRejected: return .hardReject
        }
    }
}

public enum QualityFilter {
    /// Two-tier rejection policy. Hard rejects are unsalvageable (too short,
    /// wrong language, emoji/binary spam) and will never enter any training
    /// signal. Soft rejects (currently: repetition) are still dropped from the
    /// M2 train/eval split but carry a shape useful as DPO "rejected" feedstock
    /// when M7 lands. See DECISIONS #5 for the deferral rationale.
    public static func tier(for reason: SkipReason) -> QualityTier {
        switch reason {
        case .tooShort, .wrongLanguage, .tooMuchNonASCII:
            return .hardReject
        case .tooRepetitive:
            return .softReject
        case .unsupportedExtension, .tooLarge, .unreadable, .parserFailure,
             .emptyAfterParse, .exactDuplicate, .nearDuplicate:
            return .hardReject
        }
    }

    public static func evaluate(
        _ text: String,
        config: IngestConfig
    ) -> (verdict: QualityVerdict, metrics: QualityMetrics) {
        let metrics = measure(text)

        if metrics.charCount < config.minChunkChars {
            return (verdict(for: .tooShort), metrics)
        }
        if metrics.nonASCIIRatio > config.maxNonASCIIRatio {
            return (verdict(for: .tooMuchNonASCII), metrics)
        }
        if metrics.wordCount >= 20 {
            let repetition = 1.0 - metrics.uniqueWordRatio
            if repetition > config.maxRepetitionRatio {
                return (verdict(for: .tooRepetitive), metrics)
            }
        }
        if !config.allowedLanguages.isEmpty,
           let lang = metrics.detectedLanguage,
           !config.allowedLanguages.contains(lang) {
            return (verdict(for: .wrongLanguage), metrics)
        }
        return (.accepted, metrics)
    }

    private static func verdict(for reason: SkipReason) -> QualityVerdict {
        tier(for: reason) == .softReject ? .softRejected(reason) : .hardRejected(reason)
    }

    public static func measure(_ text: String) -> QualityMetrics {
        let charCount = text.count
        let words = tokenize(text)
        let uniqueWordRatio: Double
        if words.isEmpty {
            uniqueWordRatio = 1.0
        } else {
            uniqueWordRatio = Double(Set(words).count) / Double(words.count)
        }

        let scalars = text.unicodeScalars
        let nonASCIIRatio: Double
        if scalars.isEmpty {
            nonASCIIRatio = 0.0
        } else {
            var nonASCII = 0
            for scalar in scalars where !scalar.isASCII {
                nonASCII += 1
            }
            nonASCIIRatio = Double(nonASCII) / Double(scalars.count)
        }

        let detectedLanguage = Self.detectLanguage(text, charCount: charCount)

        return QualityMetrics(
            charCount: charCount,
            wordCount: words.count,
            uniqueWordRatio: uniqueWordRatio,
            nonASCIIRatio: nonASCIIRatio,
            detectedLanguage: detectedLanguage
        )
    }

    private static func detectLanguage(_ text: String, charCount: Int) -> String? {
        guard charCount >= 40 else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue
    }

    private static func tokenize(_ text: String) -> [String] {
        var words: [String] = []
        var current = ""
        for ch in text.lowercased() {
            if ch.isLetter || ch.isNumber {
                current.append(ch)
            } else if !current.isEmpty {
                words.append(current)
                current = ""
            }
        }
        if !current.isEmpty {
            words.append(current)
        }
        return words
    }
}
