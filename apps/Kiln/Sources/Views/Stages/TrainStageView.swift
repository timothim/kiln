import SwiftUI

/// Stage 2 — training in progress. Ember-glowing progress capsule, three
/// stats, and the Growing Model preamble line. Numbers here are typed
/// placeholder values; real events land in M5–M6.
struct TrainStageView: View {
    let project: Project

    /// Placeholder values for M3. Will become live sidecar state in M5.
    private let placeholderProgress: Double = 0.32
    private let placeholderIter = 128
    private let placeholderTotalIter = 400
    private let placeholderLoss = 1.24

    var body: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.l) {
            StageHeader(
                title: project.name,
                subtitle: "Teaching your model.",
                stage: project.stage
            )

            TrainingProgressCapsule(progress: placeholderProgress)
                .frame(maxWidth: 460)
                .padding(.top, Kiln.Space.xs)

            HStack(spacing: Kiln.Space.m) {
                Stat(label: "Base", value: "Qwen2.5-\(project.modelSize.displayName)")
                Stat(label: "Iter", value: "\(placeholderIter) of \(placeholderTotalIter)")
                Stat(label: "Loss", value: String(format: "%.2f", placeholderLoss))
            }
            .frame(maxWidth: 640)

            Text("Your model will start speaking at the first checkpoint.")
                .font(Kiln.Font.body)
                .foregroundStyle(.secondary)
                .padding(.top, Kiln.Space.xs)

            Spacer(minLength: 0)
        }
        .padding(Kiln.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
