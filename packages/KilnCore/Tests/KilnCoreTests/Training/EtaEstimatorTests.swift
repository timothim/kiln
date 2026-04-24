import XCTest
@testable import KilnCore

final class EtaEstimatorTests: XCTestCase {

    private let tokensPerIter: Double = 2 * 2_048 // 3B defaults: batch=2, seq=2048

    func test_returns_nil_during_warmup() {
        var eta = EtaEstimator(warmupIters: 20, alpha: 0.3, tokensPerIter: tokensPerIter)
        for iter in 1...19 {
            XCTAssertNil(eta.update(iter: iter, tokensPerSec: 900, totalIters: 400))
        }
        XCTAssertFalse(eta.hasWarmedUp)
    }

    func test_returns_nil_when_tokens_per_sec_missing() {
        var eta = EtaEstimator(warmupIters: 20, alpha: 0.3, tokensPerIter: tokensPerIter)
        XCTAssertNil(eta.update(iter: 50, tokensPerSec: nil, totalIters: 400))
    }

    func test_returns_nil_when_tokens_per_sec_zero() {
        var eta = EtaEstimator(warmupIters: 20, alpha: 0.3, tokensPerIter: tokensPerIter)
        XCTAssertNil(eta.update(iter: 50, tokensPerSec: 0, totalIters: 400))
    }

    func test_first_post_warmup_sample_seeds_ema_as_raw_value() {
        var eta = EtaEstimator(warmupIters: 20, alpha: 0.3, tokensPerIter: tokensPerIter)
        let result = eta.update(iter: 20, tokensPerSec: 900, totalIters: 400)
        XCTAssertNotNil(result)
        // remaining = (400 - 20) * 4096 / 900 ≈ 1729.07 s
        XCTAssertEqual(result ?? -1, (380.0 * tokensPerIter) / 900.0, accuracy: 0.01)
    }

    func test_ema_converges_under_stable_throughput() {
        var eta = EtaEstimator(warmupIters: 20, alpha: 0.3, tokensPerIter: tokensPerIter)
        var last: TimeInterval = 0
        for iter in 20...80 {
            if let r = eta.update(iter: iter, tokensPerSec: 900, totalIters: 400) {
                last = r
            }
        }
        let expected = (400.0 - 80.0) * tokensPerIter / 900.0
        XCTAssertEqual(last, expected, accuracy: expected * 0.05)
    }

    func test_ema_smooths_noisy_throughput() {
        var eta = EtaEstimator(warmupIters: 20, alpha: 0.3, tokensPerIter: tokensPerIter)
        // Alternate 800 / 1000 tokens/s; EMA should settle near the 900 mean.
        for iter in 20...100 {
            let tps: Double = iter.isMultiple(of: 2) ? 1000 : 800
            _ = eta.update(iter: iter, tokensPerSec: tps, totalIters: 400)
        }
        let steady = eta.update(iter: 100, tokensPerSec: 900, totalIters: 400)!
        let naive = (300.0 * tokensPerIter) / 900.0
        XCTAssertEqual(steady, naive, accuracy: naive * 0.10)
    }

    func test_zero_remaining_iters_yields_zero_eta() {
        var eta = EtaEstimator(warmupIters: 20, alpha: 0.3, tokensPerIter: tokensPerIter)
        for iter in 20...400 {
            _ = eta.update(iter: iter, tokensPerSec: 900, totalIters: 400)
        }
        let final = eta.update(iter: 400, tokensPerSec: 900, totalIters: 400)!
        XCTAssertEqual(final, 0, accuracy: 0.01)
    }

    func test_convenience_init_from_hyperparameters() {
        let hp = Hyperparameters()
        var eta = EtaEstimator(hyperparameters: hp)
        let result = eta.update(iter: 20, tokensPerSec: 900, totalIters: 400)
        XCTAssertNotNil(result)
        let expected = (380.0 * Double(hp.batchSize * hp.maxSeqLength)) / 900.0
        XCTAssertEqual(result ?? -1, expected, accuracy: 0.01)
    }
}
