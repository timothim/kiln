import XCTest
@testable import KilnCore

/// Golden-file-style tests against the exact JSON line format emitted by
/// `kiln_trainer.events`. If the sidecar changes a field name we want a
/// compile-time red, not a silent drop.
final class TrainingEventDecodingTests: XCTestCase {

    private func decode(_ line: String) throws -> TrainingEvent {
        try SubprocessTrainingRunner.decode(line: line)
    }

    func test_ready_event_decodes() throws {
        let line = #"{"event":"ready","version":"0.1.0","mlx":"0.22.0"}"#
        guard case let .ready(version, mlx) = try decode(line) else {
            return XCTFail("expected .ready")
        }
        XCTAssertEqual(version, "0.1.0")
        XCTAssertEqual(mlx, "0.22.0")
    }

    func test_progress_event_full_fields() throws {
        let line = #"{"event":"progress","stage":"sft","iter":100,"loss":1.112,"tokens_per_s":912.4,"eta_s":1840,"val_loss":1.235,"learning_rate":1e-4}"#
        guard case let .progress(progress) = try decode(line) else {
            return XCTFail("expected .progress")
        }
        XCTAssertEqual(progress.iter, 100)
        XCTAssertEqual(progress.loss, 1.112, accuracy: 1e-6)
        XCTAssertEqual(progress.tokensPerSec ?? -1, 912.4, accuracy: 1e-6)
        XCTAssertEqual(progress.etaSec ?? -1, 1840, accuracy: 1e-6)
        XCTAssertEqual(progress.valLoss ?? -1, 1.235, accuracy: 1e-6)
        XCTAssertEqual(progress.learningRate ?? -1, 1e-4, accuracy: 1e-12)
    }

    func test_progress_event_optional_fields_omitted() throws {
        let line = #"{"event":"progress","stage":"sft","iter":50,"loss":1.324}"#
        guard case let .progress(progress) = try decode(line) else {
            return XCTFail("expected .progress")
        }
        XCTAssertEqual(progress.iter, 50)
        XCTAssertEqual(progress.loss, 1.324, accuracy: 1e-6)
        XCTAssertNil(progress.tokensPerSec)
        XCTAssertNil(progress.etaSec)
        XCTAssertNil(progress.valLoss)
        XCTAssertNil(progress.learningRate)
    }

    func test_sample_event_decodes() throws {
        let line = #"{"event":"sample","iter":100,"prompt_id":"p0","completion":"Hello there."}"#
        guard case let .sample(sample) = try decode(line) else {
            return XCTFail("expected .sample")
        }
        XCTAssertEqual(sample.iter, 100)
        XCTAssertEqual(sample.promptID, "p0")
        XCTAssertEqual(sample.completion, "Hello there.")
        XCTAssertNil(sample.tokensPerSec)
    }

    func test_checkpoint_event_with_best_flag() throws {
        let line = #"{"event":"checkpoint","path":"/tmp/run/adapters/0000050.safetensors","iter":50,"best":true}"#
        guard case let .checkpoint(path, iter, best) = try decode(line) else {
            return XCTFail("expected .checkpoint")
        }
        XCTAssertEqual(path.path, "/tmp/run/adapters/0000050.safetensors")
        XCTAssertEqual(iter, 50)
        XCTAssertEqual(best, true)
    }

    func test_advisor_observation_event_decodes_iter_content_model() throws {
        let line = #"{"event":"advisor_observation","iter":50,"content":"Voice is stabilizing.","model":"claude-opus-4-7"}"#
        guard case let .advisorObservation(iter, content, modelID) = try decode(line) else {
            return XCTFail("expected .advisorObservation")
        }
        XCTAssertEqual(iter, 50)
        XCTAssertEqual(content, "Voice is stabilizing.")
        XCTAssertEqual(modelID, "claude-opus-4-7")
    }

    func test_done_event_defaults_interrupted_false_when_omitted() throws {
        let line = #"{"event":"done","stage":"sft","artifact":"/tmp/run/adapters/adapters.safetensors"}"#
        guard case let .done(artifact, interrupted) = try decode(line) else {
            return XCTFail("expected .done")
        }
        XCTAssertEqual(artifact.path, "/tmp/run/adapters/adapters.safetensors")
        XCTAssertFalse(interrupted)
    }

    func test_done_event_interrupted_true() throws {
        let line = #"{"event":"done","stage":"sft","artifact":"/tmp/run/adapters/adapters.safetensors","interrupted":true}"#
        guard case let .done(_, interrupted) = try decode(line) else {
            return XCTFail("expected .done")
        }
        XCTAssertTrue(interrupted)
    }

    func test_error_oom_maps_to_typed_case() throws {
        let line = #"{"event":"error","code":"oom","message":"MLX OOM at iter 412","recoverable":false,"stage":"sft"}"#
        guard case let .error(err) = try decode(line) else {
            return XCTFail("expected .error")
        }
        guard case .oom(let msg) = err else {
            return XCTFail("expected .oom got \(err)")
        }
        XCTAssertEqual(msg, "MLX OOM at iter 412")
    }

    func test_error_data_invalid_maps_to_typed_case() throws {
        let line = #"{"event":"error","code":"data_invalid","message":"training set is empty","recoverable":false}"#
        guard case let .error(err) = try decode(line),
              case .dataInvalid(let msg) = err else {
            return XCTFail("expected .dataInvalid")
        }
        XCTAssertEqual(msg, "training set is empty")
    }

    func test_error_sigterm_maps_to_typed_case() throws {
        let line = #"{"event":"error","code":"sigterm","message":"interrupted","recoverable":false}"#
        guard case let .error(err) = try decode(line),
              case .sigterm = err else {
            return XCTFail("expected .sigterm")
        }
    }

    func test_unknown_event_type_throws_decoding_error() {
        let line = #"{"event":"mystery","payload":42}"#
        XCTAssertThrowsError(try decode(line)) { error in
            guard case TrainingError.decodingFailed = error else {
                return XCTFail("expected .decodingFailed, got \(error)")
            }
        }
    }

    func test_malformed_json_throws_decoding_error() {
        let line = "{not valid json"
        XCTAssertThrowsError(try decode(line)) { error in
            guard case TrainingError.decodingFailed = error else {
                return XCTFail("expected .decodingFailed, got \(error)")
            }
        }
    }

    func test_unknown_error_code_falls_through_to_internal() throws {
        let line = #"{"event":"error","code":"brand_new_code","message":"future"}"#
        guard case let .error(err) = try decode(line),
              case .internalError(let msg) = err else {
            return XCTFail("expected .internalError")
        }
        XCTAssertTrue(msg.contains("brand_new_code"))
    }
}
