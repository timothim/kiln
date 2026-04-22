import Foundation

public enum ChatMLBuilder {
    public static let defaultSystemPrompt =
        "You are a writing-style twin. Produce text in the user's own voice — mirror their cadence, vocabulary, and structure."

    public static func build(
        chunk: Chunk,
        systemPrompt: String = defaultSystemPrompt
    ) -> ChatMLExample {
        let messages: [ChatMLMessage] = [
            ChatMLMessage(role: "system", content: systemPrompt),
            ChatMLMessage(role: "user", content: chunk.userPrompt),
            ChatMLMessage(role: "assistant", content: chunk.assistantText)
        ]
        return ChatMLExample(messages: messages, sourcePath: chunk.sourcePath)
    }
}
