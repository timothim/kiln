import XCTest
@testable import KilnCore

final class IncrementalLearningTests: XCTestCase {
    func testContinueThrowsNotImplemented() async {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        let request = IncrementalLearning.Request(
            baseAdapterURL: tmp,
            additionalCorpusURL: tmp,
            extraEpochs: 1
        )
        do {
            _ = try await IncrementalLearning.continueTraining(request)
            XCTFail("Expected IncrementalLearning.LearnError.notImplemented")
        } catch IncrementalLearning.LearnError.notImplemented {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFutureCheckpointContinuation() throws {
        try XCTSkipIf(
            !IncrementalLearning.isImplemented,
            "IncrementalLearning requires the Python trainer to honour a --resume flag"
        )
    }
}
