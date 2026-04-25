import XCTest
@testable import KilnCore

final class OllamaClientTests: XCTestCase {

    // MARK: - Request building

    func test_defaultBaseURLString_parses() throws {
        let url = try XCTUnwrap(URL(string: URLSessionOllamaClient.defaultBaseURLString))
        XCTAssertEqual(url.scheme, "http")
        XCTAssertEqual(url.host, "127.0.0.1")
        XCTAssertEqual(url.port, 11434)
    }

    func test_buildChatURLRequest_sets_method_and_headers() throws {
        let base = URL(string: URLSessionOllamaClient.defaultBaseURLString) ?? URL(fileURLWithPath: "/")
        let chat = ChatRequest(
            model: "kiln-timothee",
            messages: [.init(role: .user, content: "hello")]
        )
        let req = try URLSessionOllamaClient.buildChatURLRequest(baseURL: base, chat: chat)

        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(req.url?.path, "/api/chat")
    }

    func test_buildChatURLRequest_body_carries_messages_and_stream_true() throws {
        let base = URL(string: URLSessionOllamaClient.defaultBaseURLString) ?? URL(fileURLWithPath: "/")
        let chat = ChatRequest(
            model: "kiln-timothee",
            messages: [
                .init(role: .system, content: "sys"),
                .init(role: .user, content: "hi")
            ]
        )
        let req = try URLSessionOllamaClient.buildChatURLRequest(baseURL: base, chat: chat)
        let data = try XCTUnwrap(req.httpBody)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(obj?["model"] as? String, "kiln-timothee")
        XCTAssertEqual(obj?["stream"] as? Bool, true)
        let messages = try XCTUnwrap(obj?["messages"] as? [[String: String]])
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0]["role"], "system")
        XCTAssertEqual(messages[0]["content"], "sys")
        XCTAssertEqual(messages[1]["role"], "user")
        XCTAssertEqual(messages[1]["content"], "hi")
        // No options block when no overrides given.
        XCTAssertNil(obj?["options"])
    }

    func test_buildChatURLRequest_body_includes_options_when_overrides_present() throws {
        let base = URL(string: URLSessionOllamaClient.defaultBaseURLString) ?? URL(fileURLWithPath: "/")
        let chat = ChatRequest(
            model: "kiln-timothee",
            messages: [.init(role: .user, content: "hi")],
            temperature: 0.4,
            topP: 0.8,
            seed: 42
        )
        let req = try URLSessionOllamaClient.buildChatURLRequest(baseURL: base, chat: chat)
        let data = try XCTUnwrap(req.httpBody)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let options = try XCTUnwrap(obj?["options"] as? [String: Any])
        XCTAssertEqual(options["temperature"] as? Double, 0.4)
        XCTAssertEqual(options["top_p"] as? Double, 0.8)
        XCTAssertEqual(options["seed"] as? Int, 42)
    }

    // MARK: - Stream frame decoding

    func test_decode_token_frame() throws {
        let line = #"{"model":"kiln-x","created_at":"2026-04-24T00:00:00Z","message":{"role":"assistant","content":"Hel"},"done":false}"#
        let event = try URLSessionOllamaClient.decode(line: line)
        guard case .token(let s) = event else {
            return XCTFail("expected .token, got \(event)")
        }
        XCTAssertEqual(s, "Hel")
    }

    func test_decode_done_frame_carries_timing() throws {
        let line = #"{"model":"kiln-x","done":true,"eval_count":42,"eval_duration":1000000000}"#
        let event = try URLSessionOllamaClient.decode(line: line)
        guard case .done(let total, let nanos) = event else {
            return XCTFail("expected .done, got \(event)")
        }
        XCTAssertEqual(total, 42)
        XCTAssertEqual(nanos, 1_000_000_000)
    }

    func test_decode_malformed_frame_throws() {
        XCTAssertThrowsError(try URLSessionOllamaClient.decode(line: "{not json"))
    }

    func test_decode_frame_missing_both_content_and_done_throws() {
        // Neither a token nor a terminator — we surface this as a decoding
        // error so the UI can show something went wrong.
        XCTAssertThrowsError(
            try URLSessionOllamaClient.decode(line: #"{"model":"x"}"#)
        )
    }

    // MARK: - Validation

    func test_validate_rejects_non_2xx() throws {
        let url = URL(string: URLSessionOllamaClient.defaultBaseURLString) ?? URL(fileURLWithPath: "/")
        let http = try XCTUnwrap(
            HTTPURLResponse(
                url: url,
                statusCode: 503,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )
        )
        XCTAssertThrowsError(try URLSessionOllamaClient.validate(response: http, bodyHint: "down"))
    }
}
