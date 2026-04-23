import SwiftUI

/// Middle pane — routes based on the selected project's stage. Each stage
/// gets a dedicated polished view; the switch animates with Kiln.Motion
/// .stageTransition when the stage id changes.
struct StageRouterView: View {
    let model: AppModel

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea()

            if let project = model.selectedProject {
                stage(for: project)
                    .id("\(project.id)-\(project.stage.rawValue)")
                    .transition(Kiln.Motion.stageTransition)
            } else {
                EmptyState(
                    systemImage: "sidebar.left",
                    headline: "Pick a project from the sidebar.",
                    context: "Or press ⌘N to start a new one."
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func stage(for project: Project) -> some View {
        switch project.stage {
        case .readyToDrop:
            ReadyStageView(project: project) { url in
                withAnimation(Kiln.Motion.standard) {
                    model.ingest(folderURL: url)
                }
            }
        case .preparing:
            PrepareStageView(project: project)
        case .training:
            TrainStageView(project: project)
        case .complete:
            CompleteStageView(project: project)
        }
    }
}
