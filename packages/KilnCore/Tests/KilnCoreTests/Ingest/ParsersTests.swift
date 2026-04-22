import XCTest
@testable import KilnCore

final class ParsersTests: XCTestCase {
    let config = IngestConfig(userName: "Test User")

    // MARK: - Markdown

    func testMarkdownParserStripsYAMLFrontmatter() throws {
        let tmp = try writeTemp(name: "with_fm.md", content: """
            ---
            title: Journal
            tags: [a, b]
            ---

            # Journal

            Slept poorly. Two coffees before noon.
            """)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let chunks = try MarkdownTextParser().parse(url: tmp, config: config)
        XCTAssertEqual(chunks.count, 1)
        let chunk = try XCTUnwrap(chunks.first)
        XCTAssertEqual(chunk.kind, .text)
        XCTAssertFalse(chunk.assistantText.contains("title:"))
        XCTAssertTrue(chunk.assistantText.hasPrefix("Slept"))
    }

    func testMarkdownParserExtractsTitleAsPromptHint() throws {
        let url = TestFixtures.fixture("01-deploy-notes.md")
        let chunks = try MarkdownTextParser().parse(url: url, config: config)
        let chunk = try XCTUnwrap(chunks.first)
        XCTAssertTrue(chunk.userPrompt.contains("Deploy notes"))
        XCTAssertFalse(chunk.assistantText.hasPrefix("#"))
    }

    // MARK: - OpenAI chat

    func testOpenAIChatParserSwapsRolesToUserVoice() throws {
        let url = TestFixtures.fixture("chat_openai_01.json")
        let chunks = try OpenAIChatParser().parse(url: url, config: config)
        XCTAssertFalse(chunks.isEmpty)
        // Fixture has 6 turns alternating user/assistant/user/.../; Tim starts,
        // so pairs are formed at indices 2 and 4 (user after assistant).
        XCTAssertEqual(chunks.count, 2)
        for chunk in chunks {
            XCTAssertEqual(chunk.kind, .chat)
            // The "user" slot content should be from the source assistant role.
            // Spot-check: the second Tim turn follows assistant's "Depends on the sizes...".
            XCTAssertFalse(chunk.userPrompt.isEmpty)
            XCTAssertFalse(chunk.assistantText.isEmpty)
        }
        let firstPrompt = chunks[0].userPrompt
        XCTAssertTrue(firstPrompt.hasPrefix("Depends on"))
    }

    func testOpenAIChatParserDoesNotClaimIMessageFiles() {
        let url = TestFixtures.fixture("imessage_sample.json")
        let data = try? Data(contentsOf: url)
        XCTAssertFalse(OpenAIChatParser().canParse(url: url, probe: data))
    }

    // MARK: - iMessage

    func testIMessageParserKeepsOnlyMeAsAssistant() throws {
        let url = TestFixtures.fixture("imessage_sample.json")
        let chunks = try IMessageParser().parse(url: url, config: config)
        XCTAssertFalse(chunks.isEmpty)
        for chunk in chunks {
            XCTAssertEqual(chunk.kind, .chat)
            // Every assistantText comes from a "me" turn; prompt comes from non-me.
            XCTAssertFalse(chunk.assistantText.isEmpty)
            XCTAssertFalse(chunk.userPrompt.isEmpty)
        }
        // First "me" turn in thread 1 follows Sam's "morning — did you see the eval results?"
        XCTAssertTrue(chunks[0].userPrompt.contains("eval results"))
    }

    func testIMessageParserApplies180DayCutoff() throws {
        let tmp = try writeTemp(name: "old.json", content: """
            {
              "schema": "kiln.imessage.v1",
              "exported_at": "2026-04-10T00:00:00Z",
              "threads": [{
                "handle": "+1",
                "display_name": "Old",
                "messages": [
                  {"ts": "2024-01-01T00:00:00Z", "from": "other", "text": "ancient"},
                  {"ts": "2024-01-01T00:01:00Z", "from": "me", "text": "reply"}
                ]
              }]
            }
            """)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let chunks = try IMessageParser().parse(url: tmp, config: config)
        XCTAssertEqual(chunks.count, 0)
    }

    // MARK: - Code

    func testCodeParserExtractsPythonDocstrings() throws {
        let url = TestFixtures.fixture("example_script.py")
        let chunks = try CodeParser().parse(url: url, config: config)
        XCTAssertGreaterThanOrEqual(chunks.count, 2) // module + 1+ function
        XCTAssertTrue(chunks.contains { $0.assistantText.contains("SHA-256") })
        XCTAssertTrue(chunks.contains { $0.assistantText.contains("Symlinks are skipped") })
        for chunk in chunks {
            XCTAssertEqual(chunk.kind, .code)
            XCTAssertTrue(chunk.userPrompt.contains("Python"))
        }
    }

    func testCodeParserExtractsSwiftTripleSlashDocs() throws {
        let url = TestFixtures.fixture("example_view.swift")
        let chunks = try CodeParser().parse(url: url, config: config)
        XCTAssertFalse(chunks.isEmpty)
        XCTAssertTrue(chunks.contains { $0.assistantText.contains("drop zone for folders") })
        XCTAssertTrue(chunks.allSatisfy { $0.userPrompt.contains("Swift") })
    }

    func testCodeParserExtractsTypeScriptJSDoc() throws {
        let url = TestFixtures.fixture("example_types.ts")
        let chunks = try CodeParser().parse(url: url, config: config)
        XCTAssertGreaterThanOrEqual(chunks.count, 2)
        XCTAssertTrue(chunks.contains { $0.assistantText.contains("outbound event") })
        XCTAssertTrue(chunks.allSatisfy { $0.userPrompt.contains("TypeScript") })
    }

    // MARK: - Registry

    func testRegistryDispatchesByShape() throws {
        let registry = ParserRegistry()
        XCTAssertTrue(registry.parser(for: TestFixtures.fixture("imessage_sample.json")) is IMessageParser)
        XCTAssertTrue(registry.parser(for: TestFixtures.fixture("chat_openai_01.json")) is OpenAIChatParser)
        XCTAssertTrue(registry.parser(for: TestFixtures.fixture("01-deploy-notes.md")) is MarkdownTextParser)
        XCTAssertTrue(registry.parser(for: TestFixtures.fixture("example_script.py")) is CodeParser)
    }

    // MARK: - Helpers

    private func writeTemp(name: String, content: String) throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("kiln-parsers-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
