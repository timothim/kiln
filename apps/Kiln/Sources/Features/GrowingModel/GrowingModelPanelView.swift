import SwiftUI

// MARK: - Local UI-layer types
//
// Phase 3 owns these UI-shaped structs. DATA agent wires them to real sample
// events from the MLX sidecar in M6 integration — the field names are chosen
// to slot cleanly onto what the sidecar already streams.

struct PromptSample: Identifiable, Equatable {
    let id: UUID
    let prompt: String
    let currentResponse: String?   // nil = no sample yet for this prompt
    let isUpdating: Bool
    let stylizationScore: Double   // 0...100, grows over the training run

    init(id: UUID = UUID(),
         prompt: String,
         currentResponse: String? = nil,
         isUpdating: Bool = false,
         stylizationScore: Double = 0) {
        self.id = id
        self.prompt = prompt
        self.currentResponse = currentResponse
        self.isUpdating = isUpdating
        self.stylizationScore = stylizationScore
    }
}

enum GrowingModelState: Equatable {
    case empty          // pre-first-checkpoint
    case inProgress     // sampling loop running
    case completed      // training done, final responses frozen
}

// MARK: - Growing Model Panel

/// The emotional centerpiece of M6. Three fixed prompts, each resampled from
/// the latest adapter checkpoint every ~30s. Users watch the responses drift
/// from generic-base toward their own voice over the training run.
///
/// Amber is intentional on the stylization gauge — stylization progress is a
/// firing moment per DESIGN.md, in the same family as the training progress
/// capsule and the ember glow.
struct GrowingModelPanelView: View {
    @Binding var samples: [PromptSample]
    let state: GrowingModelState
    let currentStep: Int
    let currentEpoch: Int
    let totalEpochs: Int
    let nextUpdateSeconds: Int      // 0 when no countdown is active

    var body: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.m) {
            header

            VStack(spacing: Kiln.Space.sm) {
                ForEach(samples) { sample in
                    GrowingModelPromptCard(
                        sample: sample,
                        state: state,
                        nextUpdateSeconds: nextUpdateSeconds
                    )
                }
            }

            if state == .completed {
                completionBanner
            }

            Spacer(minLength: 0)
        }
        .padding(Kiln.Space.l)
        .animation(Kiln.Motion.standard, value: state)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Growing Model")
                .font(Kiln.Font.title)
            Spacer()
            if state == .inProgress {
                Text("Step \(currentStep) · Epoch \(currentEpoch) of \(totalEpochs)")
                    .font(Kiln.Font.numeric)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .animation(Kiln.Motion.standard, value: currentStep)
            }
        }
    }

    // Firing-moment completion banner. Stylization done = emotional payoff of
    // M6; the caption-weight version read undersold. Amber is sanctioned here
    // per DESIGN.md (firing moment, same family as TrainingProgressCapsule).
    private var completionBanner: some View {
        HStack(spacing: Kiln.Space.xs) {
            Image(systemName: "flame.fill")
                .font(.system(size: Kiln.Icon.small))
                .foregroundStyle(Kiln.Palette.firing)
            Text("Congrats — your model has found its voice.")
                .font(Kiln.Font.body.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, Kiln.Space.m)
        .padding(.vertical, Kiln.Space.xs)
        .frame(maxWidth: .infinity)
        .background {
            Capsule(style: .continuous)
                .fill(Kiln.Palette.firingWash)
        }
        .padding(.top, Kiln.Space.xs)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Prompt Card

private struct GrowingModelPromptCard: View {
    let sample: PromptSample
    let state: GrowingModelState
    let nextUpdateSeconds: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.xs) {
            promptHeader
            responseArea
            footerRow
        }
        .padding(Kiln.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Kiln.Radius.card, style: .continuous)
                .fill(Color.primary.opacity(Kiln.Opacity.cardFill))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(a11yLabel)
    }

    private var promptHeader: some View {
        HStack(alignment: .top, spacing: Kiln.Space.m) {
            VStack(alignment: .leading, spacing: Kiln.Space.xxs) {
                Text("Prompt")
                    .font(Kiln.Font.label)
                    .kerning(0.44)
                    .foregroundStyle(.tertiary)
                Text(sample.prompt)
                    .font(Kiln.Font.body)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            StylizationGauge(score: sample.stylizationScore)
        }
    }

    // 0.6s is intentionally slower than Kiln.Motion.standard (0.35s) for the
    // emotional pacing of each new sample — the reveal should feel considered,
    // not snappy. Call-site constant, not a Design System token.
    private var responseArea: some View {
        Text(sample.currentResponse ?? "—")
            .font(Kiln.Font.body)
            .foregroundStyle(sample.currentResponse == nil ? .tertiary : .primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .contentTransition(.opacity)
            .animation(.smooth(duration: 0.6), value: sample.currentResponse)
    }

    @ViewBuilder
    private var footerRow: some View {
        switch state {
        case .empty:
            Text("Waiting for first checkpoint...")
                .font(Kiln.Font.caption)
                .foregroundStyle(.tertiary)
        case .inProgress:
            if sample.isUpdating {
                Text("Sampling...")
                    .font(Kiln.Font.caption)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            } else {
                Text("Next update in \(max(1, nextUpdateSeconds))s")
                    .font(Kiln.Font.caption)
                    .foregroundStyle(.tertiary)
                    .contentTransition(.numericText())
                    .animation(Kiln.Motion.standard, value: nextUpdateSeconds)
            }
        case .completed:
            Text("Final")
                .font(Kiln.Font.label)
                .kerning(0.44)
                .foregroundStyle(.secondary)
                .transition(.opacity)
        }
    }

    private var a11yLabel: String {
        let response = sample.currentResponse ?? "no response yet"
        return "Prompt: \(sample.prompt). Response: \(response). Stylization \(Int(sample.stylizationScore)) percent."
    }
}

// MARK: - Stylization Gauge

private struct StylizationGauge: View {
    let score: Double

    @State private var lastAnnouncedMilestone: Int = 0

    static let barWidth: CGFloat = 80
    static let milestones: [Int] = [25, 50, 75, 100]

    private var clamped: Double { max(0, min(100, score)) }
    private var pct: Int { Int(clamped) }

    var body: some View {
        VStack(alignment: .trailing, spacing: Kiln.Space.xxs) {
            Text("\(pct)%")
                .font(Kiln.Font.label)
                .kerning(0.44)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(Kiln.Motion.standard, value: clamped)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Kiln.Palette.surfaceSunken)
                Capsule()
                    .fill(Kiln.Palette.firing)
                    .frame(width: max(0, Self.barWidth * clamped / 100))
                    .animation(Kiln.Motion.standard, value: clamped)
            }
            .frame(width: Self.barWidth, height: Kiln.Space.xxs)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Stylization")
        .accessibilityValue(accessibilityValueText)
        .onChange(of: pct) { _, newValue in
            announceIfMilestoneCrossed(newValue)
        }
    }

    private var accessibilityValueText: String {
        switch pct {
        case 100: return "100 percent — fully stylized"
        case 75...: return "\(pct) percent — nearly fully stylized"
        case 50...: return "\(pct) percent — halfway, your voice is emerging"
        case 25...: return "\(pct) percent — building"
        default:   return "\(pct) percent — starting"
        }
    }

    private func announceIfMilestoneCrossed(_ newValue: Int) {
        guard let milestone = Self.milestones.last(where: { newValue >= $0 }),
              milestone > lastAnnouncedMilestone else { return }
        lastAnnouncedMilestone = milestone
        AccessibilityNotification.Announcement("Stylization reached \(milestone) percent").post()
    }
}

// MARK: - Previews

#Preview("Empty — waiting for first checkpoint") {
    StatefulPreviewWrapper([
        PromptSample(prompt: "What should I work on this week?"),
        PromptSample(prompt: "Write a one-line birthday message for a friend."),
        PromptSample(prompt: "Describe your perfect Sunday.")
    ]) { $samples in
        GrowingModelPanelView(
            samples: $samples,
            state: .empty,
            currentStep: 0,
            currentEpoch: 0,
            totalEpochs: 3,
            nextUpdateSeconds: 0
        )
        .frame(width: 520)
    }
}

#Preview("In progress — partial samples") {
    StatefulPreviewWrapper([
        PromptSample(
            prompt: "What should I work on this week?",
            currentResponse: "Here are several prioritization frameworks to consider.",
            stylizationScore: 18
        ),
        PromptSample(prompt: "Write a one-line birthday message for a friend."),
        PromptSample(prompt: "Describe your perfect Sunday.")
    ]) { $samples in
        GrowingModelPanelView(
            samples: $samples,
            state: .inProgress,
            currentStep: 12,
            currentEpoch: 1,
            totalEpochs: 3,
            nextUpdateSeconds: 22
        )
        .frame(width: 520)
    }
}

#Preview("In progress — full samples") {
    StatefulPreviewWrapper([
        PromptSample(
            prompt: "What should I work on this week?",
            currentResponse: "Pick the one thing you'd regret not shipping. Start there.",
            stylizationScore: 67
        ),
        PromptSample(
            prompt: "Write a one-line birthday message for a friend.",
            currentResponse: "Happy birthday — hope this year is slightly less chaotic than the last one.",
            stylizationScore: 54
        ),
        PromptSample(
            prompt: "Describe your perfect Sunday.",
            currentResponse: "Coffee, long walk, phone face-down, something unambitious for dinner.",
            stylizationScore: 71
        )
    ]) { $samples in
        GrowingModelPanelView(
            samples: $samples,
            state: .inProgress,
            currentStep: 127,
            currentEpoch: 2,
            totalEpochs: 3,
            nextUpdateSeconds: 14
        )
        .frame(width: 520)
    }
}

#Preview("Completed — final voice") {
    StatefulPreviewWrapper([
        PromptSample(
            prompt: "What should I work on this week?",
            currentResponse: "Pick the one thing you'd regret not shipping. Start there.",
            stylizationScore: 92
        ),
        PromptSample(
            prompt: "Write a one-line birthday message for a friend.",
            currentResponse: "Happy birthday — hope this year is slightly less chaotic than the last.",
            stylizationScore: 88
        ),
        PromptSample(
            prompt: "Describe your perfect Sunday.",
            currentResponse: "Coffee, long walk, phone face-down, something unambitious for dinner.",
            stylizationScore: 94
        )
    ]) { $samples in
        GrowingModelPanelView(
            samples: $samples,
            state: .completed,
            currentStep: 300,
            currentEpoch: 3,
            totalEpochs: 3,
            nextUpdateSeconds: 0
        )
        .frame(width: 520)
    }
}

// MARK: - Preview harness

/// Wraps a value in local @State so previews can demonstrate bindings.
/// Xcode Previews' built-in initializers don't vend a Binding; this closes the gap.
private struct StatefulPreviewWrapper<Value, Content: View>: View {
    @State private var value: Value
    private let content: (Binding<Value>) -> Content

    init(_ initial: Value, @ViewBuilder content: @escaping (Binding<Value>) -> Content) {
        _value = State(initialValue: initial)
        self.content = content
    }

    var body: some View { content($value) }
}
