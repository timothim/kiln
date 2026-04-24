import SwiftUI

/// Stage 0 — project exists but has no folder yet. Inline drop target with
/// ember glow. Dropping a folder promotes the project to `.preparing`.
struct ReadyStageView: View {
    let project: Project
    let onDropFolder: (URL) -> Void

    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.l) {
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
            .padding(.top, Kiln.Space.m)

            Spacer(minLength: 0)
        }
        .padding(Kiln.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var dropCard: some View {
        VStack(spacing: Kiln.Space.m) {
            DropHintIcon()
            Text("Drop a folder")
                .font(Kiln.Font.title)
                .foregroundStyle(.primary)
            Text("Notes, messages, writing — whatever sounds like you.")
                .font(Kiln.Font.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .padding(.horizontal, Kiln.Space.xl)
        .padding(.vertical, Kiln.Space.xl)
        .frame(maxWidth: 420)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: Kiln.Radius.card, style: .continuous)
                    .fill(.regularMaterial)
                if isTargeted {
                    RoundedRectangle(cornerRadius: Kiln.Radius.card, style: .continuous)
                        .fill(Kiln.Palette.firingWash)
                }
            }
        }
        .emberGlow(cornerRadius: Kiln.Radius.card, glowRadius: 20)
        .scaleEffect(isTargeted ? 1.01 : 1.0)
        .animation(Kiln.Motion.standard, value: isTargeted)
        .dropFolder(isTargeted: $isTargeted, onDrop: onDropFolder)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Drop a folder to begin")
        .accessibilityAddTraits(.isButton)
    }
}
