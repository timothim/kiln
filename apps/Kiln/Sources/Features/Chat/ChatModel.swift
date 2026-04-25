import Foundation
import KilnCore
import Observation

/// Observable state for ``ChatView``. Owns a short conversation history and
/// runs streaming requests through an injected ``OllamaClient``. Keeping the
/// client behind a protocol lets tests and SwiftUI previews plug in a mock.
@Observable
@MainActor
final class ChatModel {
    enum Status: Equatable {
        case idle
        case generating
        case failed(message: String)
    }

    var draft: String = ""
    var messages: [ChatMessage] = []
    var status: Status = .idle
    var modelName: String

    private let client: OllamaClient
    private var streamTask: Task<Void, Never>?

    init(modelName: String, client: OllamaClient) {
        self.modelName = modelName
        self.client = client
    }

    var canSend: Bool {
        switch status {
        case .idle, .failed:
            return !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .generating:
            return false
        }
    }

    func send() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        draft = ""
        let userMessage = ChatMessage(role: .user, content: trimmed)
        messages.append(userMessage)

        let placeholder = ChatMessage(role: .assistant, content: "")
        messages.append(placeholder)
        let assistantID = placeholder.id

        status = .generating

        let request = ChatRequest(
            model: modelName,
            messages: messages.filter { $0.id != assistantID }
        )
        let client = self.client
        streamTask = Task { [weak self] in
            do {
                for try await event in client.streamChat(request: request) {
                    if Task.isCancelled { break }
                    switch event {
                    case .token(let fragment):
                        self?.append(fragment, to: assistantID)
                    case .done:
                        break
                    }
                }
                self?.status = .idle
            } catch let error as ChatError {
                self?.fail(error)
            } catch is CancellationError {
                self?.status = .idle
            } catch {
                self?.status = .failed(message: error.localizedDescription)
            }
        }
    }

    func cancel() {
        streamTask?.cancel()
        streamTask = nil
        status = .idle
    }

    func clear() {
        cancel()
        messages.removeAll()
    }

    // MARK: - Helpers

    private func append(_ fragment: String, to messageID: UUID) {
        guard let idx = messages.firstIndex(where: { $0.id == messageID }) else { return }
        messages[idx].content.append(fragment)
    }

    private func fail(_ error: ChatError) {
        switch error {
        case .daemonUnreachable(let host):
            status = .failed(message: "Ollama isn't running on \(host). Start it with `ollama serve`.")
        case .httpStatus(let code, _):
            status = .failed(message: "Ollama returned HTTP \(code).")
        case .decodingFailed:
            status = .failed(message: "Couldn't read Ollama's response.")
        case .missingModel(let name):
            status = .failed(message: "No model named '\(name)' is installed. Export it first.")
        }
    }
}

// MARK: - Preview factories

extension ChatModel {
    /// Deterministic preview client — emits a fixed greeting one token at a
    /// time so Xcode previews and tests look alive without needing a running
    /// daemon.
    final class PreviewClient: OllamaClient, @unchecked Sendable {
        let tokens: [String]

        init(tokens: [String] = ["Hi", "!", " How", " can", " I", " help", "?"]) {
            self.tokens = tokens
        }

        func streamChat(request _: ChatRequest) -> AsyncThrowingStream<ChatStreamEvent, Error> {
            AsyncThrowingStream { continuation in
                let tokens = self.tokens
                Task.detached {
                    for t in tokens {
                        try? await Task.sleep(for: .milliseconds(60))
                        continuation.yield(.token(t))
                    }
                    continuation.yield(.done(totalTokens: tokens.count, evalDurationNanos: 0))
                    continuation.finish()
                }
            }
        }

        func listModels() async throws -> [String] {
            ["kiln-preview"]
        }
    }

    static func mockIdle() -> ChatModel {
        ChatModel(modelName: "kiln-preview", client: PreviewClient())
    }

    static func mockConversation() -> ChatModel {
        let m = ChatModel(modelName: "kiln-preview", client: PreviewClient())
        m.messages = [
            ChatMessage(role: .user, content: "What should I work on this week?"),
            ChatMessage(
                role: .assistant,
                content: "Pick the one thing you'd regret not shipping. Start there — the rest resolves around it."
            )
        ]
        return m
    }
}
