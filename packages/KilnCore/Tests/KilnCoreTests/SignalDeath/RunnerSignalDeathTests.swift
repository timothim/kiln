import XCTest
@testable import KilnCore

/// Verifies that all three subprocess runners propagate uncaught signal
/// deaths as errors on the event stream, rather than silently completing.
///
/// Background: prior to this fix the three runners treated
/// `Process.terminationReason == .uncaughtSignal` as a successful exit
/// (alongside `terminationStatus == 0`). That masked real crashes — a
/// SIGABRT from the Python sidecar would surface as "training/export/sample
/// completed" with no events. Each runner already handles user-initiated
/// cancellation via its `Task.isCancelled` branch (which fires when the
/// caller cancels the stream and SIGTERM is forwarded), so the exemption
/// only ever shadowed unexpected crashes.
final class RunnerSignalDeathTests: XCTestCase {

    /// Writes a small shell script that emits a `ready` event and then
    /// aborts itself via SIGABRT. Returns the script URL; caller is
    /// responsible for cleaning up the parent directory.
    private func makeCrashScript() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kiln-signal-death-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let script = dir.appendingPathComponent("crash.sh")
        let body = """
        #!/bin/sh
        echo '{"event":"ready","version":"0.1.0","mlx":"0.22.0"}'
        kill -ABRT $$
        """
        try body.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: script.path
        )
        return script
    }

    private func crashLauncher(script: URL) -> TrainerLauncher {
        TrainerLauncher(
            executableURL: script,
            argumentPrefix: [],
            workingDirectory: nil,
            environment: nil
        )
    }

    func test_training_runner_propagates_uncaught_signal_as_error() async throws {
        let script = try makeCrashScript()
        defer { try? FileManager.default.removeItem(at: script.deletingLastPathComponent()) }

        let runner = SubprocessTrainingRunner(launcher: crashLauncher(script: script))
        let request = TrainingRequest(
            datasetURL: URL(fileURLWithPath: "/tmp/d.jsonl"),
            runDir: URL(fileURLWithPath: "/tmp/r")
        )

        do {
            for try await _ in runner.runStreaming(request: request) {
                // Drain. We accept the leading `ready` event; the failure
                // must surface when the subprocess dies via SIGABRT.
            }
            XCTFail("expected the stream to throw on signal death")
        } catch let error as TrainingError {
            guard case .unexpectedExit(let code, _) = error else {
                return XCTFail("expected .unexpectedExit, got \(error)")
            }
            XCTAssertNotEqual(code, 0, "uncaught signal must surface a non-zero termination status")
        } catch {
            XCTFail("expected TrainingError.unexpectedExit, got \(type(of: error)): \(error)")
        }
    }

    func test_ollama_exporter_propagates_uncaught_signal_as_error() async throws {
        let script = try makeCrashScript()
        defer { try? FileManager.default.removeItem(at: script.deletingLastPathComponent()) }

        let exporter = SubprocessOllamaExporter(launcher: crashLauncher(script: script))
        let request = ExportRequest(
            model: "m",
            adapterURL: URL(fileURLWithPath: "/tmp/a.safetensors"),
            runDir: URL(fileURLWithPath: "/tmp/r"),
            userName: "u",
            outputName: "o",
            llamaCppDir: nil
        )

        do {
            for try await _ in exporter.runStreaming(request: request) {}
            XCTFail("expected the stream to throw on signal death")
        } catch let error as ExportError {
            guard case .unexpectedExit(let code, _) = error else {
                return XCTFail("expected .unexpectedExit, got \(error)")
            }
            XCTAssertNotEqual(code, 0)
        } catch {
            XCTFail("expected ExportError.unexpectedExit, got \(type(of: error)): \(error)")
        }
    }

    func test_sample_compare_runner_propagates_uncaught_signal_as_error() async throws {
        let script = try makeCrashScript()
        defer { try? FileManager.default.removeItem(at: script.deletingLastPathComponent()) }

        let runner = SubprocessSampleCompareRunner(launcher: crashLauncher(script: script))
        let request = SampleCompareRequest(
            prompt: "hello",
            variants: [
                .init(variant: .base, adapterPath: nil)
            ]
        )

        do {
            for try await _ in runner.runStreaming(request: request) {}
            XCTFail("expected the stream to throw on signal death")
        } catch let error as SampleCompareError {
            guard case .unexpectedExit(let code) = error else {
                return XCTFail("expected .unexpectedExit, got \(error)")
            }
            XCTAssertNotEqual(code, 0)
        } catch {
            XCTFail("expected SampleCompareError.unexpectedExit, got \(type(of: error)): \(error)")
        }
    }
}
