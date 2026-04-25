import SwiftUI
import KilnCore

/// Chat pane for the completed-project stage. Renders the rolling
/// conversation and a prompt box wired into ``ChatModel``.
struct ChatView: View {
    @Bindable var model: ChatModel

    var body: some View {
        VStack(spacing: 0) {
            transcript
            Divider()
            composer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Kiln.Space.m) {
                    if model.messages.isEmpty {
                        emptyState
                    } else {
                        ForEach(model.messages) { message in
                            ChatBubble(message: message)
                                .id(message.id)
                        }
                    }
                    if case .failed(let msg) = model.status {
                        failureBanner(message: msg)
                    }
                }
                .padding(Kiln.Space.l)
            }
            .onChange(of: model.messages.last?.content) {
                guard let lastID = model.messages.last?.id else { return }
                withAnimation(Kiln.Motion.standard) {
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Kiln.Space.xs) {
            Spacer(minLength: Kiln.Space.xl)
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: Kiln.Icon.placeholder))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text("Ask your model anything.")
                .font(Kiln.Font.body)
                .foregroundStyle(.secondary)
            Text("It will answer in the voice it learned from your folder.")
                .font(Kiln.Font.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            Spacer(minLength: Kiln.Space.xl)
        }
        .frame(maxWidth: .infinity)
    }

    private func failureBanner(message: String) -> some View {
        HStack(spacing: Kiln.Space.xs) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Kiln.Palette.danger)
                .accessibilityHidden(true)
            Text(message)
                .font(Kiln.Font.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Kiln.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Kiln.Radius.card, style: .continuous)
                .fill(Kiln.Palette.surfaceSunken)
        }
        .accessibilityElement(children: .combine)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: Kiln.Space.m) {
            TextField("Message \(model.modelName)…", text: $model.draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Kiln.Font.body)
                .lineLimit(1...6)
                .padding(.horizontal, Kiln.Space.m)
                .padding(.vertical, Kiln.Space.xs)
                .background {
                    RoundedRectangle(cornerRadius: Kiln.Radius.control, style: .continuous)
                        .fill(Color.primary.opacity(Kiln.Opacity.cardFill))
                }
                .accessibilityLabel("Message composer")

            if case .generating = model.status {
                Button("Stop", role: .destructive) { model.cancel() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityHint("Cancels the current response")
            } else {
                Button {
                    model.send()
                } label: {
                    Label("Send", systemImage: "paperplane.fill")
                        .labelStyle(.iconOnly)
                        .font(Kiln.Font.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, Kiln.Space.m)
                        .padding(.vertical, Kiln.Space.xs)
                        .background {
                            RoundedRectangle(cornerRadius: Kiln.Radius.control, style: .continuous)
                                .fill(Kiln.Palette.firing)
                        }
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!model.canSend)
                .accessibilityLabel("Send message")
            }
        }
        .padding(Kiln.Space.m)
    }
}

private struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: Kiln.Space.m) {
            if message.role == .user {
                Spacer(minLength: Kiln.Space.xl)
            }
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: Kiln.Space.xxs) {
                Text(message.role == .user ? "You" : "Your model")
                    .font(Kiln.Font.label)
                    .kerning(0.44)
                    .textCase(.uppercase)
                    .foregroundStyle(.tertiary)
                Group {
                    if message.content.isEmpty && message.role == .assistant {
                        // Streaming hasn't produced any tokens yet — show a
                        // contextual indicator instead of a bare "…", which
                        // reads as a stalled response on a 4K demo recording.
                        HStack(spacing: Kiln.Space.xs) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Thinking…")
                                .font(Kiln.Font.body)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("Your model is thinking")
                    } else {
                        Text(message.content)
                            .font(Kiln.Font.body)
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(Kiln.Space.m)
                .background {
                    RoundedRectangle(cornerRadius: Kiln.Radius.card, style: .continuous)
                        .fill(bubbleFill)
                }
            }
            if message.role == .assistant {
                Spacer(minLength: Kiln.Space.xl)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message.role == .user
            ? "You said: \(message.content)"
            : "Your model replied: \(message.content)")
    }

    private var bubbleFill: Color {
        message.role == .user
            ? Color.primary.opacity(Kiln.Opacity.trackFill)
            : Kiln.Palette.surfaceSunken
    }
}

#Preview("Empty chat") {
    ChatView(model: ChatModel.mockIdle())
        .frame(width: 760, height: 520)
}

#Preview("Existing conversation") {
    ChatView(model: ChatModel.mockConversation())
        .frame(width: 760, height: 520)
}
