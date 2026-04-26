import KilnCore
import Observation
import SwiftUI

/// Saturday Phase 5 — "Voice Coach is watching" inline panel for the
/// training UI. The panel renders a streaming list of one-liner
/// observations from Claude Opus 4.7 (or local Qwen) that arrive at
/// each checkpoint poll. Sits under the loss chart in
/// TrainStageView when the Training Advisor toggle is on.

struct TrainingAdvisorObservation: Identifiable, Hashable {
    let id = UUID()
    let iteration: Int
    let content: String
    let modelID: String
    let arrivedAt: Date
}

@Observable
@MainActor
final class TrainingAdvisorPanelModel {
    private(set) var observations: [TrainingAdvisorObservation] = []
    var isWatching: Bool = false
    var localMode: Bool = false

    func append(observation: TrainingAdvisorObservation) {
        observations.append(observation)
    }

    func clear() {
        observations.removeAll()
    }
}

struct TrainingAdvisorPanel: View {
    @State var model: TrainingAdvisorPanelModel

    /// Per DESIGN.md `post-it-card` spec: the Training Advisor renders
    /// as Opus's "annotation" stuck onto the user's training run.
    /// Folded-corner top-right + surface-paper fill.
    var body: some View {
        PostItCard {
            VStack(alignment: .leading, spacing: Kiln.Space.s3) {
                advisorBadge(localMode: model.localMode, isWatching: model.isWatching)
                advisorContent(
                    observations: model.observations.map {
                        AdvisorObservationRow(iter: $0.iteration, content: $0.content)
                    },
                    isWatching: model.isWatching
                )
            }
        }
    }
}

/// Inline variant rendered directly under the loss chart in
/// ``TrainStageView``. Consumes ``TrainModel.AdvisorObservation``
/// directly so we don't need a parallel ``TrainingAdvisorPanelModel``
/// with the same shape.
struct TrainingAdvisorInlinePanel: View {
    let observations: [TrainModel.AdvisorObservation]

    var body: some View {
        PostItCard {
            VStack(alignment: .leading, spacing: Kiln.Space.s3) {
                advisorBadge(
                    localMode: observations.last?.modelID.lowercased().hasPrefix("qwen") ?? false,
                    isWatching: true
                )
                advisorContent(
                    observations: observations.map {
                        AdvisorObservationRow(iter: $0.iter, content: $0.content)
                    },
                    isWatching: true
                )
            }
        }
    }
}

// MARK: - Shared building blocks

private struct AdvisorObservationRow {
    let iter: Int
    let content: String
}

@ViewBuilder
private func advisorBadge(localMode: Bool, isWatching: Bool) -> some View {
    HStack(spacing: Kiln.Space.xs) {
        Image(systemName: "sparkles")
            .foregroundStyle(.purple)
            .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 0) {
            Text(localMode ? "Running locally with Qwen2.5" : "Powered by Claude Opus 4.7")
                .font(Kiln.Font.label)
                .kerning(0.44)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Text("Voice Coach is watching")
                .font(Kiln.Font.body.weight(.medium))
        }
        Spacer(minLength: 0)
        if isWatching {
            ProgressView().controlSize(.small)
        }
    }
}

@ViewBuilder
private func advisorContent(observations: [AdvisorObservationRow], isWatching: Bool) -> some View {
    if observations.isEmpty {
        Text(isWatching
             ? "Waiting for the first checkpoint…"
             : "Toggle on \"Training Advisor\" in Settings → Cloud features to get live observations during training.")
            .font(Kiln.Font.caption)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    } else {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(observations.suffix(8).enumerated()), id: \.offset) { _, obs in
                HStack(alignment: .top, spacing: Kiln.Space.xs) {
                    Text("iter \(obs.iter, format: .number)")
                        .font(Kiln.Font.label)
                        .kerning(0.44)
                        .textCase(.uppercase)
                        .foregroundStyle(.tertiary)
                        .frame(width: 60, alignment: .leading)
                    Text(obs.content)
                        .font(Kiln.Font.caption)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
