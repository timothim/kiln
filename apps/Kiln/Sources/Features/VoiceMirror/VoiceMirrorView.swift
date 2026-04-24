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
                        .fill(Color.primary.opacity(0.04))
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

    @ViewBuilder
    private var columnsGrid: some View {
        if model.hasAnyContent {
            HStack(alignment: .top, spacing: Kiln.Space.m) {
                ForEach(model.reflections) { reflection in
                    VoiceMirrorColumn(
                        reflection: reflection,
                        userAnswer: $model.userAnswer,
                        onRetry: { model.retry(reflection.source) }
                    )
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        } else {
            emptyState
        }
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
    @Binding var userAnswer: String
    let onRetry: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.xs) {
            header
            content
        }
        .padding(Kiln.Space.m)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: Kiln.Radius.card, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(a11yLabel)
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
        }
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
                .animation(.smooth(duration: 0.25), value: isHovered)
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
        guard isHovered else { return s }
        for phrase in reflection.signaturePhrases {
            if let range = s.range(of: phrase) {
                s[range].backgroundColor = Kiln.Palette.firingWash
                s[range].foregroundColor = Kiln.Palette.firing
            }
        }
        return s
    }

    private var a11yLabel: String {
        switch reflection.state {
        case .idle:
            return "\(reflection.source.rawValue): awaiting generation"
        case .generating:
            return "\(reflection.source.rawValue): generating"
        case .done:
            return "\(reflection.source.rawValue): \(reflection.continuation)"
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
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 12)
                    .scaleEffect(x: widths[i], y: 1, anchor: .leading)
                    .opacity(pulse ? 1.0 : 0.45)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
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
