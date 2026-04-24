import Foundation

/// The three fixed Growing-Model sample prompts. Per SPEC.md §6.3 and the
/// Phase-3 preview harness in GrowingModelPanelView. The stable `id` strings
/// are the keys the sidecar will emit on the wire on each checkpoint.
enum GrowingModelPrompts {
    struct Prompt: Sendable {
        let id: String
        let text: String
    }

    static let defaults: [Prompt] = [
        Prompt(id: "week_focus",     text: "What should I work on this week?"),
        Prompt(id: "birthday_msg",   text: "Write a one-line birthday message for a friend."),
        Prompt(id: "perfect_sunday", text: "Describe your perfect Sunday.")
    ]
}
