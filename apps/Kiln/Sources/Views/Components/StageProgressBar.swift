import SwiftUI

/// Thin horizontal fill bar bound to the live stage fraction.
/// Uses Kiln.Palette.firing over accentWash; width animates with Kiln.Motion.standard.
struct StageProgressBar: View {
    let fraction: Double
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                    .fill(Kiln.Palette.firingWash)
                RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                    .fill(Kiln.Palette.firing)
                    .frame(width: clamped(geo.size.width))
                    .animation(Kiln.Motion.standard, value: clamped(geo.size.width))
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("Stage progress")
        .accessibilityValue("\(Int(round(fraction * 100))) percent")
    }

    private func clamped(_ width: CGFloat) -> CGFloat {
        let f = min(max(fraction, 0), 1)
        return max(0, width * CGFloat(f))
    }
}
