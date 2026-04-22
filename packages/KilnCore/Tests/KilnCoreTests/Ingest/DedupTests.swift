import XCTest
@testable import KilnCore

final class DedupTests: XCTestCase {

    // MARK: - Exact

    func testExactDedupCollapsesWhitespaceDiffs() {
        var d = ExactDedup()
        XCTAssertTrue(d.add("Hello   world"))
        XCTAssertFalse(d.add("hello world"))
        XCTAssertFalse(d.add("HELLO\tWORLD\n"))
        XCTAssertEqual(d.count, 1)
    }

    func testExactDedupKeepsDistinctContent() {
        var d = ExactDedup()
        XCTAssertTrue(d.add("morning journal entry"))
        XCTAssertTrue(d.add("evening journal entry"))
        XCTAssertEqual(d.count, 2)
    }

    // MARK: - MinHash core

    func testMinHashJaccardMonotonic() {
        // Base text of varied content long enough that a single-word change keeps
        // Jaccard above 0.85 (≈ (N-k) / (N+k) with k=8 shingles affected, so N ≳ 99).
        let base = """
            morning journal entry about the dedup pipeline and how it evolved across the
            spring while the team debated whether exact hashing alone would catch the
            duplicates that matter or whether minhash with banded locality sensitive
            hashing was worth the added complexity and the answer after two weeks of
            traces was that both stages pay their rent because exact hashing kills the
            vast majority of copy paste duplicates while minhash catches the edits where
            a single word or a punctuation mark shifts but the document is substantively
            the same piece of writing with the same structure and the same argument and
            the same conclusions reached across the same set of three paragraphs today
            """
        let nearDup = base.replacingOccurrences(of: "punctuation mark", with: "punctuation dash")
        let unrelated = """
            grocery list for tuesday oat milk apples the tart ones a loaf of sourdough
            and a small bag of dark chocolate from the corner store if it is still open
            past six in the evening after work and a bunch of bananas if they still look
            good on the shelf and a tub of yogurt and some frozen berries for smoothies
            and a jar of peanut butter if the store brand is not out of stock again
            """
        let sa = MinHash.signature(
            shingles: MinHash.shingles(base, size: 8),
            numHashes: 128, seed: 42
        )
        let sb = MinHash.signature(
            shingles: MinHash.shingles(nearDup, size: 8),
            numHashes: 128, seed: 42
        )
        let sc = MinHash.signature(
            shingles: MinHash.shingles(unrelated, size: 8),
            numHashes: 128, seed: 42
        )
        let jacAB = MinHash.jaccard(sa, sb)
        let jacAC = MinHash.jaccard(sa, sc)
        XCTAssertGreaterThan(jacAB, 0.85, "near-dup with 1 word change in long text: \(jacAB)")
        XCTAssertGreaterThan(jacAB, jacAC)
        XCTAssertLessThan(jacAC, 0.1)
    }

    func testMinHashSignatureIsDeterministic() {
        let text = "morning journal notes about the dedup pipeline and its edge cases"
        let shingles = MinHash.shingles(text, size: 4)
        let s1 = MinHash.signature(shingles: shingles, numHashes: 64, seed: 7)
        let s2 = MinHash.signature(shingles: shingles, numHashes: 64, seed: 7)
        XCTAssertEqual(s1, s2)
    }

    // MARK: - LSH

    func testMinHashLSHDetectsNearDuplicateAndKeepsDistinct() {
        var lsh = MinHashLSH(threshold: 0.85, numHashes: 128, bands: 32, shingleSize: 8, seed: 99)
        let base = String(repeating: """
            The dedup pipeline runs exact hashing first because it is cheap and catches the
            majority of accidental duplicates introduced by operating system copy actions,
            sync tools, and careless editing. After that the minhash stage handles the
            near-duplicates where a few tokens have been changed but the document is
            substantively the same piece of writing.
            """, count: 3)
        // Same text, only punctuation and capitalization differ — identical shingles.
        let punctDup = base
            .replacingOccurrences(of: ".", with: "!")
            .replacingOccurrences(of: "careless", with: "CARELESS")
        let unrelated = String(repeating: """
            Grocery list for Tuesday: oat milk, apples, the tart ones, a loaf of sourdough,
            and a small bag of the dark chocolate from the corner store if it is still open
            past six in the evening after work.
            """, count: 3)
        XCTAssertTrue(lsh.add(base))
        XCTAssertFalse(lsh.add(punctDup), "near-duplicate should be rejected")
        XCTAssertTrue(lsh.add(unrelated), "unrelated text should pass")
        XCTAssertEqual(lsh.count, 2)
    }

    func testMinHashLSHPassesShortText() {
        var lsh = MinHashLSH(threshold: 0.85, numHashes: 128, bands: 32, shingleSize: 8, seed: 1)
        XCTAssertTrue(lsh.add("too short for shingles"))
        XCTAssertTrue(lsh.add("also too short"))
        // Both pass because they have fewer words than the shingle size.
        XCTAssertEqual(lsh.count, 0)
    }
}
