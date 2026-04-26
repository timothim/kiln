import SwiftUI

/// Right pane — routes by stage. Mirrors the center router's transition so
/// the detail slides into place alongside the stage view.
struct DetailView: View {
    let project: Project?
    /// Audit C5: thread the AppModel down so the Complete detail pane
    /// can resolve a per-project ``SamplePreviewModel``. Optional so
    /// existing callers / previews that don't have an AppModel still
    /// compile (the Complete view falls back to a no-runner panel).
    var model: AppModel? = nil

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
            LogsPanel(project: project, trainModel: model?.trainModel)
        case .complete:
            CompleteDetailView(
                project: project,
                samplePreviewModel: model?.samplePreviewModel(for: project.id)
            )
        }
    }
}
