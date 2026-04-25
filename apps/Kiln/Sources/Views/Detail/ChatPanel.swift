import SwiftUI
import AppKit

/// Terminal hand-off card for the Complete detail pane. One click copies the
/// `ollama run` command for the trained model. Kiln is a forge, not a chat
/// app — the chat itself lives in Terminal.
struct ChatPanel: View {
    let project: Project

    @State private var copied = false

    private var command: String { "ollama run kiln-\(project.slug)" }

    var body: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.m) {
            Text("Chat")
                .font(Kiln.Font.title)

            Text("Your model is in Ollama. Talk to it from Terminal.")
                .font(Kiln.Font.caption)
                .foregroundStyle(.secondary)

            commandBlock
                .padding(.top, Kiln.Space.xs - 2)

            copyButton
                .padding(.top, Kiln.Space.xxs)
        }
        .padding(Kiln.Space.m)
    }

    private var commandBlock: some View {
        HStack(alignment: .center, spacing: Kiln.Space.xs) {
            Image(systemName: "terminal")
                .font(Kiln.Font.body)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(command)
                .font(Kiln.Font.mono)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, Kiln.Space.m)
        .padding(.vertical, Kiln.Space.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Kiln.Radius.control, style: .continuous)
                .fill(Color.primary.opacity(Kiln.Opacity.codeFill))
        }
    }

    private var copyButton: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
            withAnimation(Kiln.Motion.standard) { copied = true }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.5))
                withAnimation(Kiln.Motion.standard) { copied = false }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(Kiln.Font.caption)
                Text(copied ? "Copied" : "Copy command")
                    .font(Kiln.Font.body)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .accessibilityLabel(copied ? "Command copied" : "Copy Terminal command")
    }
}
