import SwiftUI

/// 7-pt firing dot that breathes via `Kiln.Motion.glow` (the canonical
/// `t-ember` 1.8s alpha pulse). Used wherever the model is "alive": the
/// training chip, the kiln-noor eyebrow, the advisor pill, the live status
/// dot in the MCP server settings.
///
/// Per DESIGN.md §Motion rule 2: **Alpha, not scale, for "alive."** Scale
/// pulses read as alerts; alpha pulses read as life. Reduce Motion → static
/// dot at full opacity.
struct EmberDot: View {
    /// Diameter in points. Defaults to 7pt per the design spec.
    var size: CGFloat = 7

    @State private var isPulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(Kiln.Palette.firing)
            .frame(width: size, height: size)
            .opacity(reduceMotion ? 1.0 : (isPulsing ? 1.0 : 0.55))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(Kiln.Motion.ember) {
                    isPulsing = true
                }
            }
            .accessibilityHidden(true)
    }
}

#Preview("EmberDot — default") {
    HStack(spacing: Kiln.Space.s4) {
        EmberDot()
        EmberDot(size: 10)
        EmberDot(size: 14)
    }
    .padding(Kiln.Space.s6)
    .background(Kiln.Palette.paper)
}
