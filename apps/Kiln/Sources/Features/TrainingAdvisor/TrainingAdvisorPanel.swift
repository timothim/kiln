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

    var body: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.xs) {
            badge
            content
        }
        .padding(Kiln.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Kiln.Radius.card, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        }
    }

    private var badge: some View {
        HStack(spacing: Kiln.Space.xs) {
            Image(systemName: "sparkles")
                .foregroundStyle(.purple)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(badgeTitle)
                    .font(Kiln.Font.label)
                    .kerning(0.44)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Text("Voice Coach is watching")
                    .font(Kiln.Font.body.weight(.medium))
            }
            Spacer(minLength: 0)
            if model.isWatching {
                ProgressView().controlSize(.small)
            }
        }
    }

    private var badgeTitle: String {
        model.localMode ? "Running locally with Qwen2.5" : "Powered by Claude Opus 4.7"
    }

    @ViewBuilder
    private var content: some View {
        if model.observations.isEmpty {
            Text(model.isWatching
                 ? "Waiting for the first checkpoint…"
                 : "Toggle on \"Training Advisor\" in Settings → Cloud features to get live observations during training.")
                .font(Kiln.Font.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(model.observations.suffix(8)) { obs in
                    HStack(alignment: .top, spacing: Kiln.Space.xs) {
                        Text("iter \(obs.iteration)")
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
}
