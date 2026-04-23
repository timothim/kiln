import SwiftUI

/// Calm indeterminate line used while a folder is being read. Opacity pulses
/// 0.5↔1.0 in place of a moving bar — liveness without false precision.
struct ReadingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        Capsule(style: .continuous)
            .fill(Kiln.Palette.firing)
            .frame(height: 2)
            .opacity(reduceMotion ? 0.85 : (pulsing ? 1.0 : 0.5))
            .shadow(color: Kiln.Palette.firing.opacity(pulsing ? 0.35 : 0.15), radius: 10)
            .onAppear {
                guard !reduceMotion, !pulsing else { return }
                withAnimation(Kiln.Motion.glow) { pulsing = true }
            }
            .accessibilityLabel("Reading in progress")
    }
}
