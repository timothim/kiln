import SwiftUI

/// Middle pane — routes based on the selected project's stage. Each stage
/// gets a dedicated polished view; the switch animates with Kiln.Motion
/// .stageTransition when the stage id changes.
struct StageRouterView: View {
    let model: AppModel

    var body: some View {
        ZStack {
            // Paper canvas — DESIGN.md "stage" sits directly on `--paper`.
            // No regularMaterial: paper is light enough that the system blur
            // would just grey it out.
            Kiln.Palette.paper
                .ignoresSafeArea()

            if let project = model.selectedProject {
                VStack(spacing: 0) {
                    contextBadge(for: project)
                    stage(for: project)
                        .id("\(project.id)-\(project.stage.rawValue)")
                        .transition(Kiln.Motion.stageTransition)
                }
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

    /// Mono context badge that sits above the active stage — DESIGN.md
    /// title-bar pattern adapted for the in-window center pane.
    /// Reads as "TRAINING · iter 200/500" or "READY" depending on stage.
    private func contextBadge(for project: Project) -> some View {
        HStack(spacing: Kiln.Space.s2) {
            Text(project.stage.label.uppercased())
                .font(Kiln.Font.eyebrow)
                .kerning(0.4)
                .foregroundStyle(Kiln.Palette.onSurface3)
            if let detail = stageBadgeDetail(for: project) {
                Text("·")
                    .font(Kiln.Font.eyebrow)
                    .foregroundStyle(Kiln.Palette.onSurface4)
                Text(detail)
                    .font(Kiln.Font.eyebrow)
                    .kerning(0.4)
                    .foregroundStyle(Kiln.Palette.onSurface3)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Kiln.Space.s6)
        .padding(.vertical, Kiln.Space.s3)
        .frame(maxWidth: .infinity)
        .background(Kiln.Palette.paper)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Kiln.Palette.hairline)
                .frame(height: 1)
        }
    }

    private func stageBadgeDetail(for project: Project) -> String? {
        switch project.stage {
        case .readyToDrop: return nil
        case .preparing:
            if let total = project.totalChunks, total > 0 {
                return "\(total.formatted()) chunks"
            }
            return nil
        case .training:
            if let trainModel = model.trainModel,
               case .running = trainModel.status,
               let progress = trainModel.currentProgress {
                let total = trainModel.totalIters ?? 0
                return total > 0
                    ? "iter \(progress.iter)/\(total)"
                    : "iter \(progress.iter)"
            }
            return nil
        case .complete: return project.name
        }
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
                },
                // Audit C3: gated on apiKeyConfigured. The dry-run path
                // (what we currently ship) does not actually call
                // Anthropic, but having a key configured is the user's
                // explicit opt-in signal for any cloud-shaped feature.
                onOpenDeepCuration: model.cloudSettings.apiKeyConfigured
                    ? { model.openDeepCuration(for: project.id) }
                    : nil,
                deepCurationModel: model.deepCurationModel,
                onCloseDeepCuration: { model.closeDeepCuration() }
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
