import SwiftUI

/// Post-it card per DESIGN.md `post-it-card` component spec. Used for the
/// Training Advisor and the Voice Coach — both contexts where Opus's text
/// arrives as an "annotation" on top of the user's run, not as a primary
/// surface in its own right.
///
/// Visual recipe:
///   - `surface-paper` fill — slightly warmer than `surface` so the card
///     reads as paper-on-paper, like a Post-it note stuck onto the page.
///   - Hairline border — same as a regular card.
///   - **Folded corner** at the top-right — a 16×16 triangle drawn as a
///     SwiftUI `Path`, filled with `paper` so it appears to "show through"
///     to the canvas underneath. The fold uses a subtle inner shadow line
///     (`hairline-2`) so it reads as 3D paper rather than a flat cutout.
///   - No drop shadow.
struct PostItCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    /// Size of the folded corner triangle in points. 16pt matches the
    /// design's CSS-trick `border-color` corner width.
    private let cornerSize: CGFloat = 16

    var body: some View {
        content()
            .padding(Kiln.Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                postItBackground
            }
    }

    private var postItBackground: some View {
        ZStack(alignment: .topTrailing) {
            // Card surface, with the top-right corner "folded back" via a
            // mask Path that excludes the triangular fold area.
            RoundedRectangle(cornerRadius: Kiln.Radius.r3, style: .continuous)
                .fill(Kiln.Palette.surfacePaper)
                .mask {
                    cardMask
                }
                .overlay {
                    RoundedRectangle(cornerRadius: Kiln.Radius.r3, style: .continuous)
                        .stroke(Kiln.Palette.hairline, lineWidth: 1)
                        .mask { cardMask }
                }

            // The folded-flap shape — a small triangle in the top-right
            // that picks up the paper background, with a subtle hairline
            // edge along the diagonal so it reads as a fold.
            foldShape
        }
    }

    /// Mask path that's the full card minus the upper-right triangle
    /// (the fold). Achieves the "torn-corner" look without overdraw.
    private var cardMask: some View {
        GeometryReader { geo in
            Path { path in
                let r = Kiln.Radius.r3
                let w = geo.size.width
                let h = geo.size.height
                let foldX = w - cornerSize
                let foldY: CGFloat = 0
                // Start at (foldX, 0), trace along the top to the
                // top-left corner, down the left side, across the bottom,
                // up the right side to the diagonal of the fold, then
                // close by drawing diagonally to the start.
                path.move(to: CGPoint(x: foldX, y: foldY))
                path.addLine(to: CGPoint(x: r, y: 0))
                path.addArc(center: CGPoint(x: r, y: r),
                            radius: r,
                            startAngle: .degrees(270),
                            endAngle: .degrees(180),
                            clockwise: true)
                path.addLine(to: CGPoint(x: 0, y: h - r))
                path.addArc(center: CGPoint(x: r, y: h - r),
                            radius: r,
                            startAngle: .degrees(180),
                            endAngle: .degrees(90),
                            clockwise: true)
                path.addLine(to: CGPoint(x: w - r, y: h))
                path.addArc(center: CGPoint(x: w - r, y: h - r),
                            radius: r,
                            startAngle: .degrees(90),
                            endAngle: .degrees(0),
                            clockwise: true)
                path.addLine(to: CGPoint(x: w, y: cornerSize))
                path.addLine(to: CGPoint(x: foldX, y: foldY))
                path.closeSubpath()
            }
            .fill(Color.black) // mask uses opacity, color is irrelevant
        }
    }

    /// The folded triangle — appears to be the paper "flap" turned up,
    /// showing the canvas behind. Drawn over the card with a hairline
    /// along the fold's diagonal.
    private var foldShape: some View {
        Canvas { context, size in
            let foldRect = CGRect(x: size.width - cornerSize,
                                  y: 0,
                                  width: cornerSize,
                                  height: cornerSize)
            // Triangular fill — the paper underneath shows through.
            var triangle = Path()
            triangle.move(to: CGPoint(x: foldRect.minX, y: foldRect.minY))
            triangle.addLine(to: CGPoint(x: foldRect.maxX, y: foldRect.minY))
            triangle.addLine(to: CGPoint(x: foldRect.maxX, y: foldRect.maxY))
            triangle.closeSubpath()
            // (No fill — we want to see the canvas/paper background through here.)
            // Hairline along the diagonal.
            var diagonal = Path()
            diagonal.move(to: CGPoint(x: foldRect.minX, y: foldRect.minY))
            diagonal.addLine(to: CGPoint(x: foldRect.maxX, y: foldRect.maxY))
            context.stroke(diagonal, with: .color(Kiln.Palette.hairline), lineWidth: 1)
        }
        .frame(width: cornerSize, height: cornerSize, alignment: .topTrailing)
        .offset(x: 0, y: 0)
        .allowsHitTesting(false)
    }
}

#Preview("PostItCard — Training Advisor") {
    VStack(alignment: .leading, spacing: Kiln.Space.s4) {
        PostItCard {
            VStack(alignment: .leading, spacing: Kiln.Space.s3) {
                HStack(spacing: Kiln.Space.s2) {
                    Chip(text: "VOICE COACH IS WATCHING", isFiring: true)
                    Spacer()
                    Text("iter 200")
                        .font(Kiln.Font.eyebrow)
                        .kerning(0.4)
                        .foregroundStyle(Kiln.Palette.onSurface3)
                }
                Text("The model is starting to find your rhythm — short clauses landing, semicolons doing real work. Loss is still trending down; another epoch and the email opener will read as you wrote it.")
                    .font(Kiln.Font.body)
                    .foregroundStyle(Kiln.Palette.onSurface)
                    .fixedSize(horizontal: false, vertical: true)
                Text("CLAUDE OPUS 4.7 · $0.18")
                    .font(Kiln.Font.eyebrow)
                    .kerning(0.4)
                    .foregroundStyle(Kiln.Palette.onSurface3)
            }
        }
    }
    .padding(Kiln.Space.s7)
    .frame(width: 540)
    .background(Kiln.Palette.paper)
}
