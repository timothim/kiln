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
                case .running:
                    IngestProgressView(project: project, model: model, onCancel: onCancel)
                case .cancelling:
                    CancellingOverlay(
                        underlying: IngestProgressView(project: project, model: model, onCancel: onCancel)
                    )
                case .completed(let report):
                    DatasetDoctorView(
                        project: project,
                        report: report,
                        onContinue: onContinue,
                        onReset: onReset
                    )
                case .failed(let error):
                    IngestErrorView(project: project, error: error, onReset: onReset)
                }
            } else {
                quietReading
            }
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
