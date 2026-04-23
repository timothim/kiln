import Foundation

/// Literal Qwen2.5-Instruct chat template renderer.
///
/// Produces the same byte sequence as the tokenizer's `apply_chat_template`
/// and the Ollama `TEMPLATE` string documented in SPEC §9.3. Keeping this
/// in the M2 data package gives us a train/serve parity check without
/// pulling a Python dependency into the Swift side.
public enum Qwen25ChatTemplate {
    /// Renders a ChatML message list as Qwen2.5-Instruct's raw chat format:
    /// one `<|im_start|>role\ncontent<|im_end|>\n` segment per message.
    ///
    /// - Parameter addGenerationPrompt: when true, appends an opening
    ///   `<|im_start|>assistant\n` without a matching `<|im_end|>` — this is
    ///   the serve-time prefix the model continues from. When false, the
    ///   output is exactly the prefix seen during training (all messages
    ///   including the assistant response, each closed by `<|im_end|>\n`).
    public static func render(
        messages: [ChatMLMessage],
        addGenerationPrompt: Bool = false
    ) -> String {
        var out = ""
        for message in messages {
            out += "<|im_start|>\(message.role)\n\(message.content)<|im_end|>\n"
        }
        if addGenerationPrompt {
            out += "<|im_start|>assistant\n"
        }
        return out
    }
}
