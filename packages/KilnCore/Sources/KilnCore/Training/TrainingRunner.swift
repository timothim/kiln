import Foundation
import OSLog

/// Everything the runner needs to spawn `python -m kiln_trainer train ...`.
///
/// The default launcher is `/usr/bin/env uv run --project <trainerPackageDir>
/// python -m kiln_trainer`. That layout matches `make` targets and the
/// `scripts/demo-check.py` probe. Callers that want to skip `uv` — typically
/// smoke tests driving the fake trainer — can supply their own executable
/// + argument prefix.
public struct TrainerLauncher: Sendable, Hashable {
    public let executableURL: URL
    public let argumentPrefix: [String]
    public let workingDirectory: URL?
    public let environment: [String: String]?

    public init(
        executableURL: URL,
        argumentPrefix: [String],
        workingDirectory: URL? = nil,
        environment: [String: String]? = nil
    ) {
        self.executableURL = executableURL
        self.argumentPrefix = argumentPrefix
        self.workingDirectory = workingDirectory
        self.environment = environment
    }

    /// `/usr/bin/env uv run --project <dir> python -m kiln_trainer`.
    public static func uvRun(trainerPackageDir: URL) -> TrainerLauncher {
        TrainerLauncher(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            argumentPrefix: [
                "uv", "run",
                "--project", trainerPackageDir.path,
                "python", "-m", "kiln_trainer"
            ],
            workingDirectory: trainerPackageDir,
            environment: nil
        )
    }
}

public protocol TrainingRunner: Sendable {
    func runStreaming(request: TrainingRequest) -> AsyncThrowingStream<TrainingEvent, Error>
}

/// Production runner: spawns the Python sidecar, parses JSON lines on stdout
/// into `TrainingEvent`, forwards SIGTERM on stream cancellation, escalates
/// to SIGKILL after a 5-second grace period (matches the 5 s flush budget in
/// `packages/kiln_trainer/CLAUDE.md`).
public final class SubprocessTrainingRunner: TrainingRunner, @unchecked Sendable {
    private let launcher: TrainerLauncher
    private let log = Logger(subsystem: "dev.kiln.core", category: "train")

    /// How long we wait after SIGTERM before escalating. The Python sidecar
    /// promises a 5 s flush budget; give it 5 s, then SIGKILL.
    private let sigtermGraceSeconds: TimeInterval

    public init(launcher: TrainerLauncher, sigtermGraceSeconds: TimeInterval = 5) {
        self.launcher = launcher
        self.sigtermGraceSeconds = sigtermGraceSeconds
    }

    public func runStreaming(request: TrainingRequest) -> AsyncThrowingStream<TrainingEvent, Error> {
        AsyncThrowingStream { continuation in
            let launcher = self.launcher
            let grace = self.sigtermGraceSeconds
            let log = self.log
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()

            process.executableURL = launcher.executableURL
            process.arguments = launcher.argumentPrefix + Self.trainArgs(for: request)
            if let cwd = launcher.workingDirectory {
                process.currentDirectoryURL = cwd
            }
            if let env = launcher.environment {
                process.environment = env
            }
            process.standardOutput = stdout
            process.standardError = stderr

            // stderr consumer — free-form log lines, forwarded to OSLog.
            let stderrHandle = stderr.fileHandleForReading
            let stderrTail = StderrTail()
            stderrHandle.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
                stderrTail.append(chunk)
                for line in chunk.split(separator: "\n", omittingEmptySubsequences: true) {
                    log.debug("[sidecar stderr] \(String(line), privacy: .public)")
                }
            }

            // Producer task — reads stdout line by line and yields events.
            let producer = Task.detached { [stdout, stderr, process, stderrTail] in
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
                            // Tolerate malformed lines — log + skip, matching M4 IngestRunner's posture.
                        }
                    }
                    process.waitUntilExit()
                    stderrHandle.readabilityHandler = nil
                    if Task.isCancelled {
                        continuation.finish(throwing: CancellationError())
                        return
                    }
                    if process.terminationStatus == 0 {
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: TrainingError.unexpectedExit(
                            code: process.terminationStatus,
                            stderrTail: stderrTail.snapshot()
                        ))
                    }
                    _ = stderr // keep alive
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                producer.cancel()
                if process.isRunning {
                    process.terminate() // SIGTERM
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
                continuation.finish(throwing: TrainingError.launchFailed(message: error.localizedDescription))
            }
        }
    }

    // MARK: - Helpers

    static func trainArgs(for request: TrainingRequest) -> [String] {
        var args: [String] = [
            "train",
            "--dataset", request.datasetURL.path,
            "--model", request.model,
            "--run-dir", request.runDir.path,
            "--epochs", String(request.hyperparameters.epochs),
            "--rank", String(request.hyperparameters.rank),
            "--lora-layers", String(request.hyperparameters.loraLayers),
            "--batch-size", String(request.hyperparameters.batchSize),
            "--learning-rate", String(request.hyperparameters.learningRate),
            "--max-seq-length", String(request.hyperparameters.maxSeqLength),
            "--save-every", String(request.hyperparameters.saveEvery),
            "--val-batches", String(request.hyperparameters.valBatches),
            "--seed", String(request.seed)
        ]
        if let iters = request.itersOverride {
            args += ["--iters", String(iters)]
        }
        if let module = request.trainerModule {
            args += ["--trainer-module", module]
        }
        if let entry = request.trainerEntry {
            args += ["--trainer-entry", entry]
        }
        return args
    }

    static func decode(line: String) throws -> TrainingEvent {
        guard let data = line.data(using: .utf8) else {
            throw TrainingError.decodingFailed(line: line, underlying: "not UTF-8")
        }
        do {
            return try JSONDecoder().decode(TrainingEvent.self, from: data)
        } catch {
            throw TrainingError.decodingFailed(line: line, underlying: error.localizedDescription)
        }
    }
}

/// Thread-safe rolling tail of the sidecar's stderr. We keep the last 4 KiB
/// so that on an unexpected exit we can attach it to the error without
/// buffering the whole log.
private final class StderrTail: @unchecked Sendable {
    private let maxBytes = 4_096
    private let lock = NSLock()
    private var buffer = ""

    func append(_ s: String) {
        lock.lock()
        defer { lock.unlock() }
        buffer += s
        if buffer.count > maxBytes {
            let drop = buffer.count - maxBytes
            buffer.removeFirst(drop)
        }
    }

    func snapshot() -> String {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }
}
