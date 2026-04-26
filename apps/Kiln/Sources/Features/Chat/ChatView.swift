import SwiftUI
import KilnCore

/// Chat pane for the completed-project stage. Renders the rolling
/// conversation and a prompt box wired into ``ChatModel``. When an
/// optional ``VoiceInspectorModel`` is supplied (M9.B / Phase 1.5),
/// tapping any assistant message opens the side panel showing the
/// three corpus chunks closest to that response in voice-embedding
/// space.
struct ChatView: View {
    @Bindable var model: ChatModel
    /// Optional Voice Inspector. When nil the side panel is not
    /// rendered — production callers attach it after ingest finishes
    /// (so the corpus is available); previews and idle states pass nil.
    /// Plain ``let`` rather than ``@Bindable`` because the optional
    /// type isn't Bindable-compatible; the view re-renders via the
    /// ``@Observable`` macro on ``VoiceInspectorModel`` itself.
    let inspector: VoiceInspectorModel?

    init(model: ChatModel, inspector: VoiceInspectorModel? = nil) {
        self._model = Bindable(model)
        self.inspector = inspector
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                transcript
                Divider()
                composer
                // Audit M13: reinforce the local-first promise for any
                // viewer who isn't tracking which features cross the
                // boundary. Chat streams from local Ollama; nothing on
                // this surface ever calls Anthropic.
                runningLocallyFooter
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let inspector, inspector.selection != nil {
                VoiceInspectorPanel(
                    selection: inspector.selection,
                    nearestSamples: inspector.nearestSamples,
                    isLoading: inspector.isLoading,
                    onDismiss: { inspector.dismiss() }
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(Kiln.Motion.standard, value: inspector?.selection != nil)
    }

    private var runningLocallyFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .foregroundStyle(.tertiary)
                .font(.system(size: 9))
            Text("Running locally — chat tokens stream from your Ollama daemon, not the cloud.")
                .font(Kiln.Font.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, Kiln.Space.m)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Convert a chat-bubble tap into a Voice Inspector selection.
    /// Only assistant messages open the inspector — tapping a user
    /// bubble does nothing (there's no model output to attribute).
    /// The "highlighted span" defaults to the first sentence of the
    /// reply; full-span selection is a follow-up that needs a richer
    /// gesture than a single tap.
    private func handleBubbleTap(_ message: ChatMessage) {
        guard let inspector, message.role == .assistant else { return }
        let content = message.content
        guard !content.isEmpty else { return }
        let firstSentence = content
            .split(whereSeparator: { ".!?\n".contains($0) })
            .first
            .map(String.init) ?? content
        inspector.selectSpan(
            InspectorSelection(
                generatedSentence: content,
                highlightedSpan: firstSentence,
                logOddsTopTerms: []
            )
        )
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
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    handleBubbleTap(message)
                                }
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
                roleEyebrow
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

    /// Per design package: the assistant's eyebrow carries an `EmberDot`
    /// for the user-facing "this is your trained voice, alive" signal.
    /// User eyebrow is a quiet mono "YOU" — same eyebrow font as
    /// elsewhere, no firing accent.
    @ViewBuilder
    private var roleEyebrow: some View {
        if message.role == .assistant {
            HStack(spacing: Kiln.Space.s2) {
                EmberDot(size: 6)
                Text("YOUR MODEL")
                    .font(Kiln.Font.eyebrow)
                    .kerning(0.4)
                    .foregroundStyle(Kiln.Palette.onSurface3)
            }
        } else {
            Text("YOU")
                .font(Kiln.Font.eyebrow)
                .kerning(0.4)
                .foregroundStyle(Kiln.Palette.onSurface3)
        }
    }

    /// User-side bubble sits on `surface-2` (slightly louder than card-fill,
    /// the chat trip-line). Assistant bubble on `surface-sunken` so the
    /// eye lands on the user's input first, then reads the response.
    private var bubbleFill: Color {
        message.role == .user
            ? Kiln.Palette.surface2
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

#Preview("With Voice Inspector (M9.B / Phase 1.5)") {
    let chatModel = ChatModel.mockConversation()
    let inspector = VoiceInspectorModel.disabled
    return ChatView(model: chatModel, inspector: inspector)
        .frame(width: 1080, height: 520)
}
