import SwiftUI
import KilnCore

/// Live running-counts + stage progress while the pipeline is ingesting.
/// Used by PrepareStageView when PrepareModel.status == .running or .cancelling.
struct IngestProgressView: View {
    let project: Project
    let model: PrepareModel
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.l) {
            StageHeader(
                title: project.name,
                subtitle: subtitle(for: model.currentStage),
                stage: project.stage
            )

            stageRow
            progressBar
            counterRow
            SampleCarousel(samples: model.liveSamples)

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .disabled(model.status == .cancelling)
                    .accessibilityHint("Stops reading your folder")
            }
        }
        .padding(Kiln.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var stageRow: some View {
        HStack(spacing: Kiln.Space.xs) {
            Image(systemName: iconName(for: model.currentStage))
                .font(Kiln.Font.caption)
                .foregroundStyle(Kiln.Palette.firing)
                .accessibilityHidden(true)
            Text(stageLabel(for: model.currentStage))
                .font(Kiln.Font.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var progressBar: some View {
        StageProgressBar(fraction: model.overallProgress)
            .frame(maxWidth: 420)
    }

    private var counterRow: some View {
        HStack(alignment: .top, spacing: Kiln.Space.xl) {
            LiveCountTicker(label: "Files read", value: model.counts.filesParsed)
            LiveCountTicker(label: "Samples kept", value: model.counts.chunksAfterQuality)
            LiveCountTicker(label: "Duplicates dropped", value: duplicatesDropped)
            LiveCountTicker(label: "Files skipped", value: model.counts.filesSkipped)
        }
    }

    private var duplicatesDropped: Int {
        let before = model.counts.chunksBeforeDedup
        let after = model.counts.chunksAfterMinHashDedup
        return max(0, before - after)
    }

    private func subtitle(for stage: IngestStage) -> String {
        switch stage {
        case .discovery: return "Looking through your folder."
        case .parsing:   return "Reading each file."
        case .dedup:     return "Removing duplicates."
        case .quality:   return "Keeping the writing that sounds like you."
        case .writing:   return "Writing training files."
        }
    }

    private func stageLabel(for stage: IngestStage) -> String {
        switch stage {
        case .discovery: return "Discovery"
        case .parsing:   return "Parsing"
        case .dedup:     return "Dedup"
        case .quality:   return "Quality filter"
        case .writing:   return "Writing"
        }
    }

    private func iconName(for stage: IngestStage) -> String {
        switch stage {
        case .discovery: return "folder.badge.questionmark"
        case .parsing:   return "doc.text.magnifyingglass"
        case .dedup:     return "rectangle.stack.badge.minus"
        case .quality:   return "checkmark.seal"
        case .writing:   return "square.and.arrow.down"
        }
    }
}
