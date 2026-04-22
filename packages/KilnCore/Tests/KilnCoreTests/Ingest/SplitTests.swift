import XCTest
@testable import KilnCore

final class SplitTests: XCTestCase {
    private func ex(_ path: String, _ body: String = "x") -> ChatMLExample {
        ChatMLExample(
            messages: [
                ChatMLMessage(role: "system", content: "s"),
                ChatMLMessage(role: "user", content: "p"),
                ChatMLMessage(role: "assistant", content: body)
            ],
            sourcePath: path
        )
    }

    func testEmptyInputReturnsEmptySplits() {
        let (train, eval) = DatasetSplit.split([], evalFraction: 0.10, seed: 1)
        XCTAssertTrue(train.isEmpty)
        XCTAssertTrue(eval.isEmpty)
    }

    func testSingleFileGoesToTrain() {
        let items = [ex("only.md", "a"), ex("only.md", "b")]
        let (train, eval) = DatasetSplit.split(items, evalFraction: 0.10, seed: 1)
        XCTAssertEqual(train.count, 2)
        XCTAssertTrue(eval.isEmpty)
    }

    func testFileLevelHoldoutNoLeakage() {
        var items: [ChatMLExample] = []
        for f in 0..<10 {
            for i in 0..<3 {
                items.append(ex("file\(f).md", "chunk-\(i)"))
            }
        }
        let (train, eval) = DatasetSplit.split(items, evalFraction: 0.20, seed: 42)
        let trainFiles = Set(train.map(\.sourcePath))
        let evalFiles = Set(eval.map(\.sourcePath))
        XCTAssertTrue(trainFiles.isDisjoint(with: evalFiles))
        XCTAssertEqual(trainFiles.count + evalFiles.count, 10)
    }

    func testEvalFractionApproximated() {
        var items: [ChatMLExample] = []
        for f in 0..<10 {
            items.append(ex("file\(f).md"))
        }
        let (train, eval) = DatasetSplit.split(items, evalFraction: 0.10, seed: 7)
        XCTAssertEqual(eval.count, 1)
        XCTAssertEqual(train.count, 9)
    }

    func testDeterministicForSameSeed() {
        var items: [ChatMLExample] = []
        for f in 0..<20 {
            items.append(ex("f\(f).md"))
        }
        let a = DatasetSplit.split(items, evalFraction: 0.10, seed: 123)
        let b = DatasetSplit.split(items, evalFraction: 0.10, seed: 123)
        XCTAssertEqual(a.train.map(\.sourcePath), b.train.map(\.sourcePath))
        XCTAssertEqual(a.eval.map(\.sourcePath), b.eval.map(\.sourcePath))
    }

    func testDifferentSeedsProduceDifferentSplits() {
        var items: [ChatMLExample] = []
        for f in 0..<20 {
            items.append(ex("f\(f).md"))
        }
        let a = DatasetSplit.split(items, evalFraction: 0.20, seed: 1)
        let b = DatasetSplit.split(items, evalFraction: 0.20, seed: 999)
        let aEval = Set(a.eval.map(\.sourcePath))
        let bEval = Set(b.eval.map(\.sourcePath))
        XCTAssertNotEqual(aEval, bEval)
    }

    func testSmallCorpusStillHoldsOutOneFile() {
        let items = [ex("a.md"), ex("b.md"), ex("c.md")]
        let (_, eval) = DatasetSplit.split(items, evalFraction: 0.10, seed: 3)
        XCTAssertEqual(eval.count, 1)
    }

    func testZeroEvalFractionKeepsAllInTrain() {
        let items = [ex("a.md"), ex("b.md"), ex("c.md")]
        let (train, eval) = DatasetSplit.split(items, evalFraction: 0.0, seed: 3)
        XCTAssertEqual(train.count, 3)
        XCTAssertTrue(eval.isEmpty)
    }
}
