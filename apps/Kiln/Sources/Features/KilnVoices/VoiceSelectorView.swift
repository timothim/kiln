import SwiftUI
import KilnCore

// MARK: - Voice Selector
//
// Compact toolbar-scale picker for switching the active voice. Lives in the
// sidebar's bottom section. Uses `Menu` rather than `Picker` because the
// picker's segmented/radio affordance implies mutual-exclusion as a UI
// primitive, where the selector is really a deliberate "load a different
// fused adapter into Ollama" action the user should take time to reach.
//
// Surface kept flat on purpose — the view is dumb: parent (`SidebarView`)
// owns the `VoicesModel` and wires refresh/activate. That way previews can
// drive the view off fixtures without conjuring an @Observable model.

struct VoiceSelectorView: View {
    let voices: [KilnVoices.Voice]
    let activeID: UUID?
    let onSelect: (UUID) -> Void
    /// Audit M6: optional. If nil, the "Manage voices…" item is
    /// suppressed entirely so the user doesn't tap a no-op. The
    /// dedicated Manage Voices UI is post-hackathon work; until it
    /// ships, callers should pass nil rather than a placeholder
    /// closure that does nothing.
    let onManage: (() -> Void)?

    var body: some View {
        Menu {
            if voices.isEmpty {
                Text("No voices saved yet")
            } else {
                ForEach(voices) { voice in
                    Button {
                        onSelect(voice.id)
                    } label: {
                        if voice.id == activeID {
                            Label(voice.name, systemImage: "checkmark")
                        } else {
                            Text(voice.name)
                        }
                    }
                }
                if onManage != nil {
                    Divider()
                }
            }
            if let onManage {
                Button("Manage voices...", action: onManage)
            }
        } label: {
            label
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel("Active voice: \(activeLabel)")
    }

    @ViewBuilder
    private var label: some View {
        HStack(spacing: Kiln.Space.xs) {
            Circle()
                .fill(activeVoice == nil ? Color.primary.opacity(0.25) : Kiln.Palette.firing)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 0) {
                Text("Voice")
                    .font(Kiln.Font.label)
                    .kerning(0.44)
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                Text(activeLabel)
                    .font(Kiln.Font.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            Image(systemName: "chevron.down")
                .font(.system(size: Kiln.Icon.small, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Kiln.Space.xs)
        .padding(.vertical, Kiln.Space.xxs)
        .background {
            RoundedRectangle(cornerRadius: Kiln.Radius.control, style: .continuous)
                .fill(Color.primary.opacity(Kiln.Opacity.cardFill))
        }
        .contentShape(Rectangle())
    }

    private var activeVoice: KilnVoices.Voice? {
        guard let id = activeID else { return nil }
        return voices.first { $0.id == id }
    }

    private var activeLabel: String {
        activeVoice?.name ?? "No voice loaded"
    }
}

// MARK: - Preview fixtures

private extension KilnVoices.Voice {
    static let previewDrafts = KilnVoices.Voice(
        id: UUID(),
        name: "Tim — drafts",
        ollamaTag: "kiln/tim-drafts:latest",
        createdAt: Date(timeIntervalSinceNow: -3600 * 24 * 2)
    )
    static let previewFormal = KilnVoices.Voice(
        id: UUID(),
        name: "Tim — formal",
        ollamaTag: "kiln/tim-formal:2026-04-18",
        createdAt: Date(timeIntervalSinceNow: -3600 * 24 * 6)
    )
    static let previewNotes = KilnVoices.Voice(
        id: UUID(),
        name: "Tim — notes only",
        ollamaTag: "kiln/tim-notes:2026-04-12",
        createdAt: Date(timeIntervalSinceNow: -3600 * 24 * 12)
    )
    static let previewLibrary: [KilnVoices.Voice] = [.previewDrafts, .previewFormal, .previewNotes]
}

// MARK: - Previews

#Preview("No voices") {
    VoiceSelectorView(
        voices: [],
        activeID: nil,
        onSelect: { _ in },
        onManage: {}
    )
    .padding(Kiln.Space.l)
    .frame(width: 320)
}

#Preview("With active voice") {
    let library = KilnVoices.Voice.previewLibrary
    return VoiceSelectorView(
        voices: library,
        activeID: library.first?.id,
        onSelect: { _ in },
        onManage: {}
    )
    .padding(Kiln.Space.l)
    .frame(width: 320)
}

#Preview("Multiple voices, none active") {
    VoiceSelectorView(
        voices: KilnVoices.Voice.previewLibrary,
        activeID: nil,
        onSelect: { _ in },
        onManage: {}
    )
    .padding(Kiln.Space.l)
    .frame(width: 320)
}
