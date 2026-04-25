import SwiftUI

// MARK: - Local UI-layer types
//
// Mirrors LEAD's KilnCore `VoiceMirror.Reflection { prompt, continuation,
// adapterStep }` so DATA's M7 wire-up is a field swap, not a re-model. The
// UI adds `source`, `state`, and `signaturePhrases` — the first two are
// pure presentation, the third is an interpretability overlay that the
// style-extractor will eventually supply.

enum ReflectionSource: String, CaseIterable, Identifiable {
    case baseQwen = "Base Qwen"
    case sftOnly = "SFT only"
    case sftPlusDpo = "SFT + DPO"
    case userAnswer = "You would say"

    var id: String { rawValue }

    /// Column identity dot — graded greys, NOT amber. Amber is reserved for
    /// the in-content signature heatmap (see class doc).
    var indicatorOpacity: Double {
        switch self {
        case .baseQwen: return 0.25
        case .sftOnly: return 0.55
        case .sftPlusDpo: return 0.9
        case .userAnswer: return 0.9
        }
    }
}

enum GenerationState: Equatable {
    case idle
    case generating
    case done
    case failed(message: String)
}

struct VoiceReflection: Identifiable, Equatable {
    let id: UUID
    let source: ReflectionSource
    var prompt: String
    var continuation: String
    var signaturePhrases: [String]   // substrings of continuation to highlight on column hover
    var adapterStep: Int?            // mirrors KilnCore VoiceMirror.Reflection.adapterStep
    var state: GenerationState

    init(id: UUID = UUID(),
         source: ReflectionSource,
         prompt: String = "",
         continuation: String = "",
         signaturePhrases: [String] = [],
         adapterStep: Int? = nil,
         state: GenerationState = .idle) {
        self.id = id
        self.source = source
        self.prompt = prompt
        self.continuation = continuation
        self.signaturePhrases = signaturePhrases
        self.adapterStep = adapterStep
        self.state = state
    }
}

// MARK: - Voice Mirror

/// Side-by-side comparison of the same prompt answered by four sources: base
/// Qwen, SFT-only checkpoint, SFT+DPO final, and the user's own answer. Lives
/// in M7 after training completes.
///
/// Amber on the per-word signature heatmap is a content-emphasis exception —
/// not a firing moment. Flagged in `docs/design/phase3-report.md` as a
/// DESIGN.md patch candidate; the prose there should sanction amber as an
/// interpretability overlay once DESIGN.md defrosts.
struct VoiceMirrorView: View {
    @Bindable var model: VoiceMirrorModel

    var body: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.l) {
            promptRow
            columnsGrid
        }
        .padding(Kiln.Space.l)
    }

    private var promptRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: Kiln.Space.m) {
            TextField("Ask a question to hear each voice...", text: $model.prompt, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Kiln.Font.body)
                .lineLimit(1...3)
                .padding(.horizontal, Kiln.Space.m)
                .padding(.vertical, Kiln.Space.xs)
                .background {
                    RoundedRectangle(cornerRadius: Kiln.Radius.control, style: .continuous)
                        .fill(Color.primary.opacity(Kiln.Opacity.cardFill))
                }
                .accessibilityLabel("Voice mirror prompt")

            Button {
                model.generate()
            } label: {
                Text(model.isGenerating ? "Generating..." : "Generate")
                    .font(Kiln.Font.body)
                    .padding(.horizontal, Kiln.Space.xs)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .controlSize(.regular)
            .disabled(model.prompt.trimmingCharacters(in: .whitespaces).isEmpty || model.isGenerating)
        }
    }

    /// Per-column minimum width. Below this the text wraps too aggressively to
     /// compare continuations side by side. When the container cannot fit
     /// four columns at this width, the grid scrolls horizontally instead of
     /// collapsing. Flagged as a candidate for a future
     /// `Kiln.Layout.voiceMirrorColumnMin` token.
    private static let columnMinWidth: CGFloat = 200

    @ViewBuilder
    private var columnsGrid: some View {
        if model.hasAnyContent {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Kiln.Space.m) {
                    ForEach(Array(model.reflections.enumerated()), id: \.element.id) { index, reflection in
                        VoiceMirrorColumn(
                            reflection: reflection,
                            columnIndex: index,
                            userAnswer: $model.userAnswer,
                            onRetry: { model.retry(reflection.source) }
                        )
                        .frame(minWidth: Self.columnMinWidth,
                               maxWidth: .infinity,
                               alignment: .topLeading)
                    }
                }
                .frame(minWidth: totalGridMinWidth,
                       maxWidth: .infinity,
                       alignment: .topLeading)
            }
        } else {
            emptyState
        }
    }

    private var totalGridMinWidth: CGFloat {
        let cols = CGFloat(model.reflections.count)
        return cols * Self.columnMinWidth + max(0, cols - 1) * Kiln.Space.m
    }

    private var emptyState: some View {
        VStack(spacing: Kiln.Space.xs) {
            Spacer(minLength: Kiln.Space.xl)
            Text("Ask a question to see your voice come through.")
                .font(Kiln.Font.body)
                .foregroundStyle(.secondary)
            Text("Compare the base model, the SFT checkpoint, the final SFT+DPO, and what you would actually say.")
                .font(Kiln.Font.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            Spacer(minLength: Kiln.Space.xl)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Column

private struct VoiceMirrorColumn: View {
    let reflection: VoiceReflection
    /// 0-based position in the row. Drives the staggered reveal so each
    /// column appears 100ms after the previous one (200ms duration each,
    /// per the Sunday animation brief). Allows the user-answer column to
    /// land last as the "your truth" answer.
    let columnIndex: Int
    @Binding var userAnswer: String
    let onRetry: () -> Void

    @State private var isHovered = false
    @State private var isPinned = false
    @State private var hasRevealed = false
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isModelColumn: Bool { reflection.source != .userAnswer }
    private var isHighlighted: Bool { isHovered || isFocused || isPinned }
    /// User-answer column is the truth source — slightly emphasized so
    /// the eye returns to it after scanning the model outputs.
    private var isUserTruth: Bool { reflection.source == .userAnswer }

    var body: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.xs) {
            header
            content
        }
        .padding(Kiln.Space.m)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: Kiln.Radius.card, style: .continuous)
                .fill(Color.primary.opacity(
                    isUserTruth ? Kiln.Opacity.codeFill : Kiln.Opacity.cardFill
                ))
        }
        .overlay(alignment: .leading) {
            // User-truth accent stripe along the leading edge — quiet
            // but present, never amber (this isn't a firing moment).
            if isUserTruth {
                Rectangle()
                    .fill(Color.secondary.opacity(0.6))
                    .frame(width: 2)
                    .padding(.vertical, Kiln.Space.xs)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: Kiln.Radius.card, style: .continuous)
                .strokeBorder(Kiln.Palette.firing.opacity(isPinned ? 0.45 : 0),
                              lineWidth: 1)
                .animation(Kiln.Motion.microToggle, value: isPinned)
        }
        .opacity(hasRevealed ? 1 : 0)
        .offset(y: hasRevealed ? 0 : 8)
        .onHover { hovering in
            isHovered = hovering
        }
        .focusable(isModelColumn && reflection.state == .done)
        .focused($isFocused)
        .onTapGesture {
            guard isModelColumn, reflection.state == .done else { return }
            isPinned.toggle()
        }
        .onAppear { revealIfReady() }
        .onChange(of: reflection.state) { _, newState in
            if newState == .done {
                revealIfReady()
            } else if newState == .generating {
                // Re-trigger on the next done so a regenerate replays
                // the stagger. Symmetric with the reveal: animate the
                // hide, or snap under Reduce Motion.
                if reduceMotion {
                    hasRevealed = false
                } else {
                    withAnimation(Kiln.Motion.staggerStep) {
                        hasRevealed = false
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(a11yLabel)
        .accessibilityAction(named: pinActionName) {
            guard isModelColumn, reflection.state == .done else { return }
            isPinned.toggle()
        }
    }

    /// Per-column delay schedule from the Sunday brief: column 0 leads
    /// at 0ms, each subsequent column waits 100ms after the previous
    /// finishes (~180ms staggerStep duration). Cumulative delay = idx *
    /// 280ms; capped reasonably for >4 columns.
    private func revealIfReady() {
        guard reflection.state == .done, !hasRevealed else {
            // Idle / generating columns hide. Failed columns reveal immediately
            // so the user sees the error rather than an empty card.
            if reflection.state != .generating {
                hasRevealed = true
            }
            return
        }
        let delayMs = min(800, columnIndex * 280)
        guard !reduceMotion else {
            // Reduce Motion → reveal everything at once with no offset.
            hasRevealed = true
            return
        }
        Task { @MainActor in
            if delayMs > 0 {
                try? await Task.sleep(for: .milliseconds(delayMs))
            }
            withAnimation(Kiln.Motion.staggerStep) {
                hasRevealed = true
            }
        }
    }

    private var header: some View {
        HStack(spacing: Kiln.Space.xs) {
            Circle()
                .fill(Color.primary.opacity(reflection.source.indicatorOpacity))
                .frame(width: 6, height: 6)
            Text(reflection.source.rawValue)
                .font(Kiln.Font.label)
                .kerning(0.44)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer(minLength: 0)
            if isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: Kiln.Icon.small - 3, weight: .semibold))
                    .foregroundStyle(Kiln.Palette.firing)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    .accessibilityHidden(true)
            }
        }
        .animation(Kiln.Motion.microToggle, value: isPinned)
    }

    @ViewBuilder
    private var content: some View {
        switch reflection.source {
        case .userAnswer:
            userAnswerField
        default:
            modelContent
        }
    }

    private var userAnswerField: some View {
        TextField("Type what you would say...", text: $userAnswer, axis: .vertical)
            .textFieldStyle(.plain)
            .font(Kiln.Font.body)
            .foregroundStyle(.primary)
            .lineLimit(3...10)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Your own answer")
    }

    @ViewBuilder
    private var modelContent: some View {
        switch reflection.state {
        case .idle:
            Text("—")
                .font(Kiln.Font.body)
                .foregroundStyle(.tertiary)
        case .generating:
            SkeletonLines()
                .padding(.vertical, Kiln.Space.xxs)
        case .done:
            Text(attributedContinuation)
                .font(Kiln.Font.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(Kiln.Motion.microToggle, value: isHighlighted)
        case let .failed(message):
            VStack(alignment: .leading, spacing: Kiln.Space.xs) {
                Text(message)
                    .font(Kiln.Font.caption)
                    .foregroundStyle(.secondary)
                Button("Retry", action: onRetry)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    private var attributedContinuation: AttributedString {
        var s = AttributedString(reflection.continuation)
        guard isHighlighted else { return s }
        for phrase in reflection.signaturePhrases {
            if let range = s.range(of: phrase) {
                s[range].backgroundColor = Kiln.Palette.firingWash
                s[range].foregroundColor = Kiln.Palette.firing
            }
        }
        return s
    }

    private var pinActionName: String {
        isPinned ? "Hide signature phrases" : "Show signature phrases"
    }

    private var a11yLabel: String {
        switch reflection.state {
        case .idle:
            return "\(reflection.source.rawValue): awaiting generation"
        case .generating:
            return "\(reflection.source.rawValue): generating"
        case .done:
            let phraseSentence = reflection.signaturePhrases.isEmpty
                ? ""
                : " Signature phrases: \(reflection.signaturePhrases.joined(separator: ", "))."
            return "\(reflection.source.rawValue).\(phraseSentence) Response: \(reflection.continuation)"
        case let .failed(message):
            return "\(reflection.source.rawValue) failed: \(message)"
        }
    }
}

// MARK: - Loading skeleton

private struct SkeletonLines: View {
    @State private var pulse = false
    private let widths: [CGFloat] = [0.92, 0.78, 0.60]

    var body: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.xs) {
            ForEach(widths.indices, id: \.self) { i in
                RoundedRectangle(cornerRadius: Kiln.Radius.sm, style: .continuous)
                    .fill(Color.primary.opacity(Kiln.Opacity.trackFill))
                    .frame(height: 12)
                    .scaleEffect(x: widths[i], y: 1, anchor: .leading)
                    .opacity(pulse ? 1.0 : 0.45)
            }
        }
        .onAppear {
            withAnimation(Kiln.Motion.skeletonPulse) {
                pulse = true
            }
        }
        .accessibilityLabel("Generating")
    }
}

// MARK: - Previews

#Preview("Empty — invitation") {
    VoiceMirrorView(model: VoiceMirrorModel.mockEmpty())
        .frame(width: 960)
}

#Preview("Generating — all four columns") {
    VoiceMirrorView(model: VoiceMirrorModel.mockGenerating())
        .frame(width: 960)
}

#Preview("Done — with signature phrases") {
    VoiceMirrorView(model: VoiceMirrorModel.mockDone())
        .frame(width: 960)
}

#Preview("Mixed — one column failed") {
    VoiceMirrorView(model: VoiceMirrorModel.mockMixed())
        .frame(width: 960)
}
