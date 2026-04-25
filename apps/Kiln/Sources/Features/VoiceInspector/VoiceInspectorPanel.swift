import SwiftUI

// MARK: - Local UI-layer types
//
// Mirrors LEAD's KilnCore `VoiceInspector.Attribution` in spirit — the UI uses
// resolved `NearestSample` rows instead of bare `nearestChunkIDs` so the panel
// can render source / excerpt / similarity without a second fetch. DATA will
// resolve the IDs into samples at the presenter layer during M9 wire-up.

struct InspectorSelection: Equatable {
    let generatedSentence: String      // full generated continuation
    let highlightedSpan: String        // substring of generatedSentence that was clicked
    let logOddsTopTerms: [String]      // top terms that pushed the model toward this span
}

enum CorpusSource: String, Equatable {
    case messages, notes, mail, obsidian, dropFolder

    var displayName: String {
        switch self {
        case .messages:   return "Messages"
        case .notes:      return "Notes"
        case .mail:       return "Mail"
        case .obsidian:   return "Obsidian"
        case .dropFolder: return "Drop folder"
        }
    }

    var systemImage: String {
        switch self {
        case .messages:   return "message.fill"
        case .notes:      return "note.text"
        case .mail:       return "envelope.fill"
        case .obsidian:   return "square.grid.3x3.fill"
        case .dropFolder: return "folder.fill"
        }
    }
}

struct NearestSample: Identifiable, Equatable {
    let id: String
    let source: CorpusSource
    let sourceDetail: String            // "From: a.chen@…", "Note: Weekly plan", etc.
    let excerpt: String                 // 1-2 sentences, up to ~240 chars
    let similarity: Double              // 0...1, cosine similarity from style-extractor embedding
    let timestamp: Date?
}

// MARK: - Voice Inspector Panel
//
// 320pt slide-in panel. Call site hides/shows via a parent's state; the panel
// itself handles empty, loading, and populated states. Width is fixed so the
// column of nearest-sample cards reads as a consistent rhythm rather than
// reflowing with the main content.

struct VoiceInspectorPanel: View {
    let selection: InspectorSelection?
    let nearestSamples: [NearestSample]
    let isLoading: Bool
    let onDismiss: () -> Void

    static let panelWidth: CGFloat = 320

    var body: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.m) {
            header
            Divider().opacity(0.4)
            if let selection {
                selectionBlock(selection)
                Divider().opacity(0.4)
                nearestBlock
            } else {
                emptyState
            }
            Spacer(minLength: 0)
            footer
        }
        .padding(Kiln.Space.m)
        .frame(width: Self.panelWidth, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background {
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea(edges: .vertical)
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Voice inspector")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Why this phrase")
                .font(Kiln.Font.title)
            Spacer(minLength: 0)
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: Kiln.Icon.small, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Dismiss inspector")
        }
    }

    private func selectionBlock(_ selection: InspectorSelection) -> some View {
        VStack(alignment: .leading, spacing: Kiln.Space.xs) {
            SectionLabel(text: "Selected")
            Text(highlightedAttributed(selection))
                .font(Kiln.Font.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            if !selection.logOddsTopTerms.isEmpty {
                VStack(alignment: .leading, spacing: Kiln.Space.xxs) {
                    SectionLabel(text: "Top contributing terms")
                    TermChipRow(terms: selection.logOddsTopTerms)
                }
                .padding(.top, Kiln.Space.xxs)
            }
        }
    }

    private func highlightedAttributed(_ selection: InspectorSelection) -> AttributedString {
        var string = AttributedString(selection.generatedSentence)
        if let range = string.range(of: selection.highlightedSpan) {
            string[range].backgroundColor = Kiln.Palette.firingWash
            string[range].foregroundColor = Kiln.Palette.firing
        }
        return string
    }

    @ViewBuilder
    private var nearestBlock: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.xs) {
            SectionLabel(text: "Nearest samples from your corpus")
            if isLoading {
                InspectorLoadingRows()
            } else if nearestSamples.isEmpty {
                Text("No nearby samples — the span likely came from the base model.")
                    .font(Kiln.Font.caption)
                    .foregroundStyle(.tertiary)
            } else {
                VStack(alignment: .leading, spacing: Kiln.Space.xs) {
                    ForEach(nearestSamples) { sample in
                        NearestSampleRow(sample: sample)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.xs) {
            Text("Select a phrase")
                .font(Kiln.Font.body)
                .foregroundStyle(.secondary)
            Text("Click any span of generated text to see the training samples closest to it in your voice-extractor embedding.")
                .font(Kiln.Font.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        Text("Attribution is approximate — nearest-neighbor on the style embedding, not a causal explanation.")
            .font(Kiln.Font.label)
            .kerning(0.44)
            .foregroundStyle(.tertiary)
            .textCase(.uppercase)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Nearest sample row

private struct NearestSampleRow: View {
    let sample: NearestSample

    var body: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.xxs) {
            HStack(spacing: Kiln.Space.xxs) {
                Image(systemName: sample.source.systemImage)
                    .font(.system(size: Kiln.Icon.small - 3, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(sample.source.displayName)
                    .font(Kiln.Font.label)
                    .kerning(0.44)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer(minLength: 0)
                SimilarityPill(value: sample.similarity)
            }
            Text(sample.sourceDetail)
                .font(Kiln.Font.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(sample.excerpt)
                .font(Kiln.Font.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(4)
        }
        .padding(Kiln.Space.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Kiln.Radius.sm, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(a11yLabel)
    }

    private var a11yLabel: String {
        let pct = Int((sample.similarity * 100).rounded())
        return "\(sample.source.displayName), \(sample.sourceDetail). Similarity \(pct) percent. \(sample.excerpt)"
    }
}

private struct SimilarityPill: View {
    let value: Double

    var body: some View {
        let pct = Int((max(0, min(1, value)) * 100).rounded())
        Text("\(pct)%")
            .font(Kiln.Font.label)
            .kerning(0.44)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .padding(.horizontal, Kiln.Space.xxs)
            .padding(.vertical, 2)
            .background {
                Capsule().fill(Color.primary.opacity(0.08))
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Term chip row

private struct TermChipRow: View {
    let terms: [String]

    var body: some View {
        HStack(spacing: Kiln.Space.xxs) {
            ForEach(terms, id: \.self) { term in
                Text(term)
                    .font(Kiln.Font.label)
                    .kerning(0.44)
                    .foregroundStyle(.primary)
                    .textCase(.uppercase)
                    .padding(.horizontal, Kiln.Space.xxs)
                    .padding(.vertical, 2)
                    .background {
                        Capsule().fill(Color.primary.opacity(0.06))
                    }
            }
        }
    }
}

// MARK: - Loading rows

private struct InspectorLoadingRows: View {
    @State private var pulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.xs) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Kiln.Radius.sm, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 64)
                    .opacity(pulse ? 1.0 : 0.55)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .accessibilityLabel("Loading nearest samples")
    }
}

// MARK: - Previews

#Preview("Empty — no selection") {
    VoiceInspectorPanel(
        selection: nil,
        nearestSamples: [],
        isLoading: false,
        onDismiss: {}
    )
    .frame(height: 640)
}

#Preview("Loading") {
    VoiceInspectorPanel(
        selection: .mockPhrase,
        nearestSamples: [],
        isLoading: true,
        onDismiss: {}
    )
    .frame(height: 640)
}

#Preview("Populated") {
    VoiceInspectorPanel(
        selection: .mockPhrase,
        nearestSamples: NearestSample.mockFive,
        isLoading: false,
        onDismiss: {}
    )
    .frame(height: 640)
}

#Preview("Base-model span — no nearby samples") {
    VoiceInspectorPanel(
        selection: .mockGenericPhrase,
        nearestSamples: [],
        isLoading: false,
        onDismiss: {}
    )
    .frame(height: 640)
}

// MARK: - Mocks

extension InspectorSelection {
    static let mockPhrase = InspectorSelection(
        generatedSentence: "Pick the one thing you would regret not shipping. Start there — the rest resolves around it.",
        highlightedSpan: "regret not shipping",
        logOddsTopTerms: ["regret", "shipping", "one thing"]
    )

    static let mockGenericPhrase = InspectorSelection(
        generatedSentence: "There are several approaches worth considering.",
        highlightedSpan: "worth considering",
        logOddsTopTerms: []
    )
}

extension NearestSample {
    static let mockFive: [NearestSample] = [
        NearestSample(
            id: "msg-1024",
            source: .messages,
            sourceDetail: "To: Aisha · 2026-03-14",
            excerpt: "honestly the question is always what you would regret not shipping. everything else is noise.",
            similarity: 0.92,
            timestamp: nil
        ),
        NearestSample(
            id: "note-88",
            source: .notes,
            sourceDetail: "Note: Weekly plan · 2026-03-10",
            excerpt: "pick one thing. ship it. repeat. the rest resolves around whatever you ship first.",
            similarity: 0.87,
            timestamp: nil
        ),
        NearestSample(
            id: "drop-214",
            source: .dropFolder,
            sourceDetail: "journal/2026-02-27.md",
            excerpt: "I keep coming back to the regret test — would I regret not shipping this on friday?",
            similarity: 0.81,
            timestamp: nil
        ),
        NearestSample(
            id: "msg-1141",
            source: .messages,
            sourceDetail: "To: Dev team · 2026-02-18",
            excerpt: "start with the thing you would regret skipping, not the thing that is easiest.",
            similarity: 0.74,
            timestamp: nil
        ),
        NearestSample(
            id: "note-62",
            source: .notes,
            sourceDetail: "Note: Principles · 2026-01-05",
            excerpt: "shipping beats polishing. the rest of the plan finds itself once something is out the door.",
            similarity: 0.68,
            timestamp: nil
        )
    ]
}
