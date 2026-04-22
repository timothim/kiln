import SwiftUI

/// Stage 1 — reading the dropped folder. Calm header + ember reading line.
/// No spinner, no fake progress bar: liveness through opacity pulse only.
struct PrepareStageView: View {
    let project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.m) {
            StageHeader(
                title: project.name,
                subtitle: "Reading your folder.",
                stage: project.stage
            )

            ReadingIndicator()
                .frame(maxWidth: 320)
                .padding(.top, Kiln.Space.xs)

            if let folder = project.folderName {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(Kiln.Font.caption)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                    Text(folder)
                        .font(Kiln.Font.mono)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, Kiln.Space.xs)
            }

            Spacer(minLength: 0)
        }
        .padding(Kiln.Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
