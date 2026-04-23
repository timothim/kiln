import XCTest
@testable import KilnCore

final class EmailParserTests: XCTestCase {
    private let parser = EmailParser()
    private let userEmails: Set<String> = ["tim@pm.me"]

    private func config(userEmails: Set<String>) -> IngestConfig {
        IngestConfig(userEmails: userEmails)
    }

    func testSingleEmlFromUserYieldsOneChunk() throws {
        let url = TestFixtures.fixture("emails/01-from-user.eml")
        let chunks = try parser.parse(url: url, config: config(userEmails: userEmails))
        XCTAssertEqual(chunks.count, 1)
        let chunk = try XCTUnwrap(chunks.first)
        XCTAssertEqual(chunk.kind, .chat)
        XCTAssertTrue(chunk.userPrompt.contains("Subject: fog on the bridge"))
        XCTAssertTrue(chunk.userPrompt.contains("From: tim@pm.me"))
        XCTAssertTrue(chunk.assistantText.contains("fog sat in the trees"))
        XCTAssertFalse(chunk.assistantText.contains("Subject:"))
    }

    func testEmlFromNonUserProducesNoChunks() throws {
        let url = TestFixtures.fixture("emails/02-from-other.eml")
        let chunks = try parser.parse(url: url, config: config(userEmails: userEmails))
        XCTAssertTrue(chunks.isEmpty)
    }

    func testEmptyUserEmailsRejectsEverything() throws {
        let url = TestFixtures.fixture("emails/01-from-user.eml")
        let chunks = try parser.parse(url: url, config: IngestConfig())
        XCTAssertTrue(chunks.isEmpty, "fail-closed when userEmails is unset")
    }

    func testMboxYieldsOnlyUserAuthoredMessages() throws {
        let url = TestFixtures.fixture("emails/03-mailbox.mbox")
        let chunks = try parser.parse(url: url, config: config(userEmails: userEmails))
        XCTAssertEqual(chunks.count, 2)
        XCTAssertTrue(chunks[0].assistantText.contains("Eggs, bread, oat milk"))
        XCTAssertFalse(
            chunks.contains { $0.assistantText.contains("picked up the cheese") },
            "Mara's reply must not become a user-authored chunk"
        )
    }

    func testMboxQuotedPrintableDecodesToCafeWithAccent() throws {
        let url = TestFixtures.fixture("emails/03-mailbox.mbox")
        let chunks = try parser.parse(url: url, config: config(userEmails: userEmails))
        let qpChunk = try XCTUnwrap(chunks.first { $0.userPrompt.contains("new roast recommendation") })
        XCTAssertTrue(qpChunk.assistantText.contains("café"), "quoted-printable must decode =C3=A9 to é")
        XCTAssertFalse(qpChunk.assistantText.contains("=C3=A9"))
        XCTAssertFalse(qpChunk.assistantText.contains("=\n"), "soft line breaks must collapse")
        XCTAssertTrue(qpChunk.assistantText.contains("pastries are also rumored"),
                      "soft-line-broken word must reassemble")
    }

    func testSenderMatchIsCaseInsensitive() throws {
        let url = TestFixtures.fixture("emails/01-from-user.eml")
        let upper = try parser.parse(url: url, config: config(userEmails: ["TIM@PM.ME"]))
        XCTAssertEqual(upper.count, 1, "configured email in all-caps must still match the lowercased sender")
        let mixed = try parser.parse(url: url, config: config(userEmails: ["Tim@PM.ME"]))
        XCTAssertEqual(mixed.count, 1)
    }

    func testDisplayNameIsStrippedFromSender() throws {
        // The fixture uses `From: Tim <tim@pm.me>`. The parser should extract
        // just `tim@pm.me` before comparing.
        let url = TestFixtures.fixture("emails/01-from-user.eml")
        let chunks = try parser.parse(url: url, config: config(userEmails: ["tim@pm.me"]))
        XCTAssertEqual(chunks.count, 1)
        let chunk = try XCTUnwrap(chunks.first)
        XCTAssertTrue(chunk.userPrompt.contains("From: tim@pm.me"))
        XCTAssertFalse(chunk.userPrompt.contains("<"))
    }

    func testEndToEndPipelineIncludesUserEmailChunks() async throws {
        let tempDir = try TestFixtures.makeTempDir(prefix: "kiln-email-pipeline")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let out = tempDir.appendingPathComponent("out", isDirectory: true)
        let cfg = IngestConfig(userEmails: userEmails)
        let pipeline = IngestPipeline(config: cfg)
        let report = try await pipeline.run(
            sourceDirectory: TestFixtures.sampleCorpusURL,
            outputDirectory: out
        )
        XCTAssertGreaterThan(report.trainCount, 0)
        let trainText = try String(contentsOf: out.appendingPathComponent("train.jsonl"), encoding: .utf8)
        let allText = trainText + (try String(
            contentsOf: out.appendingPathComponent("eval.jsonl"),
            encoding: .utf8
        ))
        XCTAssertTrue(
            allText.contains("fog sat in the trees") || allText.contains("Eggs, bread, oat milk") || allText.contains("café"),
            "at least one user-authored email body must survive dedup + quality"
        )
    }
}
