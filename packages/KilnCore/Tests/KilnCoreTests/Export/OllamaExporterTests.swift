import XCTest
@testable import KilnCore

final class OllamaExporterTests: XCTestCase {

    // MARK: - exportArgs

    func test_exportArgs_contains_required_flags() {
        let request = ExportRequest(
            model: "mlx-community/Qwen2.5-3B-Instruct-4bit",
            adapterURL: URL(fileURLWithPath: "/tmp/adapters.safetensors"),
            runDir: URL(fileURLWithPath: "/tmp/run"),
            userName: "Timothée",
            outputName: "kiln-timothee",
            llamaCppDir: URL(fileURLWithPath: "/tmp/llama.cpp"),
            quantization: "Q4_K_M"
        )
        let args = SubprocessOllamaExporter.exportArgs(for: request)

        XCTAssertEqual(args.first, "export")
        XCTAssertTrue(args.contains("--model"))
        XCTAssertTrue(args.contains("mlx-community/Qwen2.5-3B-Instruct-4bit"))
        XCTAssertTrue(args.contains("--adapter-path"))
        XCTAssertTrue(args.contains("/tmp/adapters.safetensors"))
        XCTAssertTrue(args.contains("--run-dir"))
        XCTAssertTrue(args.contains("/tmp/run"))
        XCTAssertTrue(args.contains("--user-name"))
        XCTAssertTrue(args.contains("Timothée"))
        XCTAssertTrue(args.contains("--output-name"))
        XCTAssertTrue(args.contains("kiln-timothee"))
        XCTAssertTrue(args.contains("--llama-cpp-dir"))
        XCTAssertTrue(args.contains("/tmp/llama.cpp"))
        XCTAssertTrue(args.contains("--quantization"))
        XCTAssertTrue(args.contains("Q4_K_M"))
    }

    func test_exportArgs_passes_skip_flags() {
        let request = ExportRequest(
            model: "m",
            adapterURL: URL(fileURLWithPath: "/a"),
            runDir: URL(fileURLWithPath: "/r"),
            userName: "u",
            outputName: "o",
            llamaCppDir: nil,
            skipGGUF: true,
            skipOllama: true
        )
        let args = SubprocessOllamaExporter.exportArgs(for: request)
        XCTAssertTrue(args.contains("--skip-gguf"))
        XCTAssertTrue(args.contains("--skip-ollama"))
        XCTAssertFalse(args.contains("--llama-cpp-dir"))
    }

    func test_exportArgs_includes_test_seams_when_set() {
        let request = ExportRequest(
            model: "m",
            adapterURL: URL(fileURLWithPath: "/a"),
            runDir: URL(fileURLWithPath: "/r"),
            userName: "u",
            outputName: "o",
            llamaCppDir: nil,
            fuserEntry: "/tmp/fake_fuser.py",
            ollamaBin: "/tmp/fake_ollama.sh"
        )
        let args = SubprocessOllamaExporter.exportArgs(for: request)
        XCTAssertTrue(args.contains("--fuser-entry"))
        XCTAssertTrue(args.contains("/tmp/fake_fuser.py"))
        XCTAssertTrue(args.contains("--ollama-bin"))
        XCTAssertTrue(args.contains("/tmp/fake_ollama.sh"))
    }

    // MARK: - decode

    func test_decode_ready_event() throws {
        let line = #"{"event":"ready","version":"0.1.0","mlx":"0.22.0"}"#
        let event = try SubprocessOllamaExporter.decode(line: line)
        guard case .ready(let version, let mlx) = event else {
            return XCTFail("expected .ready, got \(event)")
        }
        XCTAssertEqual(version, "0.1.0")
        XCTAssertEqual(mlx, "0.22.0")
    }

    func test_decode_done_event_for_each_stage() throws {
        let cases: [(String, ExportStage)] = [
            ("fuse", .fuse), ("gguf", .gguf), ("ollama", .ollama)
        ]
        for (wireStage, expectedStage) in cases {
            let line = """
            {"event":"done","stage":"\(wireStage)","artifact":"/tmp/\(wireStage)","interrupted":false}
            """
            let event = try SubprocessOllamaExporter.decode(line: line)
            guard case .stageDone(let stage, let artifact, let interrupted) = event else {
                return XCTFail("expected .stageDone, got \(event) for stage=\(wireStage)")
            }
            XCTAssertEqual(stage, expectedStage)
            XCTAssertEqual(artifact, "/tmp/\(wireStage)")
            XCTAssertFalse(interrupted)
        }
    }

    func test_decode_error_event_maps_to_stageFailed() throws {
        let line = #"{"event":"error","code":"gguf_failed","message":"not found","recoverable":true,"stage":"gguf"}"#
        let event = try SubprocessOllamaExporter.decode(line: line)
        guard case .stageFailed(let stage, let code, let message, let recoverable) = event else {
            return XCTFail("expected .stageFailed, got \(event)")
        }
        XCTAssertEqual(stage, .gguf)
        XCTAssertEqual(code, "gguf_failed")
        XCTAssertEqual(message, "not found")
        XCTAssertTrue(recoverable)
    }

    func test_decode_error_without_stage_defaults_to_fuse() throws {
        let line = #"{"event":"error","code":"internal","message":"bad cli","recoverable":false}"#
        let event = try SubprocessOllamaExporter.decode(line: line)
        guard case .stageFailed(let stage, _, _, _) = event else {
            return XCTFail("expected .stageFailed, got \(event)")
        }
        XCTAssertEqual(stage, .fuse)
    }

    func test_decode_unknown_event_throws() {
        XCTAssertThrowsError(try SubprocessOllamaExporter.decode(line: #"{"event":"bogus"}"#))
    }
}
