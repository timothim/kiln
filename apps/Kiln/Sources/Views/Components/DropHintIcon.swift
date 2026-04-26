import SwiftUI

/// The drop-zone hero glyph from the Claude Design package's `drop` surface
/// (`proto-surfaces.js:103-108` + `proto-styles.css:254-261`):
///
///   `.ember`   — 80×80 div with `radial-gradient(circle, --firing-wash 0%,
///                transparent 70%)`, alpha-pulsing 0.25 → 1 over 1.8s.
///   `.dz-icon` — `◇` Unicode rhombus character (U+25C7), 32pt serif in
///                `--firing`, with `margin-top: -68px` so it overlaps the
///                ember (the ember sits behind, the rhombus sits over it).
///
/// Rendered together they read as: "the kiln-mouth glowing." Reduce Motion
/// freezes the alpha at 1.
struct DropHintIcon: View {
    @State private var isPulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // The ember — radial-gradient circle, 80×80, alpha-only pulse.
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(stops: [
                            .init(color: Kiln.Palette.firingWash, location: 0.0),
                            .init(color: Color.clear,              location: 0.7),
                        ]),
                        center: .center,
                        startRadius: 0,
                        endRadius: 40
                    )
                )
                .frame(width: 80, height: 80)
                .opacity(reduceMotion ? 1.0 : (isPulsing ? 1.0 : 0.25))

            // ◇ rhombus character — 32pt serif, firing-colored, sitting
            // above (overlapping) the ember disc.
            Text("◇")
                .font(.system(size: 32, weight: .regular, design: .serif))
                .foregroundStyle(Kiln.Palette.firing)
                .offset(y: -34)
        }
        .frame(width: 80, height: 80)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(Kiln.Motion.ember) {
                isPulsing = true
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview("DropHintIcon — ember + rhombus") {
    DropHintIcon()
        .padding(80)
        .background(Kiln.Palette.paper)
}
