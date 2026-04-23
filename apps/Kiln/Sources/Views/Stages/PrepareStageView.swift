import SwiftUI
import KilnCore

/// Stage 1 — dispatches between running / cancelling / completed / failed
/// based on the PrepareModel's status. Falls back to the quiet reading
/// indicator if no PrepareModel has been attached yet (edge: re-hydration).
struct PrepareStageView: View {
    let project: Project
    var model: PrepareModel?
    let onCancel: () -> Void
    let onContinue: () -> Void
    let onReset: () -> Void

    var body: some View {
        Group {
            if let model {
                switch model.status {
                case .idle:
                    quietReading
                        .transition(Kiln.Motion.stageTransition)
                case .running:
                    IngestProgressView(project: project, model: model, onCancel: onCancel)
                        .transition(Kiln.Motion.stageTransition)
                case .cancelling:
                    CancellingOverlay(
                        underlying: IngestProgressView(project: project, model: model, onCancel: onCancel)
                    )
                    .transition(Kiln.Motion.stageTransition)
                case .completed(let report):
                    DatasetDoctorView(
                        project: project,
                        report: report,
                        onContinue: onContinue,
                        onReset: onReset
                    )
                    .transition(Kiln.Motion.stageTransition)
                case .failed(let error):
                    IngestErrorView(project: project, error: error, onReset: onReset)
                        .transition(Kiln.Motion.stageTransition)
                }
            } else {
                quietReading
                    .transition(Kiln.Motion.stageTransition)
            }
        }
        .animation(Kiln.Motion.standard, value: statusKey)
    }

    private var statusKey: String {
        guard let model else { return "nil" }
        switch model.status {
        case .idle:       return "idle"
        case .running:    return "running"
        case .cancelling: return "cancelling"
        case .completed:  return "completed"
        case .failed:     return "failed"
        }
    }

    private var quietReading: some View {
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
                HStack(spacing: Kiln.Space.xxs) {
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
