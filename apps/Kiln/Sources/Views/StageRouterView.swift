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
            PrepareStageView(
                project: project,
                model: model.prepareModel,
                onCancel: { model.cancelPrepare() },
                onContinue: {
                    withAnimation(Kiln.Motion.standard) {
                        model.continueToTraining(projectID: project.id)
                    }
                },
                onReset: {
                    withAnimation(Kiln.Motion.standard) {
                        model.resetPrepare()
                        model.updateStage(of: project.id, to: .readyToDrop)
                    }
                }
            )
        case .training:
            TrainStageView(
                project: project,
                model: model.trainModel,
                exportModel: model.exportModel,
                onStart: { split in
                    model.startTraining(projectID: project.id, voiceSplit: split)
                },
                onCancel: { model.cancelTraining() },
                onContinue: {
                    withAnimation(Kiln.Motion.standard) {
                        model.continueFromTraining(projectID: project.id)
                    }
                },
                onReset: {
                    withAnimation(Kiln.Motion.standard) {
                        model.resetTraining()
                    }
                },
                onExport: { model.startExport(projectID: project.id) },
                onDismissExport: { model.dismissExport() }
            )
        case .complete:
            CompleteStageView(
                project: project,
                chatModel: model.chatModel,
                onOpenChat: { model.openChat(for: project.id) },
                onCloseChat: { model.closeChat() },
                onOpenVoiceCoach: model.cloudSettings.voiceCoachEnabled
                    ? { model.openVoiceCoach(for: project.id) }
                    : nil,
                voiceCoachModel: model.voiceCoachModel,
                voiceCoachInput: model.voiceCoachInput,
                onCloseVoiceCoach: { model.closeVoiceCoach() }
            )
        }
    }
}
