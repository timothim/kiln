import XCTest
@testable import KilnCore

final class NormalizationTests: XCTestCase {
    func testCanonicalIsWhitespaceInvariant() {
        let a = TextNormalization.canonical("  Hello   World \n ")
        let b = TextNormalization.canonical("hello world")
        XCTAssertEqual(a, b)
    }

    func testCanonicalHashStableAcrossFormatting() {
        let h1 = TextNormalization.canonicalHash("One\t two\nthree")
        let h2 = TextNormalization.canonicalHash("ONE TWO THREE")
        XCTAssertEqual(h1, h2)
    }

    func testStripYAMLFrontmatter() {
        let doc = """
        ---
        title: Journal
        tags: [note, morning]
        ---

        # Morning

        Slept poorly.
        """
        let stripped = TextNormalization.stripYAMLFrontmatter(doc)
        XCTAssertTrue(stripped.hasPrefix("# Morning"))
        XCTAssertFalse(stripped.contains("title: Journal"))
    }

    func testStripYAMLFrontmatterIsNoOpWhenAbsent() {
        let doc = "# Morning\n\nSlept poorly.\n"
        XCTAssertEqual(TextNormalization.stripYAMLFrontmatter(doc), doc)
    }
}
