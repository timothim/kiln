import SwiftUI
import KilnCore

// MARK: - Voice Splitter (persona config)
//
// Pre-training persona configuration. Surfaces each detected persona in the
// prepared corpus as a toggleable chip so the user can dial in *which parts*
// of their writing get baked into the voice before the Teach button fires.
//
// This is not a voice *library* — that role belongs to `VoiceSelectorView`
// in the sidebar. "Splitter" here carries the original product intent: split
// the corpus by persona, pick the slices that should ship into the fused
// adapter. M8 threads the resulting `VoiceSplit` onto `TrainingRequest`; the
// trainer ignores it for now, but the UI metadata is preserved so M9+ can
// light it up without a view churn.

struct VoiceSplitterView: View {
    @Binding var split: VoiceSplit

    private let columns = [GridItem(.adaptive(minimum: 180), spacing: Kiln.Space.m)]

    var body: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.m) {
            header
            if split.personas.isEmpty {
                emptyState
            } else {
                chipGrid
                summaryRow
            }
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Kiln.Space.m) {
            VStack(alignment: .leading, spacing: Kiln.Space.xxs) {
                Text("Shape your voice")
                    .font(Kiln.Font.title)
                Text("Pick which parts of your writing to include. You can train multiple personas and switch between them later.")
                    .font(Kiln.Font.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if !split.personas.isEmpty {
                selectionActions
            }
        }
    }

    private var selectionActions: some View {
        HStack(spacing: Kiln.Space.xs) {
            Button("Select all") { setAll(selected: true) }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(split.personas.allSatisfy { $0.selected })
            Button("Clear") { setAll(selected: false) }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(split.personas.allSatisfy { !$0.selected })
        }
    }

    private var chipGrid: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: Kiln.Space.m) {
            ForEach(split.personas) { persona in
                PersonaChip(persona: persona) { toggle(persona.id) }
            }
        }
    }

    private var summaryRow: some View {
        let selected = split.selectedPersonas
        let totalSamples = split.selectedSampleCount
        return HStack(spacing: Kiln.Space.xs) {
            Text("Training on \(selected.count) \(selected.count == 1 ? "persona" : "personas") · \(formatCount(totalSamples)) samples")
                .font(Kiln.Font.label)
                .kerning(0.44)
                .textCase(.uppercase)
                .foregroundStyle(selected.isEmpty ? Color.secondary : Color.primary)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Training on \(selected.count) personas, \(totalSamples) total samples")
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.xs) {
            Text("No personas detected")
                .font(Kiln.Font.body.weight(.semibold))
                .foregroundStyle(.primary)
            Text("Your corpus will train as a single voice.")
                .font(Kiln.Font.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Kiln.Space.m)
        .background {
            RoundedRectangle(cornerRadius: Kiln.Radius.card, style: .continuous)
                .fill(Color.primary.opacity(Kiln.Opacity.cardFill))
        }
    }

    // MARK: Mutation

    private func toggle(_ id: Persona.ID) {
        var next = split.personas
        guard let idx = next.firstIndex(where: { $0.id == id }) else { return }
        next[idx].selected.toggle()
        split = VoiceSplit(personas: next)
    }

    private func setAll(selected: Bool) {
        let next = split.personas.map {
            Persona(id: $0.id, label: $0.label, sampleCount: $0.sampleCount, selected: selected)
        }
        split = VoiceSplit(personas: next)
    }

    private func formatCount(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: n)) ?? String(n)
    }
}

// MARK: - Persona Chip

private struct PersonaChip: View {
    let persona: Persona
    let onToggle: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onToggle) {
            VStack(alignment: .leading, spacing: Kiln.Space.xxs) {
                HStack(alignment: .firstTextBaseline, spacing: Kiln.Space.xs) {
                    Image(systemName: persona.selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(persona.selected ? Kiln.Palette.firing : Color.secondary)
                        .font(.system(size: Kiln.Icon.small))
                    Text(persona.label)
                        .font(Kiln.Font.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                }
                Text("\(formatCount(persona.sampleCount)) samples")
                    .font(Kiln.Font.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Kiln.Space.m)
            .background {
                RoundedRectangle(cornerRadius: Kiln.Radius.card, style: .continuous)
                    .fill(persona.selected ? Kiln.Palette.firingWash : Color.primary.opacity(Kiln.Opacity.cardFill))
            }
            .overlay {
                RoundedRectangle(cornerRadius: Kiln.Radius.card, style: .continuous)
                    .stroke(persona.selected ? Kiln.Palette.firing.opacity(0.45) : Color.clear, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: Kiln.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(Kiln.Motion.standard, value: persona.selected)
        .accessibilityLabel("\(persona.label), \(persona.sampleCount) samples, \(persona.selected ? "included" : "excluded")")
        .accessibilityAction(named: persona.selected ? "Exclude" : "Include", onToggle)
    }

    private func formatCount(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: n)) ?? String(n)
    }
}

// MARK: - Previews

/// SwiftUI Previews don't support `@State` at the top level; this wrapper
/// threads a mutable binding through so the chips actually toggle in the
/// canvas. Ported from the Apple sample project pattern.
private struct StatefulPreviewWrapper<Value, Content: View>: View {
    @State private var value: Value
    private let content: (Binding<Value>) -> Content

    init(_ initial: Value, @ViewBuilder content: @escaping (Binding<Value>) -> Content) {
        _value = State(initialValue: initial)
        self.content = content
    }

    var body: some View { content($value) }
}

#Preview("Three personas — mixed selection") {
    StatefulPreviewWrapper(
        VoiceSplit(personas: [
            Persona(label: "drafts", sampleCount: 1_240, selected: true),
            Persona(label: "formal", sampleCount: 860, selected: false),
            Persona(label: "notes", sampleCount: 320, selected: true)
        ])
    ) { binding in
        VoiceSplitterView(split: binding)
            .padding(Kiln.Space.l)
            .frame(width: 780, height: 420)
    }
}

#Preview("Single persona — all selected") {
    StatefulPreviewWrapper(
        VoiceSplit(personas: [
            Persona(label: "drafts", sampleCount: 2_100, selected: true)
        ])
    ) { binding in
        VoiceSplitterView(split: binding)
            .padding(Kiln.Space.l)
            .frame(width: 780, height: 320)
    }
}

#Preview("Empty — no personas detected") {
    StatefulPreviewWrapper(VoiceSplit(personas: [])) { binding in
        VoiceSplitterView(split: binding)
            .padding(Kiln.Space.l)
            .frame(width: 780, height: 320)
    }
}
