import Foundation
import OSLog

/// Subprocess wrapper around the Python ``export`` subcommand. The sidecar
/// orchestrates the four-stage pipeline (fuse → gguf → modelfile → ollama);
/// this runner only transports its JSON-line events into Swift's typed
/// ``ExportEvent`` stream.
///
/// Mirrors ``SubprocessTrainingRunner``'s shape: same ``TrainerLauncher``,
/// same SIGTERM-then-SIGKILL cancellation contract, same stderr→OSLog
/// forwarding. The only difference is the event decoder — export events are
/// ``done(stage=...)`` / ``error(stage=...)`` rather than progress frames.
public protocol OllamaExporter: Sendable {
    func runStreaming(request: ExportRequest) -> AsyncThrowingStream<ExportEvent, Error>
}

public final class SubprocessOllamaExporter: OllamaExporter, @unchecked Sendable {
    private let launcher: TrainerLauncher
    private let sigtermGraceSeconds: TimeInterval
    private let log = Logger(subsystem: "dev.kiln.core", category: "export")

    public init(launcher: TrainerLauncher, sigtermGraceSeconds: TimeInterval = 5) {
        self.launcher = launcher
        self.sigtermGraceSeconds = sigtermGraceSeconds
    }

    public func runStreaming(request: ExportRequest) -> AsyncThrowingStream<ExportEvent, Error> {
        AsyncThrowingStream { continuation in
            let launcher = self.launcher
            let grace = self.sigtermGraceSeconds
            let log = self.log
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()

            process.executableURL = launcher.executableURL
            process.arguments = launcher.argumentPrefix + Self.exportArgs(for: request)
            if let cwd = launcher.workingDirectory {
                process.currentDirectoryURL = cwd
            }
            if let env = launcher.environment {
                process.environment = env
            }
            process.standardOutput = stdout
            process.standardError = stderr

            let stderrHandle = stderr.fileHandleForReading
            stderrHandle.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
                for line in chunk.split(separator: "\n", omittingEmptySubsequences: true) {
                    log.debug("[sidecar stderr] \(String(line), privacy: .public)")
                }
            }

            let producer = Task.detached { [stdout, stderr, process] in
                do {
                    let stdoutHandle = stdout.fileHandleForReading
                    for try await line in stdoutHandle.bytes.lines {
                        if Task.isCancelled { break }
                        guard !line.isEmpty else { continue }
                        do {
                            let event = try Self.decode(line: line)
                            continuation.yield(event)
                        } catch {
                            log.error("decode failed: \(error.localizedDescription, privacy: .public) line=\(line, privacy: .public)")
                        }
                    }
                    process.waitUntilExit()
                    stderrHandle.readabilityHandler = nil
                    if Task.isCancelled {
                        continuation.finish(throwing: CancellationError())
                        return
                    }
                    if process.terminationStatus == 0 || process.terminationReason == .uncaughtSignal {
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: ExportError.unexpectedExit(
                            code: process.terminationStatus,
                            stderrTail: ""
                        ))
                    }
                    _ = stderr
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                producer.cancel()
                if process.isRunning {
                    process.terminate()
                    let deadline = DispatchTime.now() + grace
                    DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: deadline) {
                        if process.isRunning {
                            kill(process.processIdentifier, SIGKILL)
                        }
                    }
                }
            }

            do {
                try process.run()
            } catch {
                stderrHandle.readabilityHandler = nil
                continuation.finish(throwing: ExportError.launchFailed(message: error.localizedDescription))
            }
        }
    }

    static func exportArgs(for request: ExportRequest) -> [String] {
        var args: [String] = [
            "export",
            "--model", request.model,
            "--adapter-path", request.adapterURL.path,
            "--run-dir", request.runDir.path,
            "--user-name", request.userName,
            "--output-name", request.outputName
        ]
        if let dir = request.llamaCppDir {
            args += ["--llama-cpp-dir", dir.path]
        }
        if let q = request.quantization {
            args += ["--quantization", q]
        }
        if request.skipGGUF {
            args += ["--skip-gguf"]
        }
        if request.skipOllama {
            args += ["--skip-ollama"]
        }
        if let entry = request.fuserEntry {
            args += ["--fuser-entry", entry]
        }
        if let bin = request.ollamaBin {
            args += ["--ollama-bin", bin]
        }
        return args
    }

    static func decode(line: String) throws -> ExportEvent {
        guard let data = line.data(using: .utf8) else {
            throw ExportError.decodingFailed(line: line, underlying: "not UTF-8")
        }
        do {
            return try decode(data: data)
        } catch {
            throw ExportError.decodingFailed(
                line: line,
                underlying: error.localizedDescription
            )
        }
    }

    private static func decode(data: Data) throws -> ExportEvent {
        let obj = try JSONDecoder().decode(WireEvent.self, from: data)
        switch obj.event {
        case "ready":
            return .ready(version: obj.version ?? "n/a", mlx: obj.mlx ?? "n/a")
        case "done":
            guard
                let rawStage = obj.stage,
                let stage = ExportStage(rawValue: rawStage)
            else {
                throw ExportError.decodingFailed(
                    line: "",
                    underlying: "done event missing or unknown stage: \(obj.stage ?? "nil")"
                )
            }
            return .stageDone(
                stage: stage,
                artifact: obj.artifact ?? "",
                interrupted: obj.interrupted ?? false
            )
        case "error":
            // Stage may be absent (cli-level parse errors emit no stage).
            // Default to `fuse` in that case — it's the first stage the caller
            // would see and keeps the event surface simple.
            let stage = obj.stage.flatMap(ExportStage.init(rawValue:)) ?? .fuse
            return .stageFailed(
                stage: stage,
                code: obj.code ?? "unknown",
                message: obj.message ?? "unknown error",
                recoverable: obj.recoverable ?? false
            )
        default:
            throw ExportError.decodingFailed(
                line: "",
                underlying: "unknown event type: \(obj.event)"
            )
        }
    }

    private struct WireEvent: Decodable {
        let event: String
        // ready
        let version: String?
        let mlx: String?
        // done
        let stage: String?
        let artifact: String?
        let interrupted: Bool?
        // error
        let code: String?
        let message: String?
        let recoverable: Bool?
    }
}
