import SwiftUI

/// Stage 0 — project exists but has no folder yet. Mirrors the launch
/// `EmptyDropView` so a project's first beat reads identically to the cold-
/// launch state. Implements the Claude Design package's `drop` surface
/// (Tier S) — see `proto-surfaces.js:103-208` + `proto-styles.css:242-272`.
///
/// Dropping a folder promotes the project to `.preparing`.
struct ReadyStageView: View {
    let project: Project
    let onDropFolder: (URL) -> Void

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
                    isTargeted ? Kiln.Palette.firing : Kiln.Palette.onSurface4,
                    style: StrokeStyle(
                        lineWidth: 1.5,
                        dash: isTargeted ? [] : [6, 4]
                    )
                )
        }
        .scaleEffect(isTargeted ? 1.005 : 1.0)
        .animation(Kiln.Motion.std, value: isTargeted)
        .dropFolder(isTargeted: $isTargeted, onDrop: onDropFolder)
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
