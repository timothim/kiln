import SwiftUI

/// Right pane — routes by stage. Mirrors the center router's transition so
/// the detail slides into place alongside the stage view.
struct DetailView: View {
    let project: Project?

    var body: some View {
        ZStack {
            if let project {
                view(for: project)
                    .id("\(project.id)-\(project.stage.rawValue)-detail")
                    .transition(Kiln.Motion.stageTransition)
            } else {
                DetailEmptyView(
                    headline: "Pick a project to see its details.",
                    context: nil
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func view(for project: Project) -> some View {
        switch project.stage {
        case .readyToDrop:
            DetailEmptyView()
        case .preparing:
            PrepareDetailView()
        case .training:
            LogsPanel(project: project)
        case .complete:
            CompleteDetailView(project: project)
        }
    }
}
