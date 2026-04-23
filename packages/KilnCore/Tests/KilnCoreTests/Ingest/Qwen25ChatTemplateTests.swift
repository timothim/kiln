import XCTest
@testable import KilnCore

final class Qwen25ChatTemplateTests: XCTestCase {
    private let canonical: [ChatMLMessage] = [
        ChatMLMessage(role: "system", content: "You are Tim, responding in their voice."),
        ChatMLMessage(role: "user", content: "Continue in your own voice."),
        ChatMLMessage(role: "assistant", content: "The fog sat in the trees until ten.")
    ]

    func testGoldenRenderMatchesByteForByte() {
        let golden =
            "<|im_start|>system\nYou are Tim, responding in their voice.<|im_end|>\n" +
            "<|im_start|>user\nContinue in your own voice.<|im_end|>\n" +
            "<|im_start|>assistant\nThe fog sat in the trees until ten.<|im_end|>\n"
        XCTAssertEqual(
            Qwen25ChatTemplate.render(messages: canonical, addGenerationPrompt: false),
            golden
        )
    }

    func testAddGenerationPromptAppendsOpenAssistantSegment() {
        let rendered = Qwen25ChatTemplate.render(
            messages: Array(canonical.prefix(2)),
            addGenerationPrompt: true
        )
        let expected =
            "<|im_start|>system\nYou are Tim, responding in their voice.<|im_end|>\n" +
            "<|im_start|>user\nContinue in your own voice.<|im_end|>\n" +
            "<|im_start|>assistant\n"
        XCTAssertEqual(rendered, expected)
    }

    /// Train/serve parity: the bytes the trainer sees for a (system, user,
    /// assistant) triple must include, as a prefix, the bytes the model sees
    /// at serve time when Ollama asks it to continue from (system, user).
    func testTrainAndServePrefixesAgree() {
        let trainRender = Qwen25ChatTemplate.render(messages: canonical, addGenerationPrompt: false)
        let serveRender = Qwen25ChatTemplate.render(
            messages: Array(canonical.prefix(2)),
            addGenerationPrompt: true
        )
        XCTAssertTrue(
            trainRender.hasPrefix(serveRender),
            "train bytes must start with the serve-time prefix up to the assistant's first token"
        )
        let remainder = String(trainRender.dropFirst(serveRender.count))
        XCTAssertEqual(remainder, "The fog sat in the trees until ten.<|im_end|>\n")
    }

    /// Matches the Ollama `TEMPLATE` from SPEC §9.3 when rendered with the
    /// same (system, user) pair and an empty response. If these two ever
    /// drift, serve-time prompts diverge from what the model was trained on.
    func testMatchesOllamaModelfilePrefix() {
        let system = canonical[0].content
        let prompt = canonical[1].content
        let ollamaRendered =
            "<|im_start|>system\n\(system)<|im_end|>\n" +
            "<|im_start|>user\n\(prompt)<|im_end|>\n" +
            "<|im_start|>assistant\n"
        let serveRender = Qwen25ChatTemplate.render(
            messages: Array(canonical.prefix(2)),
            addGenerationPrompt: true
        )
        XCTAssertEqual(serveRender, ollamaRendered)
    }

    func testEmptyMessagesWithoutGenerationPromptRendersEmpty() {
        XCTAssertEqual(Qwen25ChatTemplate.render(messages: []), "")
    }

    func testEmptyMessagesWithGenerationPromptRendersOnlyAssistantOpener() {
        XCTAssertEqual(
            Qwen25ChatTemplate.render(messages: [], addGenerationPrompt: true),
            "<|im_start|>assistant\n"
        )
    }

    func testDefaultSystemPromptMatchesSpecLiteral() {
        XCTAssertEqual(
            ChatMLBuilder.defaultSystemPrompt,
            "You are {user_name}, responding in their voice."
        )
        XCTAssertTrue(ChatMLBuilder.defaultSystemPrompt.contains("{user_name}"))
    }

    func testBuildWithUserNameSubstitutesPlaceholder() {
        let chunk = Chunk(
            sourcePath: "a.md",
            kind: .text,
            userPrompt: "Continue in your own voice.",
            assistantText: "Morning notes."
        )
        let example = ChatMLBuilder.build(chunk: chunk, userName: "Tim")
        XCTAssertEqual(
            example.messages[0].content,
            "You are Tim, responding in their voice."
        )
        XCTAssertFalse(example.messages[0].content.contains("{user_name}"))
    }

    func testBuildWithUserNameRendersInQwenTemplate() {
        let chunk = Chunk(
            sourcePath: "a.md",
            kind: .text,
            userPrompt: "p",
            assistantText: "a"
        )
        let example = ChatMLBuilder.build(chunk: chunk, userName: "Tim")
        let rendered = Qwen25ChatTemplate.render(messages: example.messages)
        XCTAssertTrue(rendered.contains("<|im_start|>system\nYou are Tim, responding in their voice.<|im_end|>\n"))
        XCTAssertTrue(rendered.contains("<|im_start|>user\np<|im_end|>\n"))
        XCTAssertTrue(rendered.contains("<|im_start|>assistant\na<|im_end|>\n"))
    }
}
