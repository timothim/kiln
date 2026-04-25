import Foundation
import XCTest
@testable import KilnCore

/// Tests for the Saturday Phase 1 ``SubprocessVoiceCoachRunner``.
/// Same fake-shell-launcher pattern as the M9.C / M9.B runners.
final class VoiceCoachRunnerTests: XCTestCase {

    private func makeFakeLauncher(
        emit lines: [String],
        exitCode: Int32 = 0
    ) throws -> (TrainerLauncher, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kiln-voicecoach-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let script = dir.appendingPathComponent("fake-vc.sh")
        let body = """
        #!/bin/bash
        \(lines.map { "echo '\($0)'" }.joined(separator: "\n"))
        exit \(exitCode)
        """
        try body.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: script.path
        )
        let launcher = TrainerLauncher(
            executableURL: script,
            argumentPrefix: [],
            workingDirectory: dir,
            environment: nil
        )
        return (launcher, dir)
    }

    private func sampleInput() -> VoiceCoachInput {
        VoiceCoachInput(
            styleSignature: ["formality": .number(0.5)],
            sampleCompletions: [
                .init(prompt: "What should I work on this week?", completion: "Pick the one you'd regret skipping.")
            ]
        )
    }

    func test_cloud_mode_decodes_voice_report_event() async throws {
        // Plain markdown in the canned event — keep the JSON
        // single-line so the shell echo works cleanly.
        let canned = [
            "{\"event\":\"ready\",\"version\":\"0.1.0\",\"mlx\":\"0.22.1\"}",
            "{\"event\":\"voice_report\",\"markdown\":\"Dominant traits — terse, direct.\",\"model\":\"claude-opus-4-7\"}",
            "{\"event\":\"done\",\"stage\":\"generation\",\"artifact\":\"stdout\",\"interrupted\":false}",
        ]
        let (launcher, dir) = try makeFakeLauncher(emit: canned)
        defer { try? FileManager.default.removeItem(at: dir) }

        let runner = SubprocessVoiceCoachRunner(launcher: launcher)
        let report = try await runner.generate(
            input: sampleInput(),
            mode: .cloud,
            apiKey: "sk-ant-test"
        )
        XCTAssertEqual(report.modelID, "claude-opus-4-7")
        XCTAssertTrue(report.markdown.contains("Dominant traits"))
        XCTAssertTrue(report.markdown.contains("terse, direct"))
    }

    func test_missing_api_key_throws_immediately_without_spawning_subprocess() async throws {
        // Use an executable that would fail if invoked — confirms we
        // short-circuit before the spawn.
        let launcher = TrainerLauncher(
            executableURL: URL(fileURLWithPath: "/usr/bin/false"),
            argumentPrefix: [],
            workingDirectory: nil,
            environment: nil
        )
        let runner = SubprocessVoiceCoachRunner(launcher: launcher)
        do {
            _ = try await runner.generate(
                input: sampleInput(),
                mode: .cloud,
                apiKey: nil
            )
            XCTFail("expected missingAPIKey")
        } catch VoiceCoachError.missingAPIKey {
            // expected
        } catch {
            XCTFail("expected missingAPIKey, got \(error)")
        }
    }

    func test_sidecar_data_invalid_for_missing_key_maps_to_typed_error() async throws {
        // The sidecar emits `data_invalid` containing the literal
        // `ANTHROPIC_API_KEY` substring. Runner should map that to the
        // typed missingAPIKey case so the UI can render a "set up
        // your key" CTA instead of a generic error.
        let canned = [
            #"{"event":"ready","version":"0.1.0","mlx":"0.22.1"}"#,
            #"{"event":"error","code":"data_invalid","message":"ANTHROPIC_API_KEY missing from env","recoverable":false}"#,
            #"{"event":"done","stage":"generation","artifact":"stdout","interrupted":false}"#,
        ]
        let (launcher, dir) = try makeFakeLauncher(emit: canned, exitCode: 1)
        defer { try? FileManager.default.removeItem(at: dir) }

        let runner = SubprocessVoiceCoachRunner(launcher: launcher)
        do {
            _ = try await runner.generate(
                input: sampleInput(),
                mode: .cloud,
                apiKey: "sk-ant-test-but-sidecar-says-nope"
            )
            XCTFail("expected missingAPIKey")
        } catch VoiceCoachError.missingAPIKey {
            // expected
        } catch {
            XCTFail("expected missingAPIKey, got \(error)")
        }
    }

    func test_local_mode_with_subprocess_failure_throws_sidecarError() async throws {
        let canned = [
            #"{"event":"ready","version":"0.1.0","mlx":"0.22.1"}"#,
            #"{"event":"error","code":"subprocess_failed","message":"Ollama daemon unreachable","recoverable":false}"#,
            #"{"event":"done","stage":"generation","artifact":"stdout","interrupted":false}"#,
        ]
        let (launcher, dir) = try makeFakeLauncher(emit: canned, exitCode: 1)
        defer { try? FileManager.default.removeItem(at: dir) }

        let runner = SubprocessVoiceCoachRunner(launcher: launcher)
        do {
            _ = try await runner.generate(
                input: sampleInput(),
                mode: .local,
                apiKey: nil
            )
            XCTFail("expected sidecarError")
        } catch VoiceCoachError.sidecarError(let code, _) {
            XCTAssertEqual(code, "subprocess_failed")
        } catch {
            XCTFail("expected sidecarError, got \(error)")
        }
    }

    func test_anycodable_round_trips_styleSignature_payload() throws {
        let input = VoiceCoachInput(
            styleSignature: [
                "formality": .number(0.5),
                "ngrams": .stringArray(["forgot the dog", "burnt toast"]),
                "label": .string("Tim"),
            ],
            sampleCompletions: []
        )
        let encoded = try JSONEncoder().encode(input)
        let decoded = try JSONDecoder().decode(VoiceCoachInput.self, from: encoded)
        XCTAssertEqual(decoded.styleSignature["label"], .string("Tim"))
    }
}
