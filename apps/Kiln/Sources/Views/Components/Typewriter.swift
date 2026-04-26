import SwiftUI

/// Type-on view modifier. Per DESIGN.md §Motion rule 4, type-on/erase is the
/// **canonical content arrival animation** — not a generic skeleton shimmer.
/// Used for advisor messages, before/after, growing model, chat replies.
///
/// Variable cadence per the design package's `proto-motion.js`: 14ms/char
/// default, longer pauses on punctuation (`.` 220ms, `,` 90ms, `?!` 200ms,
/// `\n` 320ms, ` ` rate+5ms). Reduce Motion → write the final string
/// immediately and skip the whole animation.
///
/// ## Usage
/// ```swift
/// Text(typewriter.revealed)
///     .font(Kiln.Font.body)
///     .foregroundStyle(Kiln.Palette.onSurface)
///
/// // Trigger a reveal:
/// .task(id: targetText) {
///     await typewriter.reveal(targetText, rate: 14)
/// }
/// ```
@Observable
@MainActor
final class TypewriterModel {
    /// What's currently rendered. Grows char-by-char during a reveal.
    private(set) var revealed: String = ""
    /// True while a reveal is in flight. Useful for cursor blinkers.
    private(set) var isTyping: Bool = false

    private var currentTask: Task<Void, Never>?

    /// Reveal `text` one character at a time. Awaiting this returns when the
    /// last character has been rendered (or the call has been cancelled by
    /// a subsequent `reveal` / `setImmediate`).
    /// - Parameters:
    ///   - text: target string.
    ///   - rate: base ms-per-character. Punctuation pauses are absolute.
    ///   - reduceMotion: pass `@Environment(\.accessibilityReduceMotion)`;
    ///     when `true`, the function writes `text` immediately and returns.
    func reveal(_ text: String,
                rate: Int = 14,
                reduceMotion: Bool = false) async {
        currentTask?.cancel()
        if reduceMotion {
            revealed = text
            isTyping = false
            return
        }

        let task = Task<Void, Never> { [weak self] in
            guard let self else { return }
            self.revealed = ""
            self.isTyping = true
            for char in text {
                if Task.isCancelled { return }
                self.revealed.append(char)
                let delayMs: Int
                switch char {
                case ".":               delayMs = 220
                case "?", "!":          delayMs = 200
                case ",":               delayMs = 90
                case "\n":              delayMs = 320
                case " ":               delayMs = rate + 5
                default:                delayMs = rate
                }
                try? await Task.sleep(for: .milliseconds(delayMs))
            }
            self.isTyping = false
        }
        currentTask = task
        await task.value
    }

    /// Erase the currently revealed string right-to-left at ~12ms/char per
    /// the design package's "fade then erase right→left" Growing-Model
    /// pattern. Awaits until empty.
    func erase(reduceMotion: Bool = false) async {
        currentTask?.cancel()
        if reduceMotion {
            revealed = ""
            isTyping = false
            return
        }

        let task = Task<Void, Never> { [weak self] in
            guard let self else { return }
            self.isTyping = true
            while !self.revealed.isEmpty {
                if Task.isCancelled { return }
                self.revealed.removeLast()
                try? await Task.sleep(for: .milliseconds(12))
            }
            self.isTyping = false
        }
        currentTask = task
        await task.value
    }

    /// Set the revealed string without animation. Useful for previews and
    /// for resetting state at unmount.
    func setImmediate(_ text: String) {
        currentTask?.cancel()
        revealed = text
        isTyping = false
    }

    /// Cancel any in-flight reveal/erase without changing the visible text.
    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        isTyping = false
    }
}

/// Inline blinking cursor — appears at the trailing edge of typewritten text
/// while `isTyping == true`. 540ms blink period. Reduce Motion → static
/// underscore (no blink), so screen readers don't announce a flicker.
struct TypewriterCursor: View {
    let isVisible: Bool

    @State private var blinkPhase: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text("|")
            .font(Kiln.Font.body)
            .foregroundStyle(Kiln.Palette.firing)
            .opacity(opacity)
            .onAppear { startBlink() }
            .accessibilityHidden(true)
    }

    private var opacity: Double {
        guard isVisible else { return 0 }
        if reduceMotion { return 1 }
        return blinkPhase ? 1 : 0.2
    }

    private func startBlink() {
        guard !reduceMotion else { return }
        withAnimation(Kiln.Motion.cursorBlink) {
            blinkPhase = true
        }
    }
}
