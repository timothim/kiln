import SwiftUI

/// Shared header for stage views in the center pane.
/// Title + stage badge in one row; optional secondary line below.
struct StageHeader: View {
    let title: String
    var subtitle: String? = nil
    let stage: ProjectStage

    var body: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.s2) {
            HStack(spacing: Kiln.Space.s3) {
                Text(title)
                    .font(Kiln.Font.display)
                    .foregroundStyle(Kiln.Palette.onSurface)
                    .lineLimit(1)
                    .truncationMode(.tail)

                StageBadge(stage: stage)

                Spacer(minLength: 0)
            }

            if let subtitle {
                Text(subtitle)
                    .font(Kiln.Font.body)
                    .foregroundStyle(Kiln.Palette.onSurface2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
