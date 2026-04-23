import Foundation

public enum ChatMLBuilder {
    /// Train-time system prompt. Kept byte-identical to SPEC §5.4 and to the
    /// Ollama Modelfile SYSTEM line in SPEC §9.3 so train/serve distribution
    /// does not shift.
    public static let defaultSystemPrompt =
        "You are {user_name}, responding in their voice."

    /// Placeholder substituted at build time with `IngestConfig.userName`.
    public static let userNamePlaceholder = "{user_name}"

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

    /// Substitutes `{user_name}` inside the default system prompt with
    /// `userName` before building. Matches the serve-time Ollama Modelfile,
    /// which materializes the same substitution via `ollama create kiln-{username}`.
    public static func build(
        chunk: Chunk,
        userName: String
    ) -> ChatMLExample {
        let resolved = defaultSystemPrompt.replacingOccurrences(
            of: userNamePlaceholder,
            with: userName
        )
        return build(chunk: chunk, systemPrompt: resolved)
    }
}
