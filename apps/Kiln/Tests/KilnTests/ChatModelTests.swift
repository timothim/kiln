import XCTest
import KilnCore
@testable import Kiln

@MainActor
final class ChatModelTests: XCTestCase {

    /// In-memory ``OllamaClient`` that hands back scripted tokens and tracks
    /// the request it saw, so tests can assert both the stream transform and
    /// the request we built.
    final class FakeClient: OllamaClient, @unchecked Sendable {
        var tokens: [String]
        var shouldFail: ChatError?
        var seenRequests: [ChatRequest] = []

        init(tokens: [String] = ["Hi", " there"], shouldFail: ChatError? = nil) {
            self.tokens = tokens
            self.shouldFail = shouldFail
        }

        func streamChat(request: ChatRequest) -> AsyncThrowingStream<ChatStreamEvent, Error> {
            seenRequests.append(request)
            let tokens = self.tokens
            let fail = self.shouldFail
            return AsyncThrowingStream { continuation in
                Task.detached {
                    if let fail {
                        continuation.finish(throwing: fail)
                        return
                    }
                    for t in tokens {
                        continuation.yield(.token(t))
                    }
                    continuation.yield(.done(totalTokens: tokens.count, evalDurationNanos: 0))
                    continuation.finish()
                }
            }
        }

        func listModels() async throws -> [String] { ["kiln-test"] }
    }

    // MARK: - canSend gating

    func test_canSend_requires_nonEmpty_and_not_generating() {
        let model = ChatModel(modelName: "kiln-test", client: FakeClient())
        XCTAssertFalse(model.canSend)
        model.draft = "   "
        XCTAssertFalse(model.canSend)
        model.draft = "hello"
        XCTAssertTrue(model.canSend)
    }

    // MARK: - happy path streaming

    func test_send_streams_tokens_into_assistant_message() async {
        let client = FakeClient(tokens: ["Pick", " one", " thing"])
        let model = ChatModel(modelName: "kiln-test", client: client)
        model.draft = "what should I do?"
        model.send()

        await waitForStatus(model) { $0 == .idle }

        XCTAssertEqual(model.messages.count, 2)
        XCTAssertEqual(model.messages[0].role, .user)
        XCTAssertEqual(model.messages[0].content, "what should I do?")
        XCTAssertEqual(model.messages[1].role, .assistant)
        XCTAssertEqual(model.messages[1].content, "Pick one thing")
        XCTAssertEqual(client.seenRequests.count, 1)
        // Request includes only the user message, not the in-flight assistant placeholder.
        XCTAssertEqual(client.seenRequests.first?.messages.count, 1)
    }

    // MARK: - failure mapping

    func test_send_translates_daemon_unreachable_into_actionable_copy() async {
        let client = FakeClient(shouldFail: .daemonUnreachable(host: "127.0.0.1"))
        let model = ChatModel(modelName: "kiln-test", client: client)
        model.draft = "hi"
        model.send()

        await waitForStatus(model) { status in
            if case .failed = status { return true }
            return false
        }
        guard case .failed(let message) = model.status else {
            return XCTFail("expected .failed, got \(model.status)")
        }
        XCTAssertTrue(message.contains("ollama serve"))
    }

    // MARK: - helpers

    private func waitForStatus(
        _ model: ChatModel,
        timeout: TimeInterval = 2.0,
        file: StaticString = #file,
        line: UInt = #line,
        predicate: @escaping @MainActor (ChatModel.Status) -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate(model.status) { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("timed out; observed \(model.status)", file: file, line: line)
    }
}
