import XCTest
import KilnCore
@testable import Kiln

@MainActor
final class VoiceMirrorModelTests: XCTestCase {

    final class FakeRunner: SampleCompareRunner, @unchecked Sendable {
        var events: [SampleCompareEvent]

        init(events: [SampleCompareEvent]) {
            self.events = events
        }

        func runStreaming(request _: SampleCompareRequest) -> AsyncThrowingStream<SampleCompareEvent, Error> {
            let events = self.events
            return AsyncThrowingStream { continuation in
                Task.detached {
                    for e in events {
                        continuation.yield(e)
                    }
                    continuation.finish()
                }
            }
        }
    }

    func test_generate_routes_events_into_reflections() async {
        let runner = FakeRunner(events: [
            .ready(version: "0.1.0", mlx: "0.22.0"),
            .generation(.init(variant: .base, prompt: "hi", completion: "base says", tokens: 10, tokensPerSec: 100)),
            .generation(.init(variant: .sft, prompt: "hi", completion: "sft says", tokens: 10, tokensPerSec: 100)),
            .generation(.init(variant: .sftdpo, prompt: "hi", completion: "sftdpo says", tokens: 10, tokensPerSec: 100)),
            .done(interrupted: false, variantsDelivered: [.base, .sft, .sftdpo])
        ])
        let model = VoiceMirrorModel(
            runner: runner,
            sftAdapterURL: URL(fileURLWithPath: "/tmp/sft.safetensors"),
            sftDpoAdapterURL: URL(fileURLWithPath: "/tmp/sftdpo.safetensors")
        )
        model.prompt = "hi"
        model.generate()

        await waitForSettled(model)

        XCTAssertEqual(reflection(model, for: .baseQwen)?.continuation, "base says")
        XCTAssertEqual(reflection(model, for: .sftOnly)?.continuation, "sft says")
        XCTAssertEqual(reflection(model, for: .sftPlusDpo)?.continuation, "sftdpo says")
        XCTAssertEqual(reflection(model, for: .baseQwen)?.state, .done)
    }

    func test_variant_failure_marks_matching_column_failed_only() async {
        let runner = FakeRunner(events: [
            .ready(version: "0.1.0", mlx: "0.22.0"),
            .generation(.init(variant: .base, prompt: "hi", completion: "ok", tokens: 1, tokensPerSec: 1)),
            .variantFailed(variant: .sft, message: "adapter missing", code: "adapter_invalid"),
            .generation(.init(variant: .sftdpo, prompt: "hi", completion: "ok", tokens: 1, tokensPerSec: 1)),
            .done(interrupted: false, variantsDelivered: [.base, .sftdpo])
        ])
        let model = VoiceMirrorModel(
            runner: runner,
            sftAdapterURL: URL(fileURLWithPath: "/tmp/sft.safetensors"),
            sftDpoAdapterURL: URL(fileURLWithPath: "/tmp/sftdpo.safetensors")
        )
        model.prompt = "hi"
        model.generate()

        await waitForSettled(model)

        XCTAssertEqual(reflection(model, for: .baseQwen)?.state, .done)
        XCTAssertEqual(reflection(model, for: .sftPlusDpo)?.state, .done)
        guard case .failed(let msg) = reflection(model, for: .sftOnly)?.state else {
            return XCTFail("expected failed, got \(String(describing: reflection(model, for: .sftOnly)?.state))")
        }
        XCTAssertEqual(msg, "adapter missing")
    }

    // MARK: - helpers

    private func waitForSettled(
        _ model: VoiceMirrorModel,
        timeout: TimeInterval = 2.0,
        file: StaticString = #file,
        line: UInt = #line
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !model.isGenerating { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("timed out waiting for VoiceMirrorModel to settle", file: file, line: line)
    }

    private func reflection(_ model: VoiceMirrorModel, for source: ReflectionSource) -> VoiceReflection? {
        model.reflections.first { $0.source == source }
    }
}
