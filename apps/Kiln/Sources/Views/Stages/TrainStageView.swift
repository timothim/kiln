import SwiftUI
import KilnCore

/// Stage 2 — dispatches between empty / running / cancelling / completed /
/// failed based on the TrainModel's status. Mirrors PrepareStageView exactly.
struct TrainStageView: View {
    let project: Project
    var model: TrainModel?
    var exportModel: ExportModel?
    let onStart: (VoiceSplit?) -> Void
    let onCancel: () -> Void
    let onContinue: () -> Void
    let onReset: () -> Void
    let onExport: () -> Void
    let onDismissExport: () -> Void

    var body: some View {
        Group {
            if let model {
                switch model.status {
                case .idle:
                    TrainingEmptyView(project: project, onStart: onStart)
                        .transition(Kiln.Motion.stageTransition)
                case .running:
                    TrainingRunningView(project: project, model: model, onCancel: onCancel)
                        .transition(Kiln.Motion.stageTransition)
                case .cancelling:
                    CancellingOverlay(
                        underlying: TrainingRunningView(project: project, model: model, onCancel: onCancel)
                    )
                    .transition(Kiln.Motion.stageTransition)
                case .completed(let report):
                    TrainingCompletedView(
                        project: project,
                        report: report,
                        exportModel: exportModel,
                        onContinue: onContinue,
                        onReset: onReset,
                        onExport: onExport,
                        onDismissExport: onDismissExport
                    )
                    .transition(Kiln.Motion.stageTransition)
                case .failed(let error):
                    TrainingErrorView(project: project, error: error, onReset: onReset)
                        .transition(Kiln.Motion.stageTransition)
                }
            } else {
                TrainingEmptyView(project: project, onStart: onStart)
                    .transition(Kiln.Motion.stageTransition)
            }
        }
        .animation(Kiln.Motion.standard, value: statusKey)
    }

    private var statusKey: String {
        guard let model else { return "idle" }
        switch model.status {
        case .idle:        return "idle"
        case .running:     return "running"
        case .cancelling:  return "cancelling"
        case .completed:   return "completed"
        case .failed:      return "failed"
        }
    }
}

// MARK: - Empty

private struct TrainingEmptyView: View {
    let project: Project
    let onStart: (VoiceSplit?) -> Void

    @State private var split: VoiceSplit

    init(project: Project, onStart: @escaping (VoiceSplit?) -> Void) {
        self.project = project
        self.onStart = onStart
        self._split = State(initialValue: Self.initialSplit(for: project))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Kiln.Space.l) {
                StageHeader(
                    title: project.name,
                    subtitle: "Ready when you are.",
                    stage: project.stage
                )

                VoiceSplitterView(split: $split)
                    .padding(.top, Kiln.Space.xs)

                HStack {
                    Spacer(minLength: 0)
                    card
                    Spacer(minLength: 0)
                }
                .padding(.top, Kiln.Space.m)
            }
            .padding(Kiln.Space.xl)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var card: some View {
        VStack(spacing: Kiln.Space.m) {
            Image(systemName: "flame")
                .font(.system(size: Kiln.Icon.hero, weight: .regular))
                .foregroundStyle(Kiln.Palette.firing)
                .accessibilityHidden(true)
            Text("Teach your model")
                .font(Kiln.Font.title)
                .foregroundStyle(.primary)
            Text("Qwen2.5-\(project.modelSize.displayName) will learn from your prepared samples.")
                .font(Kiln.Font.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            Button(action: { onStart(split) }) {
                Label("Teach", systemImage: "flame")
                    .font(Kiln.Font.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, Kiln.Space.m)
                    .padding(.vertical, Kiln.Space.xs)
                    .background(
                        RoundedRectangle(cornerRadius: Kiln.Radius.control, style: .continuous)
                            .fill(Kiln.Palette.firing)
                    )
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .padding(.top, Kiln.Space.xs)
            .accessibilityLabel("Teach your model")
        }
        .padding(.horizontal, Kiln.Space.xl)
        .padding(.vertical, Kiln.Space.xl)
        .frame(maxWidth: 420)
        .background(
            RoundedRectangle(cornerRadius: Kiln.Radius.card, style: .continuous)
                .fill(.regularMaterial)
        )
        .emberGlow(cornerRadius: Kiln.Radius.card, glowRadius: 20)
    }

    /// Seeds the splitter. Persisted `project.voiceSplit` wins; otherwise we
    /// synthesize a single-persona default so the splitter isn't an empty
    /// shell during demos. The label leans on the corpus folder name so the
    /// copy reads "oof, that's mine" rather than a generic placeholder.
    private static func initialSplit(for project: Project) -> VoiceSplit {
        if let existing = project.voiceSplit {
            return existing
        }
        let trimmedFolder = project.folderName.flatMap { $0.isEmpty ? nil : $0 }
        let label = trimmedFolder ?? "Your writing"
        let samples = project.keptChunks ?? project.totalChunks ?? 0
        return VoiceSplit(
            personas: [Persona(label: label, sampleCount: samples, selected: true)]
        )
    }
}

// MARK: - Running

private struct TrainingRunningView: View {
    let project: Project
    @Bindable var model: TrainModel
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.l) {
            StageHeader(
                title: project.name,
                subtitle: subtitle,
                stage: project.stage
            )

            TrainingProgressCapsule(progress: fractionComplete)
                .frame(maxWidth: 460)
                .padding(.top, Kiln.Space.xs)

            HStack(spacing: Kiln.Space.m) {
                Stat(label: "Base", value: "Qwen2.5-\(project.modelSize.displayName)")
                Stat(label: "Iter", value: iterDisplay)
                Stat(label: "Loss", value: lossDisplay)
                Stat(label: "ETA", value: etaDisplay)
            }
            .frame(maxWidth: 640)

            if !model.lossHistory.isEmpty {
                VStack(alignment: .leading, spacing: Kiln.Space.xs) {
                    Text("Loss")
                        .font(Kiln.Font.caption)
                        .foregroundStyle(.tertiary)
                    LossSparkline(samples: model.lossHistory)
                        .frame(maxWidth: 640)
                }
                .padding(.top, Kiln.Space.xs)
            }

            GrowingModelPanelView(
                samples: $model.growingModelSamples,
                state: model.growingModelState,
                currentStep: model.currentProgress?.iter ?? 0,
                currentEpoch: model.currentEpoch,
                totalEpochs: model.totalEpochs,
                nextUpdateSeconds: 0
            )
            .frame(maxWidth: 640)

            // PR #23 Training Advisor — appears as soon as the first
            // observation arrives. Hidden during warm-up when there's
            // nothing for Opus to react to yet.
            if !model.advisorObservations.isEmpty {
                TrainingAdvisorInlinePanel(observations: model.advisorObservations)
                    .frame(maxWidth: 640)
                    .transition(.opacity)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Stop", role: .destructive, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityHint("Stops training and keeps the last checkpoint")
            }
        }
        .padding(Kiln.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var subtitle: String {
        if model.isWarmingUp {
            return "Warming up. Loss numbers appear shortly."
        }
        return "Teaching your model."
    }

    private var fractionComplete: Double {
        guard let total = model.totalIters, total > 0,
              let iter = model.currentProgress?.iter else { return 0 }
        return min(1.0, Double(iter) / Double(total))
    }

    private var iterDisplay: String {
        let current = model.currentProgress?.iter ?? 0
        if let total = model.totalIters {
            return "\(current) of \(total)"
        }
        return "\(current)"
    }

    private var lossDisplay: String {
        guard let loss = model.currentProgress?.loss else { return "—" }
        return String(format: "%.2f", loss)
    }

    private var etaDisplay: String {
        if model.isWarmingUp { return "Warming up" }
        return model.etaDisplay ?? "—"
    }
}

// MARK: - Completed

private struct TrainingCompletedView: View {
    let project: Project
    let report: TrainingReport
    var exportModel: ExportModel?
    let onContinue: () -> Void
    let onReset: () -> Void
    let onExport: () -> Void
    let onDismissExport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.l) {
            StageHeader(
                title: project.name,
                subtitle: subtitle,
                stage: project.stage
            )

            HStack(spacing: Kiln.Space.m) {
                Stat(label: "Iterations", value: "\(report.itersCompleted)")
                Stat(label: "Final loss", value: report.finalLoss.map { String(format: "%.2f", $0) } ?? "—")
                Stat(label: "Wall clock", value: formatDuration(report.wallClockSec))
                Stat(label: "Adapter", value: report.adapterURL.lastPathComponent)
            }
            .frame(maxWidth: 640)

            if report.partialCheckpoint {
                Label("Stopped early. A partial checkpoint was saved.", systemImage: "checkmark.seal")
                    .font(Kiln.Font.caption)
                    .foregroundStyle(.secondary)
            }

            exportSection
                .frame(maxWidth: 640)

            Spacer(minLength: 0)

            HStack {
                Button("Start over", action: onReset)
                Spacer()
                Button(action: onContinue) {
                    Label("Continue", systemImage: "arrow.right")
                        .font(Kiln.Font.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, Kiln.Space.m)
                        .padding(.vertical, Kiln.Space.xs)
                        .background(
                            RoundedRectangle(cornerRadius: Kiln.Radius.control, style: .continuous)
                                .fill(Kiln.Palette.firing)
                        )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .accessibilityLabel("Continue")
            }
        }
        .padding(Kiln.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var exportSection: some View {
        if let exportModel {
            switch exportModel.status {
            case .idle:
                exportCTA
            case .running:
                exportProgressCard(
                    headline: "Installing your model in Ollama.",
                    allowRetry: false
                )
            case .completed(let modelName):
                exportCompletedCard(modelName: modelName)
            case .failed(let message, _):
                exportFailedCard(message: message)
            }
        } else {
            exportCTA
        }
    }

    private var exportCTA: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.xs) {
            Text("Install in Ollama")
                .font(Kiln.Font.label)
                .kerning(0.44)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            HStack(spacing: Kiln.Space.m) {
                Text("One tap to fuse the adapter, convert to GGUF, and install as an Ollama model.")
                    .font(Kiln.Font.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Kiln.Space.m)
                Button(action: onExport) {
                    Label("Export to Ollama", systemImage: "square.and.arrow.down.on.square")
                        .font(Kiln.Font.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, Kiln.Space.m)
                        .padding(.vertical, Kiln.Space.xs)
                        .background(
                            RoundedRectangle(cornerRadius: Kiln.Radius.control, style: .continuous)
                                .fill(Kiln.Palette.firing)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Export to Ollama")
            }
        }
        .padding(Kiln.Space.m)
        .background {
            RoundedRectangle(cornerRadius: Kiln.Radius.card, style: .continuous)
                .fill(Kiln.Palette.surfaceSunken)
        }
    }

    private func exportProgressCard(headline: String, allowRetry: Bool) -> some View {
        VStack(alignment: .leading, spacing: Kiln.Space.xs) {
            Text(headline)
                .font(Kiln.Font.body)
                .foregroundStyle(.primary)
            if let exportModel {
                ExportProgressView(progress: exportModel.progress)
            }
            if allowRetry {
                Button("Retry export", action: onExport)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(Kiln.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Kiln.Radius.card, style: .continuous)
                .fill(Kiln.Palette.surfaceSunken)
        }
    }

    private func exportCompletedCard(modelName: String) -> some View {
        VStack(alignment: .leading, spacing: Kiln.Space.xs) {
            HStack(spacing: Kiln.Space.xs) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text("Your model is installed and ready to chat.")
                    .font(Kiln.Font.body)
                    .foregroundStyle(.primary)
            }
            if let exportModel {
                ExportProgressView(progress: exportModel.progress)
            }
            Text("ollama run \(modelName)")
                .font(Kiln.Font.mono)
                .textSelection(.enabled)
                .padding(.horizontal, Kiln.Space.m)
                .padding(.vertical, Kiln.Space.xs)
                .background {
                    RoundedRectangle(cornerRadius: Kiln.Radius.control, style: .continuous)
                        .fill(Color.primary.opacity(Kiln.Opacity.codeFill))
                }
        }
        .padding(Kiln.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Kiln.Radius.card, style: .continuous)
                .fill(Kiln.Palette.surfaceSunken)
        }
    }

    private func exportFailedCard(message: String) -> some View {
        VStack(alignment: .leading, spacing: Kiln.Space.xs) {
            HStack(spacing: Kiln.Space.xs) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(Kiln.Palette.danger)
                    .accessibilityHidden(true)
                Text(message)
                    .font(Kiln.Font.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Retry", action: onExport)
                    .buttonStyle(.borderedProminent)
                    .tint(Kiln.Palette.firing)
                Button("Dismiss", action: onDismissExport)
                    .buttonStyle(.bordered)
            }
        }
        .padding(Kiln.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Kiln.Radius.card, style: .continuous)
                .fill(Kiln.Palette.surfaceSunken)
        }
    }

    private var subtitle: String {
        if report.partialCheckpoint {
            return "Stopped at iter \(report.itersCompleted). Partial adapter saved."
        }
        return "Your model finished learning."
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total)s" }
        let minutes = total / 60
        let rem = total % 60
        if minutes < 60 { return String(format: "%dm %02ds", minutes, rem) }
        let hours = minutes / 60
        let mm = minutes % 60
        return String(format: "%dh %02dm", hours, mm)
    }
}

// MARK: - Failed

private struct TrainingErrorView: View {
    let project: Project
    let error: TrainModel.DisplayError
    let onReset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.l) {
            StageHeader(title: project.name, subtitle: nil, stage: project.stage)

            VStack(alignment: .leading, spacing: Kiln.Space.m) {
                HStack(spacing: Kiln.Space.xs) {
                    Image(systemName: iconName)
                        .font(.title2)
                        .foregroundStyle(iconColor)
                        .accessibilityHidden(true)
                    Text(headline)
                        .font(Kiln.Font.title)
                        .foregroundStyle(.primary)
                }
                Text(error.userFacingMessage)
                    .font(Kiln.Font.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Kiln.Space.l)
            .frame(maxWidth: 520, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Kiln.Radius.card, style: .continuous)
                    .fill(Kiln.Palette.surfaceSunken)
            )

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button(action: onReset) { Text("Try again") }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityLabel("Try again")
            }
        }
        .padding(Kiln.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var headline: String {
        switch error {
        case .cancelled:        return "Stopped before the first checkpoint"
        case .outOfMemory:      return "Out of memory"
        case .dataInvalid:      return "Dataset unusable"
        case .modelNotFound:    return "Base model missing"
        case .subprocessFailed: return "Trainer failed"
        case .interrupted:      return "Training interrupted"
        case .launchFailed:     return "Could not start trainer"
        case .decodingFailed:   return "Communication error"
        case .other:            return "Something went wrong"
        }
    }

    private var iconName: String {
        switch error {
        case .cancelled: return "xmark.circle"
        case .outOfMemory: return "memorychip"
        case .dataInvalid: return "doc.badge.ellipsis"
        case .modelNotFound: return "questionmark.folder"
        case .launchFailed: return "bolt.slash"
        case .decodingFailed: return "exclamationmark.bubble"
        default: return "exclamationmark.triangle"
        }
    }

    private var iconColor: Color {
        switch error {
        case .cancelled: return .secondary
        default:         return Kiln.Palette.danger
        }
    }
}
