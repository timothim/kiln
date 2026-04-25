import SwiftUI

/// Stage 3 — training complete. Confident header, stat grid, the built-in
/// chat pane, the Terminal hand-off line in monospace, and a "Share voice"
/// button that opens the Kiln Share export sheet. No exclamation marks (one
/// is reserved for the final export-success moment when Ollama confirms).
struct CompleteStageView: View {
    let project: Project
    var chatModel: ChatModel?
    let onOpenChat: () -> Void
    let onCloseChat: () -> Void

    @State private var isShareSheetPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.l) {
            header
            statsRow
                .frame(maxWidth: 640)
                .padding(.top, Kiln.Space.xs)

            if let chatModel {
                ChatView(model: chatModel)
                    .frame(maxWidth: .infinity)
                    .background {
                        RoundedRectangle(cornerRadius: Kiln.Radius.card, style: .continuous)
                            .fill(Kiln.Palette.surfaceSunken)
                    }
            } else {
                chatEntry
            }

            terminalLine
                .padding(.top, Kiln.Space.xs)
            shareRow
                .padding(.top, Kiln.Space.xs)
            Spacer(minLength: 0)
        }
        .padding(Kiln.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $isShareSheetPresented) {
            ShareExportSheet(
                voiceName: project.name,
                voiceTag: "kiln/\(project.slug):latest",
                onExport: { options in
                    await ShareController.runExport(project: project, options: options)
                },
                onCancel: { isShareSheetPresented = false }
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.xs) {
            HStack(spacing: Kiln.Space.xs) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: Kiln.Icon.heading))
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text("\(project.name) is ready")
                    .font(Kiln.Font.display)
                    .lineLimit(2)
                Spacer(minLength: 0)
                StageBadge(stage: project.stage)
                if chatModel != nil {
                    Button("Close chat", action: onCloseChat)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityLabel("Close chat")
                }
            }
            Text("Your model is trained. Start chatting, hand off to Terminal, or share the voice as a `.kiln` bundle.")
                .font(Kiln.Font.body)
                .foregroundStyle(.secondary)
        }
    }

    private var statsRow: some View {
        HStack(spacing: Kiln.Space.m) {
            Stat(label: "Model", value: "Qwen2.5-\(project.modelSize.displayName)")
            Stat(label: "Chunks", value: chunksValue)
            Stat(
                label: "Trained",
                value: project.lastTrained
                    .map { $0.formatted(.relative(presentation: .named)) }
                    ?? "just now"
            )
        }
    }

    private var chunksValue: String {
        if let kept = project.keptChunks, let total = project.totalChunks {
            return "\(kept.formatted()) of \(total.formatted())"
        }
        return "—"
    }

    private var chatEntry: some View {
        HStack(alignment: .center, spacing: Kiln.Space.m) {
            VStack(alignment: .leading, spacing: Kiln.Space.xs) {
                Text("Talk to your model")
                    .font(Kiln.Font.title)
                Text("Chat opens a rolling conversation backed by the Ollama daemon on this machine.")
                    .font(Kiln.Font.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Kiln.Space.m)
            Button(action: onOpenChat) {
                Label("Open chat", systemImage: "bubble.left.and.bubble.right.fill")
                    .font(Kiln.Font.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, Kiln.Space.m)
                    .padding(.vertical, Kiln.Space.xs)
                    .background(
                        RoundedRectangle(cornerRadius: Kiln.Radius.control, style: .continuous)
                            .fill(Kiln.Palette.firing)
                    )
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .accessibilityLabel("Open chat with your model")
        }
        .padding(Kiln.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Kiln.Radius.card, style: .continuous)
                .fill(Kiln.Palette.surfaceSunken)
        }
    }

    private var terminalLine: some View {
        HStack(spacing: Kiln.Space.xs) {
            Image(systemName: "terminal")
                .font(Kiln.Font.body)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("ollama run kiln-\(project.slug)")
                .font(Kiln.Font.mono)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
        .padding(.horizontal, Kiln.Space.m)
        .padding(.vertical, Kiln.Space.xs)
        .background {
            RoundedRectangle(cornerRadius: Kiln.Radius.control, style: .continuous)
                .fill(Color.primary.opacity(Kiln.Opacity.codeFill))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Terminal command: ollama run kiln dash \(project.slug)")
    }

    private var shareRow: some View {
        HStack(spacing: Kiln.Space.sm) {
            Button {
                isShareSheetPresented = true
            } label: {
                Label("Share voice", systemImage: "square.and.arrow.up")
                    .padding(.horizontal, Kiln.Space.xs)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .controlSize(.regular)
            .disabled(project.trainingReport == nil)
            .accessibilityHint("Package this voice as a .kiln bundle you can share.")

            if project.trainingReport == nil {
                Text("Finish training to enable sharing.")
                    .font(Kiln.Font.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
