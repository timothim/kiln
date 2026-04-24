import XCTest
@testable import KilnCore

final class SampleCompareRunnerTests: XCTestCase {

    // MARK: - compareArgs

    func test_compareArgs_contains_required_flags() {
        let request = SampleCompareRequest(
            model: "mlx-community/Qwen2.5-3B-Instruct-4bit",
            prompt: "hi",
            variants: [
                .init(variant: .base, adapterPath: nil),
                .init(variant: .sft, adapterPath: URL(fileURLWithPath: "/tmp/sft.safetensors")),
                .init(variant: .sftdpo, adapterPath: URL(fileURLWithPath: "/tmp/sftdpo.safetensors"))
            ],
            maxTokens: 128,
            temperature: 0.5,
            topP: 0.8,
            seed: 17
        )
        let args = SubprocessSampleCompareRunner.compareArgs(for: request)

        XCTAssertEqual(args.first, "sample-compare")
        XCTAssertTrue(args.contains("--model"))
        XCTAssertTrue(args.contains("mlx-community/Qwen2.5-3B-Instruct-4bit"))
        XCTAssertTrue(args.contains("--prompt"))
        XCTAssertTrue(args.contains("hi"))
        XCTAssertTrue(args.contains("--max-tokens"))
        XCTAssertTrue(args.contains("128"))
        XCTAssertTrue(args.contains("--temp"))
        XCTAssertTrue(args.contains("0.5"))
        XCTAssertTrue(args.contains("--top-p"))
        XCTAssertTrue(args.contains("0.8"))
        XCTAssertTrue(args.contains("--seed"))
        XCTAssertTrue(args.contains("17"))

        // Each --variant is emitted in a repeatable "tag[:path]" form.
        let variants = Self.collect(args, flag: "--variant")
        XCTAssertEqual(variants.count, 3)
        XCTAssertTrue(variants.contains("base"))
        XCTAssertTrue(variants.contains("sft:/tmp/sft.safetensors"))
        XCTAssertTrue(variants.contains("sftdpo:/tmp/sftdpo.safetensors"))
    }

    func test_compareArgs_includes_generator_entry_when_set() {
        let request = SampleCompareRequest(
            prompt: "hello",
            variants: [.init(variant: .base, adapterPath: nil)],
            generatorEntry: "/tmp/fake.py"
        )
        let args = SubprocessSampleCompareRunner.compareArgs(for: request)
        XCTAssertTrue(args.contains("--generator-entry"))
        XCTAssertTrue(args.contains("/tmp/fake.py"))
    }

    func test_variantSpec_cliToken_matches_wire_format() {
        XCTAssertEqual(
            SampleCompareRequest.VariantSpec(variant: .base, adapterPath: nil).cliToken(),
            "base"
        )
        XCTAssertEqual(
            SampleCompareRequest.VariantSpec(
                variant: .sft,
                adapterPath: URL(fileURLWithPath: "/var/a.safetensors")
            ).cliToken(),
            "sft:/var/a.safetensors"
        )
        XCTAssertEqual(
            SampleCompareRequest.VariantSpec(
                variant: .sftdpo,
                adapterPath: URL(fileURLWithPath: "/var/b.safetensors")
            ).cliToken(),
            "sftdpo:/var/b.safetensors"
        )
    }

    // MARK: - decode

    func test_decode_ready_event() throws {
        let line = #"{"event":"ready","version":"0.1.0","mlx":"0.22.0"}"#
        let event = try SubprocessSampleCompareRunner.decode(line: line, promptEcho: "")
        guard case .ready(let version, let mlx) = event else {
            return XCTFail("expected .ready, got \(event)")
        }
        XCTAssertEqual(version, "0.1.0")
        XCTAssertEqual(mlx, "0.22.0")
    }

    func test_decode_generation_event_maps_prompt_id_to_variant() throws {
        let line = #"{"event":"generation","prompt_id":"sft","prompt":"hi","completion":"hey","tokens":4,"tokens_per_s":12.5}"#
        let event = try SubprocessSampleCompareRunner.decode(line: line, promptEcho: "hi")
        guard case .generation(let gen) = event else {
            return XCTFail("expected .generation, got \(event)")
        }
        XCTAssertEqual(gen.variant, .sft)
        XCTAssertEqual(gen.prompt, "hi")
        XCTAssertEqual(gen.completion, "hey")
        XCTAssertEqual(gen.tokens, 4)
        XCTAssertEqual(gen.tokensPerSec, 12.5, accuracy: 0.0001)
    }

    func test_decode_error_event_with_variant_context() throws {
        let line = #"{"event":"error","code":"adapter_invalid","message":"nope","context":{"variant":"sftdpo"}}"#
        let event = try SubprocessSampleCompareRunner.decode(line: line, promptEcho: "")
        guard case .variantFailed(let variant, let message, let code) = event else {
            return XCTFail("expected .variantFailed, got \(event)")
        }
        XCTAssertEqual(variant, .sftdpo)
        XCTAssertEqual(message, "nope")
        XCTAssertEqual(code, "adapter_invalid")
    }

    func test_decode_done_event() throws {
        let line = #"{"event":"done","stage":"generation","artifact":"ok","interrupted":false}"#
        let event = try SubprocessSampleCompareRunner.decode(line: line, promptEcho: "")
        guard case .done(let interrupted, _) = event else {
            return XCTFail("expected .done, got \(event)")
        }
        XCTAssertFalse(interrupted)
    }

    func test_decode_unknown_event_throws() {
        XCTAssertThrowsError(
            try SubprocessSampleCompareRunner.decode(
                line: #"{"event":"bogus"}"#,
                promptEcho: ""
            )
        )
    }

    // MARK: - utils

    private static func collect(_ args: [String], flag: String) -> [String] {
        var out: [String] = []
        var idx = args.startIndex
        while idx < args.endIndex {
            if args[idx] == flag, idx + 1 < args.endIndex {
                out.append(args[idx + 1])
                idx = args.index(idx, offsetBy: 2)
            } else {
                idx = args.index(after: idx)
            }
        }
        return out
    }
}
