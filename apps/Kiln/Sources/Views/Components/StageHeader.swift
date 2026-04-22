import SwiftUI

/// Shared header for stage views in the center pane.
/// Title + stage badge in one row; optional secondary line below.
struct StageHeader: View {
    let title: String
    var subtitle: String? = nil
    let stage: ProjectStage

    var body: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.xs) {
            HStack(spacing: Kiln.Space.xs) {
                Text(title)
                    .font(Kiln.Font.display)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                StageBadge(stage: stage)

                Spacer(minLength: 0)
            }

            if let subtitle {
                Text(subtitle)
                    .font(Kiln.Font.body)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
