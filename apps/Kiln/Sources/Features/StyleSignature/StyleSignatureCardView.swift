import SwiftUI

// MARK: - Local UI-layer types
//
// Superset of LEAD's KilnCore `StyleSignatureCard.Signature { embedding,
// markdownCard, topLexicalMarkers }`. The UI needs structure the KilnCore
// type doesn't carry (user label, summary prose, weighted phrases, syntactic
// patterns, sentence-length distribution, register). When DATA wires up in
// M7 they can either (a) enrich the Core type to match, or (b) map Core's
// markdown into these fields inside a presenter.

struct StyleSignature: Equatable {
    let userLabel: String                            // "Tim" / "Alex" / username
    let summary: String                              // 2-3 sentences describing the voice
    let signaturePhrases: [SignaturePhrase]          // top ~10, weighted for word-cloud sizing
    let syntacticPatterns: [String]                  // ~5 examples, e.g. "starts with 'Actually,'"
    let sentenceLengthBuckets: [Int]                 // counts per bucket, ascending
    let register: Register
}

struct SignaturePhrase: Equatable, Hashable {
    let text: String
    let weight: Double    // 0...1, drives font size in the word cloud
}

enum Register: String, CaseIterable, Equatable {
    case formal, casual, technical, poetic

    var displayName: String {
        switch self {
        case .formal:    return "Formal"
        case .casual:    return "Casual"
        case .technical: return "Technical"
        case .poetic:    return "Poetic"
        }
    }

    /// Dot opacity for the register badge — a neutral-grey grade, not amber.
    /// Four registers shouldn't all look the same; this nudges them apart.
    var dotOpacity: Double {
        switch self {
        case .formal:    return 0.85
        case .casual:    return 0.45
        case .technical: return 0.70
        case .poetic:    return 0.55
        }
    }
}

// MARK: - Style Signature Card

enum StyleSignatureState: Equatable {
    case loading
    case ready(StyleSignature)
}

/// Shareable summary of the user's voice, produced by the style-extractor at
/// the end of training. Exportable as PNG via `StyleSignatureExporter`.
///
/// The on-disk PNG should look exactly like `CardArt` — the outer
/// `StyleSignatureCardView` adds the export button as chrome, not content.
/// During extraction (M7) the card shows a skeleton so the panel doesn't pop
/// in from nothing.
struct StyleSignatureCardView: View {
    let state: StyleSignatureState

    @State private var exportResult: ExportResult?

    init(state: StyleSignatureState) {
        self.state = state
    }

    init(signature: StyleSignature) {
        self.init(state: .ready(signature))
    }

    private var isReady: Bool {
        if case .ready = state { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: Kiln.Space.m) {
            cardSurface

            HStack(spacing: Kiln.Space.xs) {
                if let message = exportResult?.message {
                    Text(message)
                        .font(Kiln.Font.caption)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
                Spacer(minLength: 0)
                Button {
                    Task { await exportTapped() }
                } label: {
                    Label("Export as PNG", systemImage: "square.and.arrow.up")
                        .font(Kiln.Font.body)
                        .padding(.horizontal, Kiln.Space.xs)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(!isReady)
                .accessibilityLabel("Export style signature as PNG")
            }
        }
        .padding(Kiln.Space.l)
        .animation(Kiln.Motion.standard, value: exportResult)
        .animation(Kiln.Motion.standard, value: isReady)
    }

    @ViewBuilder
    private var cardSurface: some View {
        switch state {
        case .loading:
            StyleSignatureSkeletonCard()
                .transition(.opacity)
        case let .ready(signature):
            StyleSignatureCardArt(signature: signature)
                .transition(.opacity)
        }
    }

    @MainActor
    private func exportTapped() async {
        guard case let .ready(signature) = state else { return }
        let result = StyleSignatureExporter.exportPNG(signature: signature)
        withAnimation(Kiln.Motion.standard) {
            exportResult = result
        }
    }
}

// MARK: - Skeleton card

/// Placeholder art shown while the style extractor runs. Geometry mirrors
/// `StyleSignatureCardArt` so the transition is a crossfade, not a reflow.
private struct StyleSignatureSkeletonCard: View {
    @State private var pulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.m) {
            HStack(alignment: .firstTextBaseline) {
                skeletonBar(width: 140, height: 28)
                Spacer(minLength: 0)
                skeletonBar(width: 100, height: 11)
            }
            VStack(alignment: .leading, spacing: Kiln.Space.xxs) {
                skeletonLine
                skeletonLine
                skeletonBar(width: 380, height: 13)
            }
            Divider().opacity(0.4)
            skeletonSection(labelWidth: 150, chipWidths: [76, 110, 64, 88, 120, 54, 90])
            Divider().opacity(0.4)
            skeletonSection(labelWidth: 180, chipWidths: [180, 220, 160, 200])
            Divider().opacity(0.4)
            HStack(alignment: .bottom, spacing: Kiln.Space.l) {
                VStack(alignment: .leading, spacing: Kiln.Space.xs) {
                    skeletonBar(width: 110, height: 11)
                    skeletonBar(width: 96, height: 40)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: Kiln.Space.xs) {
                    skeletonBar(width: 70, height: 11)
                    skeletonBar(width: 88, height: 24)
                }
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                skeletonBar(width: 110, height: 11)
            }
        }
        .padding(Kiln.Space.l)
        .frame(width: StyleSignatureCardArt.cardWidth,
               height: StyleSignatureCardArt.cardHeight,
               alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: Kiln.Radius.modal, style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Kiln.Radius.modal, style: .continuous)
                .stroke(Color.primary.opacity(Kiln.Opacity.codeFill), lineWidth: 1)
        }
        .opacity(pulse ? 1.0 : 0.55)
        .onAppear {
            withAnimation(Kiln.Motion.skeletonPulse) {
                pulse = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Building your style signature")
    }

    private var skeletonLine: some View {
        RoundedRectangle(cornerRadius: Kiln.Radius.sm, style: .continuous)
            .fill(Color.primary.opacity(Kiln.Opacity.trackFill))
            .frame(maxWidth: .infinity)
            .frame(height: 13)
    }

    private func skeletonBar(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: Kiln.Radius.sm, style: .continuous)
            .fill(Color.primary.opacity(Kiln.Opacity.trackFill))
            .frame(width: width, height: height)
    }

    private func skeletonSection(labelWidth: CGFloat, chipWidths: [CGFloat]) -> some View {
        VStack(alignment: .leading, spacing: Kiln.Space.xs) {
            skeletonBar(width: labelWidth, height: 11)
            FlowLayout(spacing: Kiln.Space.xs) {
                ForEach(chipWidths.indices, id: \.self) { i in
                    Capsule()
                        .fill(Color.primary.opacity(Kiln.Opacity.codeFill))
                        .frame(width: chipWidths[i], height: 20)
                }
            }
        }
    }
}

// MARK: - Card art (the exportable surface)

struct StyleSignatureCardArt: View {
    let signature: StyleSignature

    static let cardWidth:  CGFloat = 640
    static let cardHeight: CGFloat = 480

    /// Section dividers inside the card are intentionally lighter than the
    /// system default — the card already has a regular-material background,
    /// so a full-strength divider reads as a hard line. Same value used for
    /// every divider so they match.
    private static let sectionDividerOpacity: Double = 0.4

    /// Subtle border + chip-fill grade. Color.primary at this opacity
    /// disappears against the card material, so we use it for non-essential
    /// chrome (the outer stroke and the syntactic-pattern chip background).
    private static let chromeOpacity: Double = 0.06

    var body: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.m) {
            header
            summaryBlock
            sectionDivider
            signaturePhrasesBlock
            sectionDivider
            syntacticPatternsBlock
            sectionDivider
            rhythmAndRegisterRow
            Spacer(minLength: 0)
            watermark
        }
        .padding(Kiln.Space.l)
        .frame(width: Self.cardWidth, height: Self.cardHeight, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: Kiln.Radius.modal, style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Kiln.Radius.modal, style: .continuous)
                .stroke(Color.primary.opacity(Self.chromeOpacity), lineWidth: 1)
        }
    }

    private var sectionDivider: some View {
        Divider().opacity(Self.sectionDividerOpacity)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(signature.userLabel)
                .font(Kiln.Font.display)
                .foregroundStyle(.primary)
            Spacer()
            Text("Voice signature")
                .font(Kiln.Font.label)
                .kerning(0.44)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
        }
    }

    private var summaryBlock: some View {
        Text(signature.summary)
            .font(Kiln.Font.body)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var signaturePhrasesBlock: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.xs) {
            SectionLabel(text: "Signature phrases")
            SignaturePhraseCloud(phrases: signature.signaturePhrases)
        }
    }

    private var syntacticPatternsBlock: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.xs) {
            SectionLabel(text: "How you phrase things")
            FlowLayout(spacing: Kiln.Space.xs) {
                ForEach(signature.syntacticPatterns, id: \.self) { pattern in
                    Text(pattern)
                        .font(Kiln.Font.caption)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, Kiln.Space.xs)
                        .padding(.vertical, Kiln.Space.xxs)
                        .background {
                            Capsule().fill(Color.primary.opacity(Self.chromeOpacity))
                        }
                }
            }
        }
    }

    private var rhythmAndRegisterRow: some View {
        HStack(alignment: .bottom, spacing: Kiln.Space.l) {
            VStack(alignment: .leading, spacing: Kiln.Space.xs) {
                SectionLabel(text: "Sentence rhythm")
                SentenceLengthHistogram(buckets: signature.sentenceLengthBuckets)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: Kiln.Space.xs) {
                SectionLabel(text: "Register")
                RegisterBadge(register: signature.register)
            }
        }
    }

    private var watermark: some View {
        HStack {
            Spacer()
            Text("Generated by Kiln")
                .font(Kiln.Font.label)
                .kerning(0.44)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
        }
    }
}

// MARK: - Word cloud

private struct SignaturePhraseCloud: View {
    let phrases: [SignaturePhrase]

    var body: some View {
        FlowLayout(spacing: Kiln.Space.xs) {
            ForEach(phrases, id: \.text) { phrase in
                Text(phrase.text)
                    .font(.system(size: Self.fontSize(for: phrase.weight), weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, Kiln.Space.xs)
                    .padding(.vertical, Kiln.Space.xxs)
                    .background {
                        Capsule().fill(Color.primary.opacity(Kiln.Opacity.codeFill))
                    }
            }
        }
    }

    /// 13pt at weight 0, 24pt at weight 1 — linear. Feels right for a 10-phrase cloud.
    private static func fontSize(for weight: Double) -> CGFloat {
        13 + max(0, min(1, weight)) * 11
    }
}

// MARK: - Histogram

private struct SentenceLengthHistogram: View {
    let buckets: [Int]

    private static let barWidth:  CGFloat = 8
    private static let barSpacing: CGFloat = 3
    private static let height:    CGFloat = 40

    var body: some View {
        let maxCount = max(1, buckets.max() ?? 1)
        HStack(alignment: .bottom, spacing: Self.barSpacing) {
            ForEach(buckets.indices, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.primary.opacity(0.45))
                    .frame(
                        width: Self.barWidth,
                        height: max(3, CGFloat(buckets[i]) / CGFloat(maxCount) * Self.height)
                    )
            }
        }
        .frame(height: Self.height, alignment: .bottom)
        .accessibilityLabel("Sentence-length distribution across \(buckets.count) buckets")
    }
}

// MARK: - Register badge

private struct RegisterBadge: View {
    let register: Register

    var body: some View {
        HStack(spacing: Kiln.Space.xxs) {
            Circle()
                .fill(Color.primary.opacity(register.dotOpacity))
                .frame(width: 6, height: 6)
            Text(register.displayName)
                .font(Kiln.Font.label)
                .kerning(0.44)
                .foregroundStyle(.primary)
                .textCase(.uppercase)
        }
        .padding(.horizontal, Kiln.Space.xs)
        .padding(.vertical, Kiln.Space.xxs)
        .background {
            Capsule().fill(Color.primary.opacity(Kiln.Opacity.trackFill))
        }
        .accessibilityLabel("Dominant register: \(register.displayName)")
    }
}

// MARK: - Flow layout
//
// SwiftUI has no built-in wrapping HStack. This is a thin `Layout` impl for
// the signature-phrase cloud and the syntactic-pattern chip row. Placed here
// instead of DesignSystem because it's feature-scoped; promote to a shared
// module if another feature needs it.
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widestRow: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth && rowWidth > 0 {
                totalHeight += rowHeight + spacing
                widestRow = max(widestRow, rowWidth - spacing)
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        widestRow = max(widestRow, rowWidth - spacing)
        return CGSize(width: min(widestRow, maxWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Previews

#Preview("Card — populated (Tim)") {
    StyleSignatureCardView(signature: .mockTim)
        .frame(width: 720)
}

#Preview("Card — minimal (Alex)") {
    StyleSignatureCardView(signature: .mockAlex)
        .frame(width: 720)
}

#Preview("Card — loading skeleton") {
    StyleSignatureCardView(state: .loading)
        .frame(width: 720)
}

// MARK: - Mocks

extension StyleSignature {
    static let mockTim = StyleSignature(
        userLabel: "Tim",
        summary: "Conversational, direct, lightly ironic. Short sentences with occasional flourishes. Leans on the specific over the abstract.",
        signaturePhrases: [
            SignaturePhrase(text: "honestly", weight: 0.95),
            SignaturePhrase(text: "the one thing", weight: 0.88),
            SignaturePhrase(text: "ship it", weight: 0.80),
            SignaturePhrase(text: "regret not", weight: 0.75),
            SignaturePhrase(text: "actually", weight: 0.70),
            SignaturePhrase(text: "for what it's worth", weight: 0.55),
            SignaturePhrase(text: "worth a shot", weight: 0.48),
            SignaturePhrase(text: "kind of", weight: 0.40),
            SignaturePhrase(text: "fine by me", weight: 0.35),
            SignaturePhrase(text: "go for it", weight: 0.25)
        ],
        syntacticPatterns: [
            "Starts thoughts with \"Actually,\"",
            "Em-dash asides — like this one",
            "Short declaratives. Then a follow-up.",
            "Questions answered with questions?",
            "Ends on the specific detail"
        ],
        sentenceLengthBuckets: [6, 12, 18, 22, 15, 9, 5, 2],
        register: .casual
    )

    static let mockAlex = StyleSignature(
        userLabel: "Alex",
        summary: "Precise and measured. Prefers technical accuracy over flourish. Rarely uses qualifiers.",
        signaturePhrases: [
            SignaturePhrase(text: "observed that", weight: 0.9),
            SignaturePhrase(text: "per the spec", weight: 0.75),
            SignaturePhrase(text: "notably", weight: 0.6),
            SignaturePhrase(text: "in practice", weight: 0.55),
            SignaturePhrase(text: "correctness", weight: 0.4),
            SignaturePhrase(text: "as follows", weight: 0.3)
        ],
        syntacticPatterns: [
            "Leads with the conclusion",
            "Numbered lists over prose",
            "Passive voice for findings",
            "Parentheticals cite evidence"
        ],
        sentenceLengthBuckets: [2, 4, 9, 14, 19, 22, 18, 10],
        register: .technical
    )
}
