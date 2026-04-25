import SwiftUI
import KilnCore

/// Compact four-stage progress strip used by the export CTA on the train-
/// completed view. Stages advance left-to-right; the currently active one
/// shows the amber firing accent, completed ones show a checkmark, failed
/// ones a red X.
struct ExportProgressView: View {
    let progress: ExportModel.Progress

    var body: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.xs) {
            HStack(spacing: Kiln.Space.m) {
                stageRow(name: "Fuse adapter", state: progress.fuse)
                stageRow(name: "Convert GGUF", state: progress.gguf)
                stageRow(name: "Modelfile", state: progress.modelfile)
                stageRow(name: "Install in Ollama", state: progress.ollama)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(voiceOverLabel)
    }

    @ViewBuilder
    private func stageRow(name: String, state: ExportModel.StageState) -> some View {
        HStack(spacing: Kiln.Space.xxs) {
            glyph(for: state)
                .frame(width: 14, height: 14)
            Text(name)
                .font(Kiln.Font.caption)
                .foregroundStyle(foreground(for: state))
        }
        .padding(.horizontal, Kiln.Space.xs)
        .padding(.vertical, Kiln.Space.xxs)
        .background {
            RoundedRectangle(cornerRadius: Kiln.Radius.control, style: .continuous)
                .fill(background(for: state))
        }
    }

    @ViewBuilder
    private func glyph(for state: ExportModel.StageState) -> some View {
        switch state {
        case .pending:
            Circle()
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
        case .running:
            Circle()
                .fill(Kiln.Palette.firing)
                .opacity(0.85)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(Kiln.Palette.danger)
        }
    }

    private func foreground(for state: ExportModel.StageState) -> Color {
        switch state {
        case .pending: return Color.secondary.opacity(0.6)
        case .running: return .primary
        case .done:    return .secondary
        case .failed:  return Kiln.Palette.danger
        }
    }

    private func background(for state: ExportModel.StageState) -> Color {
        switch state {
        case .running: return Kiln.Palette.firingWash
        default:       return Color.clear
        }
    }

    private var voiceOverLabel: String {
        func stateWord(_ s: ExportModel.StageState) -> String {
            switch s {
            case .pending: return "pending"
            case .running: return "in progress"
            case .done:    return "done"
            case .failed:  return "failed"
            }
        }
        return "Export progress: fuse \(stateWord(progress.fuse)), GGUF \(stateWord(progress.gguf)), Modelfile \(stateWord(progress.modelfile)), Ollama \(stateWord(progress.ollama))"
    }
}

#Preview("Running mid-pipeline") {
    ExportProgressView(
        progress: ExportModel.Progress(
            fuse: .done(artifact: "fused"),
            gguf: .running,
            modelfile: .pending,
            ollama: .pending
        )
    )
    .padding()
}

#Preview("All done") {
    ExportProgressView(
        progress: ExportModel.Progress(
            fuse: .done(artifact: "fused"),
            gguf: .done(artifact: "kiln.gguf"),
            modelfile: .done(artifact: "Modelfile"),
            ollama: .done(artifact: "kiln-preview")
        )
    )
    .padding()
}
