import SwiftUI

/// Horizontal training-progress capsule. Amber fill on a low-contrast track,
/// with the skill's ember-glow: 0.9↔1.0 opacity over 1.8s, ease-in-out.
/// Reduce Motion flattens to steady 1.0 opacity.
struct TrainingProgressCapsule: View {
    /// 0.0 to 1.0
    let progress: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule(style: .continuous)
                .fill(Color.primary.opacity(Kiln.Opacity.trackFill))

            GeometryReader { proxy in
                Capsule(style: .continuous)
                    .fill(Kiln.Palette.firing)
                    .frame(width: max(12, proxy.size.width * clamped))
                    .opacity(reduceMotion ? 1.0 : (pulsing ? 1.0 : 0.9))
            }
        }
        .frame(height: 6)
        .shadow(color: Kiln.Palette.firing.opacity(pulsing ? 0.4 : 0.2), radius: 14)
        .onAppear {
            guard !reduceMotion, !pulsing else { return }
            withAnimation(Kiln.Motion.glow) { pulsing = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Training progress")
        .accessibilityValue("\(Int(clamped * 100)) percent")
    }

    private var clamped: Double { min(max(progress, 0), 1) }
}
