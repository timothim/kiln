import XCTest
@testable import KilnCore

final class ChatMLTests: XCTestCase {
    func testBuildProducesThreeRoleMessages() {
        let chunk = Chunk(
            sourcePath: "notes/monday.md",
            kind: .text,
            userPrompt: "Continue in your own voice.",
            assistantText: "A cold morning. The fog sat in the trees until ten."
        )
        let example = ChatMLBuilder.build(chunk: chunk)
        XCTAssertEqual(example.messages.count, 3)
        XCTAssertEqual(example.messages[0].role, "system")
        XCTAssertEqual(example.messages[1].role, "user")
        XCTAssertEqual(example.messages[1].content, chunk.userPrompt)
        XCTAssertEqual(example.messages[2].role, "assistant")
        XCTAssertEqual(example.messages[2].content, chunk.assistantText)
        XCTAssertEqual(example.sourcePath, chunk.sourcePath)
    }

    func testDefaultSystemPromptMentionsVoice() {
        XCTAssertTrue(
            ChatMLBuilder.defaultSystemPrompt.localizedCaseInsensitiveContains("voice"),
            "system prompt should anchor on the user's voice"
        )
    }

    func testCustomSystemPromptOverridesDefault() {
        let chunk = Chunk(
            sourcePath: "a.md",
            kind: .text,
            userPrompt: "p",
            assistantText: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        )
        let example = ChatMLBuilder.build(chunk: chunk, systemPrompt: "custom-system")
        XCTAssertEqual(example.messages[0].content, "custom-system")
    }

    func testExampleEncodesMessagesButNotSourcePath() throws {
        let chunk = Chunk(
            sourcePath: "secret/path.md",
            kind: .text,
            userPrompt: "prompt",
            assistantText: "body"
        )
        let example = ChatMLBuilder.build(chunk: chunk)
        let encoder = JSONLWriter.makeEncoder()
        let data = try encoder.encode(example)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"messages\""))
        XCTAssertFalse(json.contains("secret/path.md"))
        XCTAssertFalse(json.contains("\"sourcePath\""))
    }
}
