import SwiftUI

/// Subtle respiring amber glow for firing moments: empty drop zone at launch,
/// training progress, export CTA. Opacity 0.9↔1.0 over 1.8s. Degrades to a
/// flat accent stroke when Reduce Motion is on.
struct EmberGlow: ViewModifier {
    var cornerRadius: CGFloat = Kiln.Radius.modal
    var lineWidth: CGFloat = 1.25
    var glowRadius: CGFloat = 28

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Kiln.Palette.firing, lineWidth: lineWidth)
                    .opacity(pulsing ? 1.0 : 0.9)
            }
            .shadow(color: Kiln.Palette.firing.opacity(pulsing ? 0.45 : 0.18),
                    radius: glowRadius)
            .onAppear {
                guard !reduceMotion, !pulsing else { return }
                withAnimation(Kiln.Motion.glow) { pulsing = true }
            }
    }
}

extension View {
    func emberGlow(cornerRadius: CGFloat = Kiln.Radius.modal,
                   lineWidth: CGFloat = 1.25,
                   glowRadius: CGFloat = 28) -> some View {
        modifier(EmberGlow(cornerRadius: cornerRadius,
                           lineWidth: lineWidth,
                           glowRadius: glowRadius))
    }
}
