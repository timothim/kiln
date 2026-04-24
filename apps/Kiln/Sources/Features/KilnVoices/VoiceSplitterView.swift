import SwiftUI

// MARK: - Local UI-layer types
//
// Mirrors LEAD's KilnCore `KilnVoices.Voice { id, name, ollamaTag, createdAt }`.
// The UI layer adds `isActive`, `sampleCount`, and `lastUsed` — these are
// presentation concerns that the core library will eventually supply via a
// derived `VoiceStatus` enum. Kept flat here for Phase 3.

struct Voice: Identifiable, Equatable, Hashable {
    let id: UUID
    let name: String
    let ollamaTag: String
    let createdAt: Date
    let sampleCount: Int       // size of the training corpus used for this voice
    let isActive: Bool         // Ollama's currently-served model matches this voice's tag

    init(id: UUID = UUID(),
         name: String,
         ollamaTag: String,
         createdAt: Date,
         sampleCount: Int,
         isActive: Bool = false) {
        self.id = id
        self.name = name
        self.ollamaTag = ollamaTag
        self.createdAt = createdAt
        self.sampleCount = sampleCount
        self.isActive = isActive
    }
}

// MARK: - Voice Splitter
//
// Library view of all saved voices. "Splitter" because it lays the library out
// side-by-side so the user can compare voices before switching — the selector
// is for quick toolbar-scale switching; the splitter is for the deliberate
// "pick which voice I want today" moment.
//
// Card layout over list because each voice has rich metadata (name, sample
// count, created date, active state) and the visual rhythm of a 3-wide grid
// makes even a small library (2-3 voices) feel intentional rather than sparse.

struct VoiceSplitterView: View {
    let voices: [Voice]
    let onActivate: (Voice.ID) -> Void
    let onDelete: (Voice.ID) -> Void

    private let columns = [GridItem(.adaptive(minimum: 220), spacing: Kiln.Space.m)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Kiln.Space.m) {
                header
                if voices.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: Kiln.Space.m) {
                        ForEach(voices) { voice in
                            VoiceCard(
                                voice: voice,
                                onActivate: { onActivate(voice.id) },
                                onDelete: { onDelete(voice.id) }
                            )
                        }
                    }
                }
            }
            .padding(Kiln.Space.l)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.xxs) {
            Text("Your voices")
                .font(Kiln.Font.title)
            Text("Each voice is a fused adapter. Activating one loads it into Ollama.")
                .font(Kiln.Font.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: Kiln.Space.xs) {
            Spacer(minLength: Kiln.Space.xl)
            Text("No voices yet.")
                .font(Kiln.Font.body)
                .foregroundStyle(.secondary)
            Text("Finish a training run to save your first voice here.")
                .font(Kiln.Font.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Spacer(minLength: Kiln.Space.xl)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Voice Card

private struct VoiceCard: View {
    let voice: Voice
    let onActivate: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false
    @State private var confirmingDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.xs) {
            nameRow
            metadataRow
            Spacer(minLength: Kiln.Space.xs)
            actionRow
        }
        .padding(Kiln.Space.m)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(minHeight: 160, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: Kiln.Radius.card, style: .continuous)
                .fill(voice.isActive ? Kiln.Palette.firingWash : Color.primary.opacity(0.04))
        }
        .overlay {
            RoundedRectangle(cornerRadius: Kiln.Radius.card, style: .continuous)
                .stroke(voice.isActive ? Kiln.Palette.firing.opacity(0.45) : Color.clear, lineWidth: 1)
        }
        .onHover { isHovered = $0 }
        .animation(Kiln.Motion.standard, value: voice.isActive)
        .animation(Kiln.Motion.standard, value: isHovered)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(a11yLabel)
    }

    private var nameRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: Kiln.Space.xs) {
            Text(voice.name)
                .font(Kiln.Font.body.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            if voice.isActive {
                ActiveBadge()
            }
        }
    }

    private var metadataRow: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.xxs) {
            Text(voice.ollamaTag)
                .font(Kiln.Font.mono)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Text("\(voice.sampleCount) samples · \(Self.dateFormatter.string(from: voice.createdAt))")
                .font(Kiln.Font.caption)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var actionRow: some View {
        if confirmingDelete {
            HStack(spacing: Kiln.Space.xs) {
                Text("Delete this voice?")
                    .font(Kiln.Font.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("Cancel") { confirmingDelete = false }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                Button("Delete", role: .destructive) {
                    confirmingDelete = false
                    onDelete()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .transition(.opacity)
        } else {
            HStack(spacing: Kiln.Space.xs) {
                Button(voice.isActive ? "Active" : "Activate", action: onActivate)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(voice.isActive)
                Spacer(minLength: 0)
                Button {
                    confirmingDelete = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: Kiln.Icon.small))
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .opacity(isHovered ? 1 : 0.4)
                .accessibilityLabel("Delete voice \(voice.name)")
            }
            .transition(.opacity)
        }
    }

    private var a11yLabel: String {
        let state = voice.isActive ? "active" : "inactive"
        return "Voice \(voice.name), \(state). Tag \(voice.ollamaTag). \(voice.sampleCount) samples."
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
}

// MARK: - Active badge

private struct ActiveBadge: View {
    var body: some View {
        HStack(spacing: Kiln.Space.xxs) {
            Circle()
                .fill(Kiln.Palette.firing)
                .frame(width: 6, height: 6)
            Text("Active")
                .font(Kiln.Font.label)
                .kerning(0.44)
                .foregroundStyle(.primary)
                .textCase(.uppercase)
        }
        .padding(.horizontal, Kiln.Space.xs)
        .padding(.vertical, 2)
        .background {
            Capsule().fill(Kiln.Palette.firingWash)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Previews

#Preview("Empty library") {
    VoiceSplitterView(
        voices: [],
        onActivate: { _ in },
        onDelete: { _ in }
    )
    .frame(width: 780, height: 420)
}

#Preview("Single voice — first run") {
    VoiceSplitterView(
        voices: [Voice.mockTimFirstRun],
        onActivate: { _ in },
        onDelete: { _ in }
    )
    .frame(width: 780, height: 420)
}

#Preview("Three voices — one active") {
    VoiceSplitterView(
        voices: Voice.mockLibrary,
        onActivate: { _ in },
        onDelete: { _ in }
    )
    .frame(width: 860, height: 520)
}

// MARK: - Mocks

extension Voice {
    static let mockTimFirstRun = Voice(
        name: "Tim — drafts",
        ollamaTag: "kiln/tim-drafts:latest",
        createdAt: Date(timeIntervalSinceNow: -3600 * 24 * 2),
        sampleCount: 1_240,
        isActive: true
    )

    static let mockLibrary: [Voice] = [
        Voice(
            name: "Tim — drafts",
            ollamaTag: "kiln/tim-drafts:latest",
            createdAt: Date(timeIntervalSinceNow: -3600 * 24 * 2),
            sampleCount: 1_240,
            isActive: true
        ),
        Voice(
            name: "Tim — formal",
            ollamaTag: "kiln/tim-formal:2026-04-18",
            createdAt: Date(timeIntervalSinceNow: -3600 * 24 * 6),
            sampleCount: 860,
            isActive: false
        ),
        Voice(
            name: "Tim — notes only",
            ollamaTag: "kiln/tim-notes:2026-04-12",
            createdAt: Date(timeIntervalSinceNow: -3600 * 24 * 12),
            sampleCount: 320,
            isActive: false
        )
    ]
}
