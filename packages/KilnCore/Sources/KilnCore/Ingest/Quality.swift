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

public enum QualityVerdict: Sendable, Equatable {
    case accepted
    case rejected(SkipReason)
}

public enum QualityFilter {
    public static func evaluate(
        _ text: String,
        config: IngestConfig
    ) -> (verdict: QualityVerdict, metrics: QualityMetrics) {
        let metrics = measure(text)

        if metrics.charCount < config.minChunkChars {
            return (.rejected(.tooShort), metrics)
        }
        if metrics.nonASCIIRatio > config.maxNonASCIIRatio {
            return (.rejected(.tooMuchNonASCII), metrics)
        }
        if metrics.wordCount >= 20 {
            let repetition = 1.0 - metrics.uniqueWordRatio
            if repetition > config.maxRepetitionRatio {
                return (.rejected(.tooRepetitive), metrics)
            }
        }
        if !config.allowedLanguages.isEmpty,
           let lang = metrics.detectedLanguage,
           !config.allowedLanguages.contains(lang) {
            return (.rejected(.wrongLanguage), metrics)
        }
        return (.accepted, metrics)
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
