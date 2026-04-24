import Foundation

/// Derives an ETA for the remaining iterations from the sidecar's
/// `tokens_per_s` stream. MLX kernel-compile is bursty during the first ~20
/// iterations (see `.claude/skills/mlx-lora-finetuning/SKILL.md` §7), so those
/// samples are discarded — otherwise the ETA starts off wildly optimistic and
/// the number jumps backwards as the run warms up. After warm-up we keep an
/// EMA of tokens/s and convert it to wall-clock via the tokens-per-iter
/// constant `batchSize × maxSeqLength`.
///
/// The sidecar itself already emits `eta_s` when it's in a position to. This
/// estimator is the fallback for runs where `eta_s` is missing (older sidecar
/// builds or transient windows where the field is null).
public struct EtaEstimator: Sendable {
    public let warmupIters: Int
    public let alpha: Double
    public let tokensPerIter: Double

    private var ema: Double?
    private var sampleCount: Int = 0

    public init(warmupIters: Int = 20, alpha: Double = 0.3, tokensPerIter: Double) {
        precondition(tokensPerIter > 0, "tokensPerIter must be positive")
        precondition((0...1).contains(alpha), "alpha must be in [0, 1]")
        self.warmupIters = warmupIters
        self.alpha = alpha
        self.tokensPerIter = tokensPerIter
    }

    /// Convenience init that derives tokensPerIter from a `Hyperparameters`.
    public init(hyperparameters: Hyperparameters, warmupIters: Int = 20, alpha: Double = 0.3) {
        self.init(
            warmupIters: warmupIters,
            alpha: alpha,
            tokensPerIter: Double(hyperparameters.batchSize * hyperparameters.maxSeqLength)
        )
    }

    public var hasWarmedUp: Bool { ema != nil }

    /// Feed in a progress datum. Returns the current ETA in seconds, or
    /// `nil` while warming up or if tokens/s is missing.
    public mutating func update(iter: Int, tokensPerSec: Double?, totalIters: Int) -> TimeInterval? {
        guard iter >= warmupIters, let tps = tokensPerSec, tps > 0 else {
            return nil
        }
        sampleCount += 1
        if let prev = ema {
            ema = alpha * tps + (1 - alpha) * prev
        } else {
            ema = tps
        }
        guard let current = ema, current > 0 else { return nil }
        let remainingIters = max(0, totalIters - iter)
        let remainingTokens = Double(remainingIters) * tokensPerIter
        return remainingTokens / current
    }
}
