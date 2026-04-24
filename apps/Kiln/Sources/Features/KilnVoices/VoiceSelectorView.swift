import SwiftUI

// MARK: - Voice Selector
//
// Compact toolbar-scale picker for switching the active voice. Companion to
// `VoiceSplitterView` — splitter is the deliberate library view, selector is
// the one-click swap. Uses `Menu` rather than `Picker` because the picker's
// segmented/radio affordance implies mutual-exclusion as a UI primitive,
// where the selector is really a deliberate "load a different fused adapter
// into Ollama" action the user should take time to reach.

struct VoiceSelectorView: View {
    let voices: [Voice]
    let activeID: Voice.ID?
    let onSelect: (Voice.ID) -> Void
    let onManage: () -> Void

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
                Divider()
            }
            Button("Manage voices...", action: onManage)
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
                .fill(Color.primary.opacity(0.04))
        }
        .contentShape(Rectangle())
    }

    private var activeVoice: Voice? {
        guard let id = activeID else { return nil }
        return voices.first { $0.id == id }
    }

    private var activeLabel: String {
        activeVoice?.name ?? "No voice loaded"
    }
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
    let library = Voice.mockLibrary
    return VoiceSelectorView(
        voices: library,
        activeID: library.first(where: \.isActive)?.id,
        onSelect: { _ in },
        onManage: {}
    )
    .padding(Kiln.Space.l)
    .frame(width: 320)
}

#Preview("Multiple voices, none active") {
    VoiceSelectorView(
        voices: Voice.mockLibrary.map {
            Voice(id: $0.id, name: $0.name, ollamaTag: $0.ollamaTag,
                  createdAt: $0.createdAt, sampleCount: $0.sampleCount,
                  isActive: false)
        },
        activeID: nil,
        onSelect: { _ in },
        onManage: {}
    )
    .padding(Kiln.Space.l)
    .frame(width: 320)
}
