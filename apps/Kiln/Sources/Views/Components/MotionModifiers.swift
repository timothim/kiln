import SwiftUI

/// View modifiers that thread `@Environment(\.accessibilityReduceMotion)`
/// through every animation site so motion becomes opt-in for users with
/// the system-level Reduce Motion preference enabled.
///
/// DESIGN.md §Motion: "Reduce Motion honored: the ember glow degrades to a
/// static accent." This is the canonical implementation of that rule for
/// every other animation in the app — call sites use `.kilnMotion(token,
/// value: state)` instead of `.animation(token, value: state)` so the
/// Reduce Motion gate is always wired in.

extension View {
    /// Apply `animation` only when the user has Reduce Motion turned off.
    /// Mirrors the `.animation(_:value:)` API exactly so this is a
    /// drop-in replacement at any animation site.
    func kilnMotion<V: Equatable>(_ animation: Animation,
                                  value: V) -> some View {
        modifier(KilnMotionModifier(animation: animation, value: value))
    }

    /// Apply `transition` only when Reduce Motion is off. With Reduce
    /// Motion on, the view appears/disappears instantly. Used for stage
    /// transitions, sheet content swaps, etc.
    func kilnTransition(_ transition: AnyTransition) -> some View {
        modifier(KilnTransitionModifier(transition: transition))
    }
}

private struct KilnMotionModifier<V: Equatable>: ViewModifier {
    let animation: Animation
    let value: V

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        // SwiftUI's `.animation(_:value:)` accepts an optional Animation;
        // passing nil disables the implicit animation for that value's
        // changes — exactly the Reduce Motion semantic.
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

private struct KilnTransitionModifier: ViewModifier {
    let transition: AnyTransition

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.transition(reduceMotion ? .identity : transition)
    }
}

/// Helper for `withAnimation` calls that don't have a SwiftUI value to
/// bind to (e.g. one-shot reveals from `.onAppear`). Returns the supplied
/// animation when Reduce Motion is off, `nil` otherwise — pass to
/// `withAnimation` and the call becomes a no-op for users who opted out.
@MainActor
enum KilnMotion {
    static func respecting(_ animation: Animation,
                           reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}
