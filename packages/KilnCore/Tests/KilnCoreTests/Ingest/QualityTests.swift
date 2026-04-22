import XCTest
@testable import KilnCore

final class QualityTests: XCTestCase {
    private let config = IngestConfig()

    func testAcceptsNormalEnglishProse() {
        let text = """
        This morning I walked to the river and watched the fog roll off the water. \
        It was colder than I expected. I ran into Mara on the bridge and we talked \
        about the new tokenizer rules for a while. She thinks we should keep the \
        byte fallback on. I am not sure yet, but I will think about it this week.
        """
        let (verdict, metrics) = QualityFilter.evaluate(text, config: config)
        XCTAssertEqual(verdict, .accepted)
        XCTAssertEqual(metrics.detectedLanguage, "en")
        XCTAssertGreaterThan(metrics.uniqueWordRatio, 0.5)
        XCTAssertLessThan(metrics.nonASCIIRatio, 0.05)
    }

    func testRejectsTooShort() throws {
        let text = try String(contentsOf: TestFixtures.fixture("edge_cases/16-tiny.md"), encoding: .utf8)
        let (verdict, metrics) = QualityFilter.evaluate(text, config: config)
        XCTAssertEqual(verdict, .rejected(.tooShort))
        XCTAssertLessThan(metrics.charCount, config.minChunkChars)
    }

    func testRejectsFrenchWhenEnglishOnly() throws {
        let text = try String(contentsOf: TestFixtures.fixture("edge_cases/12-french-journal.md"), encoding: .utf8)
        let (verdict, metrics) = QualityFilter.evaluate(text, config: config)
        XCTAssertEqual(verdict, .rejected(.wrongLanguage))
        XCTAssertEqual(metrics.detectedLanguage, "fr")
    }

    func testAcceptsFrenchWhenAllowed() throws {
        var cfg = config
        cfg.allowedLanguages = ["en", "fr"]
        let text = try String(contentsOf: TestFixtures.fixture("edge_cases/12-french-journal.md"), encoding: .utf8)
        let (verdict, _) = QualityFilter.evaluate(text, config: cfg)
        XCTAssertEqual(verdict, .accepted)
    }

    func testRejectsRepetitive() throws {
        let text = try String(contentsOf: TestFixtures.fixture("edge_cases/13-repetitive.md"), encoding: .utf8)
        let (verdict, metrics) = QualityFilter.evaluate(text, config: config)
        XCTAssertEqual(verdict, .rejected(.tooRepetitive))
        XCTAssertLessThan(metrics.uniqueWordRatio, 0.15)
    }

    func testRejectsEmojiSpamAsNonASCII() throws {
        let text = try String(contentsOf: TestFixtures.fixture("edge_cases/14-emoji-spam.md"), encoding: .utf8)
        let (verdict, metrics) = QualityFilter.evaluate(text, config: config)
        XCTAssertEqual(verdict, .rejected(.tooMuchNonASCII))
        XCTAssertGreaterThan(metrics.nonASCIIRatio, 0.30)
    }

    func testAllowsLightAccentsBelowThreshold() {
        let text = """
        Short note on a café visit: I ordered an espresso and a croissant and sat \
        by the window for almost an hour. The barista recommended a new roast from \
        Colombia which was very good. I will go back tomorrow morning for another cup.
        """
        let (verdict, metrics) = QualityFilter.evaluate(text, config: config)
        XCTAssertEqual(verdict, .accepted)
        XCTAssertLessThan(metrics.nonASCIIRatio, 0.05)
    }

    func testMeasureCountsWordsAndChars() {
        let text = "Hello, world! This is a test."
        let m = QualityFilter.measure(text)
        XCTAssertEqual(m.charCount, text.count)
        XCTAssertEqual(m.wordCount, 6)
        XCTAssertEqual(m.uniqueWordRatio, 1.0)
    }

    func testRepetitionCheckSkipsShortTexts() {
        let text = "no no no no no no no no no no no no no no no"
        let (verdict, metrics) = QualityFilter.evaluate(text, config: config)
        XCTAssertEqual(metrics.wordCount, 15)
        XCTAssertNotEqual(verdict, .rejected(.tooRepetitive))
    }

    func testEmptyTextRejectedAsTooShort() {
        let (verdict, _) = QualityFilter.evaluate("", config: config)
        XCTAssertEqual(verdict, .rejected(.tooShort))
    }
}
