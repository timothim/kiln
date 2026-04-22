import SwiftUI

/// Full-window launch view. One respiring amber card, one sentence, one hint.
/// This is the first thing the user ever sees — it has to breathe, not shout.
struct EmptyDropView: View {
    let model: AppModel

    @State private var isTargeted = false

    var body: some View {
        ZStack {
            Color.clear

            VStack(spacing: Kiln.Space.m) {
                DropHintIcon()

                VStack(spacing: Kiln.Space.xs) {
                    Text("Drop a folder to teach a model about you.")
                        .font(Kiln.Font.display)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Notes, messages, writing — anything in your voice.")
                        .font(Kiln.Font.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 6) {
                    Text("or press")
                    Text("⌘N")
                        .font(Kiln.Font.mono)
                        .foregroundStyle(.secondary)
                    Text("to start blank")
                }
                .font(Kiln.Font.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, Kiln.Space.xs)
            }
            .padding(.horizontal, Kiln.Space.l)
            .padding(.vertical, Kiln.Space.l + Kiln.Space.s)
            .frame(maxWidth: Kiln.Layout.dropCardMaxWidth)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: Kiln.Radius.modal, style: .continuous)
                        .fill(.regularMaterial)
                    RoundedRectangle(cornerRadius: Kiln.Radius.modal, style: .continuous)
                        .fill(isTargeted ? Kiln.Palette.accentWash : Color.clear)
                }
            }
            .emberGlow(cornerRadius: Kiln.Radius.modal)
            .scaleEffect(isTargeted ? 1.01 : 1.0)
            .animation(Kiln.Motion.standard, value: isTargeted)
            .dropFolder(isTargeted: $isTargeted) { url in
                withAnimation(Kiln.Motion.standard) {
                    model.ingest(folderURL: url)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Drop a folder to teach a model about you")
            .accessibilityHint("Press Command N to start blank")
            .accessibilityAddTraits(.isButton)
            .padding(Kiln.Space.l)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
