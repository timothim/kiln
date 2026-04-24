import SwiftUI

/// Sidebar row for a single project. Shows name, model size, and last-trained
/// relative timestamp (or "not trained"). Badge carries the current stage.
struct ProjectCard: View {
    let project: Project
    var isSelected: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: Kiln.Space.xs) {
            VStack(alignment: .leading, spacing: Kiln.Space.xxs) {
                Text(project.name)
                    .font(Kiln.Font.body)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .truncationMode(.tail)

                HStack(spacing: 6) {
                    Text(project.modelSize.displayName)
                        .font(Kiln.Font.caption)
                        .foregroundStyle(.secondary)

                    Text("·")
                        .font(Kiln.Font.caption)
                        .foregroundStyle(.tertiary)

                    trainedLabel
                }

                StageBadge(stage: project.stage)
                    .padding(.top, 2)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, Kiln.Space.xs - 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    @ViewBuilder
    private var trainedLabel: some View {
        if let lastTrained = project.lastTrained {
            Text(lastTrained, format: .relative(presentation: .numeric))
                .font(Kiln.Font.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("not trained")
                .font(Kiln.Font.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var accessibilitySummary: String {
        let trained = project.lastTrained.map {
            "last trained " + $0.formatted(.relative(presentation: .named))
        } ?? "not yet trained"
        return "\(project.name), model \(project.modelSize.displayName), \(project.stage.spoken), \(trained)"
    }
}
