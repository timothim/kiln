import SwiftUI

/// Full-window launch view. Implements the Claude Design package's `drop`
/// surface (Tier S) — `proto-surfaces.js:103-108` + the `.drop-zone` CSS at
/// `proto-styles.css:242-272`.
///
/// Visual recipe:
///   - Surface fills 78% × 78% of the canvas, capped at 720 × 460.
///   - 1.5px **dashed** border in `--on-surface-4` (warm tertiary brown,
///     NOT firing) when empty — firing comes only on `targeted`.
///   - Background `--surface` (pure white). Becomes `--firing-wash` when
///     targeted, with a solid `--firing` border + scale 1.005.
///   - Center stack: `DropHintIcon` (ember disc + ◇ rhombus), then a serif
///     28pt `<h2>` headline, then a mono 12pt `--on-surface-3` sub-line.
///
/// Copy by state (per `proto-surfaces.js:144-178`):
///   - empty:    "Drop a folder. Meet yourself."  /  "~/Documents/notes"
///   - targeted: "Release to begin."               /  "~/Documents/notes — folder · 1,247 items"
///   - received: "Reading your folder."            /  "<n> chunks read"
///   - refused:  shake + danger sub-text
struct EmptyDropView: View {
    let model: AppModel

    @State private var isTargeted = false

    var body: some View {
        ZStack {
            Kiln.Palette.paper.ignoresSafeArea()
            GeometryReader { geo in
                let w = min(720, geo.size.width  * 0.78)
                let h = min(460, geo.size.height * 0.78)
                dropZone
                    .frame(width: w, height: h)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var dropZone: some View {
        VStack(spacing: 10) {
            DropHintIcon()
            Text(headline)
                // 28pt serif, weight 500, letter-spacing -0.012em
                .font(.system(size: 28, weight: .medium, design: .serif))
                .tracking(-0.34)
                .foregroundStyle(Kiln.Palette.onSurface)
                .multilineTextAlignment(.center)
            Text(subline)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Kiln.Palette.onSurface3)
        }
        .padding(Kiln.Space.s6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: Kiln.Radius.rLg, style: .continuous)
                .fill(isTargeted ? Kiln.Palette.firingWash : Kiln.Palette.surface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Kiln.Radius.rLg, style: .continuous)
                .strokeBorder(
                    // Dashed `on-surface-4` warm tertiary in empty;
                    // solid `firing` when armed.
                    isTargeted ? Kiln.Palette.firing : Kiln.Palette.onSurface4,
                    style: StrokeStyle(
                        lineWidth: 1.5,
                        dash: isTargeted ? [] : [6, 4]
                    )
                )
        }
        .scaleEffect(isTargeted ? 1.005 : 1.0)
        .animation(Kiln.Motion.std, value: isTargeted)
        .dropFolder(isTargeted: $isTargeted) { url in
            withAnimation(Kiln.Motion.kind) {
                model.ingest(folderURL: url)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(headline)
        .accessibilityHint(subline)
        .accessibilityAddTraits(.isButton)
    }

    private var headline: String {
        isTargeted ? "Release to begin." : "Drop a folder. Meet yourself."
    }

    private var subline: String {
        isTargeted ? "~/Documents/notes — folder" : "~/Documents/notes"
    }
}

#Preview("Drop zone — empty") {
    EmptyDropView(model: AppModel())
        .frame(width: 1280, height: 800)
}
