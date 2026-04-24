import XCTest
import KilnCore
@testable import Kiln

@MainActor
final class ExportModelTests: XCTestCase {

    final class FakeExporter: OllamaExporter, @unchecked Sendable {
        var events: [ExportEvent]
        var throwAfter: Error?

        init(events: [ExportEvent], throwAfter: Error? = nil) {
            self.events = events
            self.throwAfter = throwAfter
        }

        func runStreaming(request _: ExportRequest) -> AsyncThrowingStream<ExportEvent, Error> {
            let events = self.events
            let throwAfter = self.throwAfter
            return AsyncThrowingStream { continuation in
                Task.detached {
                    for e in events {
                        continuation.yield(e)
                    }
                    if let t = throwAfter {
                        continuation.finish(throwing: t)
                    } else {
                        continuation.finish()
                    }
                }
            }
        }
    }

    private func sampleRequest() -> ExportRequest {
        ExportRequest(
            model: "mlx-community/Qwen2.5-3B-Instruct-4bit",
            adapterURL: URL(fileURLWithPath: "/tmp/adapters.safetensors"),
            runDir: URL(fileURLWithPath: "/tmp/run"),
            userName: "tim",
            outputName: "kiln-tim",
            llamaCppDir: URL(fileURLWithPath: "/tmp/llama.cpp")
        )
    }

    func test_happy_path_transitions_through_stages_to_completed() async {
        let exporter = FakeExporter(events: [
            .ready(version: "0.1.0", mlx: "0.22.0"),
            .stageDone(stage: .fuse, artifact: "/tmp/fused", interrupted: false),
            .stageDone(stage: .gguf, artifact: "/tmp/out.gguf", interrupted: false),
            .stageDone(stage: .ollama, artifact: "kiln-tim", interrupted: false)
        ])
        let model = ExportModel(exporter: exporter)
        model.start(request: sampleRequest())

        await waitForStatus(model) { status in
            if case .completed = status { return true }
            return false
        }
        guard case .completed(let name) = model.status else {
            return XCTFail("expected .completed, got \(model.status)")
        }
        XCTAssertEqual(name, "kiln-tim")
        XCTAssertEqual(model.progress.fuse, .done(artifact: "/tmp/fused"))
        XCTAssertEqual(model.progress.gguf, .done(artifact: "/tmp/out.gguf"))
        XCTAssertEqual(model.progress.modelfile, .done(artifact: "Modelfile"))
        XCTAssertEqual(model.progress.ollama, .done(artifact: "kiln-tim"))
    }

    func test_stageFailed_moves_model_to_failed_with_message() async {
        let exporter = FakeExporter(events: [
            .ready(version: "0.1.0", mlx: "0.22.0"),
            .stageDone(stage: .fuse, artifact: "/tmp/fused", interrupted: false),
            .stageFailed(
                stage: .gguf,
                code: "gguf_failed",
                message: "llama.cpp not found",
                recoverable: true
            )
        ])
        let model = ExportModel(exporter: exporter)
        model.start(request: sampleRequest())

        await waitForStatus(model) { status in
            if case .failed = status { return true }
            return false
        }
        guard case .failed(let message, let recoverable) = model.status else {
            return XCTFail("expected .failed, got \(model.status)")
        }
        XCTAssertEqual(message, "llama.cpp not found")
        XCTAssertTrue(recoverable)
        XCTAssertEqual(model.progress.gguf, .failed(message: "llama.cpp not found"))
    }

    func test_interrupted_stage_flips_to_failed() async {
        let exporter = FakeExporter(events: [
            .ready(version: "0.1.0", mlx: "0.22.0"),
            .stageDone(stage: .fuse, artifact: "/tmp/fused", interrupted: true)
        ])
        let model = ExportModel(exporter: exporter)
        model.start(request: sampleRequest())

        await waitForStatus(model) { status in
            if case .failed = status { return true }
            return false
        }
        guard case .failed(_, let recoverable) = model.status else {
            return XCTFail("expected .failed, got \(model.status)")
        }
        XCTAssertTrue(recoverable)
    }

    // MARK: - helpers

    private func waitForStatus(
        _ model: ExportModel,
        timeout: TimeInterval = 2.0,
        file: StaticString = #file,
        line: UInt = #line,
        predicate: @escaping @MainActor (ExportModel.Status) -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate(model.status) { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("timed out; observed \(model.status)", file: file, line: line)
    }
}
