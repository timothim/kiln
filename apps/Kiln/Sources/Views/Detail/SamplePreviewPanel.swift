import SwiftUI

/// Before/after sample card for the Complete detail pane. M3 shows a typed
/// placeholder `Sample`; M6 wires the Growing Model sidecar output through.
struct SamplePreviewPanel: View {
    struct Sample {
        let prompt: String
        let base: String
        let tuned: String
    }

    private let sample = Sample(
        prompt: "What should I work on this week?",
        base: "Here are several prioritization frameworks to consider.",
        tuned: "Pick the one thing you'd regret not shipping. Then start."
    )

    var body: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.m) {
            Text("Sample")
                .font(Kiln.Font.title)

            promptRow

            sampleRow(label: "Base",  text: sample.base, tint: .secondary)
            sampleRow(label: "Kiln",  text: sample.tuned, tint: .primary)
        }
        .padding(Kiln.Space.m)
    }

    private var promptRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: Kiln.Space.xs) {
            Text("You asked")
                .font(Kiln.Font.caption)
                .foregroundStyle(.tertiary)
            Text(sample.prompt)
                .font(Kiln.Font.body)
                .foregroundStyle(.primary)
                .lineLimit(2)
        }
    }

    private func sampleRow(label: String, text: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: Kiln.Space.xxs) {
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 6, height: 6)
                Text(label)
                    .font(Kiln.Font.caption)
                    .foregroundStyle(.secondary)
            }
            Text(text)
                .font(Kiln.Font.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Kiln.Space.xs)
        .background {
            RoundedRectangle(cornerRadius: Kiln.Radius.control, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) response: \(text)")
    }
}
