import SwiftUI

/// Stage 0 — project exists but has no folder yet. Drop surface per the
/// Claude Design package's `drop` Tier-S surface: 480×280 panel sitting on
/// `paper`, dashed `firing` border in empty state, solid `firing` border +
/// `firing-wash` fill in targeted state, corner `EmberDot` for the alive
/// signal. Dropping a folder promotes the project to `.preparing`.
struct ReadyStageView: View {
    let project: Project
    let onDropFolder: (URL) -> Void

    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.s6) {
            StageHeader(
                title: project.name,
                subtitle: "No folder yet. Drop one here to begin.",
                stage: project.stage
            )

            HStack {
                Spacer(minLength: 0)
                dropCard
                Spacer(minLength: 0)
            }
            .padding(.top, Kiln.Space.s4)

            Spacer(minLength: 0)
        }
        .padding(Kiln.Space.s7)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var dropCard: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: Kiln.Space.s3) {
                Spacer(minLength: 0)
                Text("Drop a folder of your writing.")
                    .font(Kiln.Font.display)
                    .foregroundStyle(Kiln.Palette.onSurface)
                    .multilineTextAlignment(.center)
                Text("Notes, messages, journal — anything in your voice.")
                    .font(Kiln.Font.body)
                    .foregroundStyle(Kiln.Palette.onSurface2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(Kiln.Space.s7)
            .frame(width: 480, height: 280)
            .background {
                RoundedRectangle(cornerRadius: Kiln.Radius.r5, style: .continuous)
                    .fill(isTargeted
                          ? Kiln.Palette.firingWash
                          : Kiln.Palette.surface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Kiln.Radius.r5, style: .continuous)
                    .strokeBorder(
                        Kiln.Palette.firing,
                        style: StrokeStyle(
                            // Solid 2px in targeted reads as "armed";
                            // dashed 1.5px in empty reads as invitation.
                            lineWidth: isTargeted ? 2.0 : 1.5,
                            dash: isTargeted ? [] : [6, 4]
                        )
                    )
            }
            // Corner glyph — alpha-pulsing 7pt firing dot top-right.
            EmberDot(size: 7)
                .padding(Kiln.Space.s4)
        }
        .scaleEffect(isTargeted ? 1.04 : 1.0)
        .animation(Kiln.Motion.kind, value: isTargeted)
        .dropFolder(isTargeted: $isTargeted, onDrop: onDropFolder)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Drop a folder of your writing")
        .accessibilityHint("Drag a folder onto this zone to begin training.")
        .accessibilityAddTraits(.isButton)
    }
}
