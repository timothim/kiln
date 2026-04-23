// tf-idf-swift.swift
// Kiln — log-odds-with-informative-Dirichlet-prior (Monroe et al. 2008).
// See interpretability-helpers/SKILL.md §2 for the math.
//
// Usage:
//   let bg = BackgroundCorpus(counts: ..., total: ..., alpha: 0.01)
//   let scorer = LogOddsScorer(background: bg)
//   let results = scorer.score(userCounts: uc, userTotal: utot)
//   // results: [(term, z, userCount, backgroundCount, expected)] sorted by |z| desc

import Foundation

// MARK: - Types

public struct LogOddsScore: Equatable {
    public let term: String
    public let z: Double
    public let userCount: Int
    public let backgroundCount: Int
    public let expectedCount: Double
}

public struct BackgroundCorpus {
    public let counts: [String: Int]
    public let total: Int
    /// Smoothing strength. α_w = alpha * background_count_w for each term w.
    public let alpha: Double

    public init(counts: [String: Int], total: Int, alpha: Double = 0.01) {
        self.counts = counts
        self.total = total
        self.alpha = alpha
    }
}

// MARK: - Log-odds scorer

public struct LogOddsScorer {
    public let background: BackgroundCorpus

    public init(background: BackgroundCorpus) {
        self.background = background
    }

    /// Compute log-odds z-scores for every term in `userCounts`.
    /// Terms with `userCount < minCount` are dropped (noise floor).
    public func score(
        userCounts: [String: Int],
        userTotal: Int,
        minCount: Int = 3
    ) -> [LogOddsScore] {
        var results: [LogOddsScore] = []
        results.reserveCapacity(userCounts.count)

        let bgTotal = Double(background.total)
        let uTotal = Double(userTotal)
        // α total: sum of per-term priors. Closed-form: alpha * bgTotal.
        let alphaSum = background.alpha * bgTotal

        for (term, uCount) in userCounts where uCount >= minCount {
            let bgCount = background.counts[term] ?? 0
            // α_w is proportional to the background frequency (informative prior).
            // Monroe et al. recommend α_w = α_0 · p_bg(w). Use max(bgCount, 1) to
            // avoid zero prior for terms absent from background.
            let priorTerm = background.alpha * Double(max(bgCount, 1))
            let fU = Double(uCount) + priorTerm
            let fB = Double(bgCount) + priorTerm
            let pU = fU / (uTotal + alphaSum)
            let pB = fB / (bgTotal + alphaSum)
            let logOdds = log(pU / (1 - pU)) - log(pB / (1 - pB))
            // Standard error of the log-odds ratio (Monroe eq. 22).
            let variance = 1.0 / fU + 1.0 / fB
            let z = logOdds / sqrt(variance)
            let expected = (Double(bgCount) / bgTotal) * uTotal
            results.append(
                LogOddsScore(
                    term: term,
                    z: z,
                    userCount: uCount,
                    backgroundCount: bgCount,
                    expectedCount: expected
                )
            )
        }

        results.sort { abs($0.z) > abs($1.z) }
        return results
    }
}

// MARK: - Tokenization

public enum TokenCounter {
    /// Lowercased unigram counts with URL / @mention / code-fence stripping.
    /// For POS n-grams, use NLTagger in a caller module; this is plain text only.
    public static func unigrams(from text: String) -> [String: Int] {
        var counts: [String: Int] = [:]
        counts.reserveCapacity(1024)
        let cleaned = stripNoise(text)
        cleaned.enumerateSubstrings(
            in: cleaned.startIndex..<cleaned.endIndex,
            options: [.byWords, .localized]
        ) { sub, _, _, _ in
            guard var w = sub?.lowercased(), w.count >= 2 else { return }
            // Drop purely numeric tokens.
            if w.allSatisfy({ $0.isNumber || $0 == "." }) { return }
            // Normalize possessive: "kiln's" -> "kiln"; keep contractions ("don't").
            if w.hasSuffix("'s") || w.hasSuffix("\u{2019}s") {
                w.removeLast(2)
            }
            counts[w, default: 0] += 1
        }
        return counts
    }

    private static func stripNoise(_ text: String) -> String {
        var s = text
        // URLs
        s = s.replacingOccurrences(
            of: #"https?://\S+"#, with: " ", options: .regularExpression)
        // @mentions (Twitter/Slack style)
        s = s.replacingOccurrences(
            of: #"@\w+"#, with: " ", options: .regularExpression)
        // Markdown code fences
        s = s.replacingOccurrences(
            of: #"```[\s\S]*?```"#, with: " ", options: .regularExpression)
        // Inline code
        s = s.replacingOccurrences(
            of: #"`[^`]+`"#, with: " ", options: .regularExpression)
        return s
    }
}

// MARK: - Classic TF-IDF (reference only; log-odds is what we ship)

/// TF-IDF is included so regression tests can prove log-odds and TF-IDF
/// disagree on tail terms — this is the entire reason we ship log-odds.
/// Surfacing TF-IDF rankings in the UI is an explicit non-goal (see SKILL §2).
public enum ClassicTFIDF {
    public static func score(
        userCounts: [String: Int],
        userTotal: Int,
        background: BackgroundCorpus
    ) -> [(term: String, tfidf: Double)] {
        var results: [(String, Double)] = []
        results.reserveCapacity(userCounts.count)
        let bgTotal = Double(background.total)
        for (term, uc) in userCounts {
            let tf = Double(uc) / Double(userTotal)
            let bgProb = Double(background.counts[term] ?? 0) / bgTotal
            let idf = log((1 + 1.0) / (1 + bgProb))
            results.append((term, tf * idf))
        }
        return results.sorted { $0.1 > $1.1 }
    }
}

// MARK: - Structural stats

public struct StructuralSummary: Equatable {
    public let sentenceCount: Int
    public let medianLengthTokens: Int
    public let p25LengthTokens: Int
    public let p75LengthTokens: Int
    public let questionRate: Double
    public let exclamationRate: Double
    public let allLowerRate: Double
}

public enum StructuralStats {
    public static func summarize(sentences: [String]) -> StructuralSummary {
        guard !sentences.isEmpty else {
            return StructuralSummary(
                sentenceCount: 0,
                medianLengthTokens: 0,
                p25LengthTokens: 0,
                p75LengthTokens: 0,
                questionRate: 0,
                exclamationRate: 0,
                allLowerRate: 0
            )
        }
        var lengths: [Int] = []
        lengths.reserveCapacity(sentences.count)
        var questions = 0
        var exclamations = 0
        var allLower = 0
        for s in sentences {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let tokenCount = trimmed.split(whereSeparator: { $0.isWhitespace }).count
            lengths.append(tokenCount)
            if trimmed.hasSuffix("?") { questions += 1 }
            if trimmed.hasSuffix("!") { exclamations += 1 }
            if trimmed == trimmed.lowercased() { allLower += 1 }
        }
        guard !lengths.isEmpty else {
            return StructuralSummary(
                sentenceCount: 0,
                medianLengthTokens: 0,
                p25LengthTokens: 0,
                p75LengthTokens: 0,
                questionRate: 0, exclamationRate: 0, allLowerRate: 0
            )
        }
        lengths.sort()
        let n = lengths.count
        let med = lengths[n / 2]
        let p25 = lengths[max(n / 4, 0)]
        let p75 = lengths[min((3 * n) / 4, n - 1)]
        let total = Double(n)
        return StructuralSummary(
            sentenceCount: n,
            medianLengthTokens: med,
            p25LengthTokens: p25,
            p75LengthTokens: p75,
            questionRate: Double(questions) / total,
            exclamationRate: Double(exclamations) / total,
            allLowerRate: Double(allLower) / total
        )
    }
}

// MARK: - Python pseudocode (reference; do not ship)
//
// If Swift and Python disagree by more than 1e-6 on a golden case, the
// Swift port is wrong. Check tokenization first, then α handling.
//
//     import numpy as np
//
//     def logodds(fu: np.ndarray, fb: np.ndarray, alpha: float = 0.01):
//         """fu, fb are aligned count vectors over the same vocabulary."""
//         nu = fu.sum()
//         nb = fb.sum()
//         alpha_w = alpha * np.maximum(fb, 1)         # informative prior
//         alpha_sum = alpha_w.sum()
//         pu = (fu + alpha_w) / (nu + alpha_sum)
//         pb = (fb + alpha_w) / (nb + alpha_sum)
//         lo = np.log(pu / (1 - pu)) - np.log(pb / (1 - pb))
//         var = 1.0 / (fu + alpha_w) + 1.0 / (fb + alpha_w)
//         return lo / np.sqrt(var)
