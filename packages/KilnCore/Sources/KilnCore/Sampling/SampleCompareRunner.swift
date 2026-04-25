import Foundation
import OSLog

/// Runs the sidecar's ``sample-compare`` subcommand and surfaces its events.
///
/// The runner reuses ``TrainerLauncher`` because the same ``python -m
/// kiln_trainer`` binary handles all subcommands. The event stream is not a
/// ``TrainingEvent`` — sample-compare has a simpler lifecycle (ready → N×
/// generation → done) that doesn't carry loss/checkpoints, so we ship a
/// dedicated ``SampleCompareEvent`` and decoder.
public protocol SampleCompareRunner: Sendable {
    func runStreaming(request: SampleCompareRequest) -> AsyncThrowingStream<SampleCompareEvent, Error>
}

public final class SubprocessSampleCompareRunner: SampleCompareRunner, @unchecked Sendable {
    private let launcher: TrainerLauncher
    private let sigtermGraceSeconds: TimeInterval
    private let log = Logger(subsystem: "dev.kiln.core", category: "sample-compare")

    public init(launcher: TrainerLauncher, sigtermGraceSeconds: TimeInterval = 5) {
        self.launcher = launcher
        self.sigtermGraceSeconds = sigtermGraceSeconds
    }

    public func runStreaming(request: SampleCompareRequest) -> AsyncThrowingStream<SampleCompareEvent, Error> {
        AsyncThrowingStream { continuation in
            let launcher = self.launcher
            let grace = self.sigtermGraceSeconds
            let log = self.log
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()

            process.executableURL = launcher.executableURL
            process.arguments = launcher.argumentPrefix + Self.compareArgs(for: request)
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

            let boxed = SampleCompareState()

            let producer = Task.detached { [stdout, stderr, process, boxed] in
                do {
                    let stdoutHandle = stdout.fileHandleForReading
                    for try await line in stdoutHandle.bytes.lines {
                        if Task.isCancelled { break }
                        guard !line.isEmpty else { continue }
                        do {
                            let event = try Self.decode(line: line, promptEcho: request.prompt)
                            switch event {
                            case .generation(let g):
                                boxed.append(g.variant)
                            case .done(let doneInterrupted, _):
                                boxed.interrupted = doneInterrupted
                                continuation.yield(
                                    .done(
                                        interrupted: doneInterrupted,
                                        variantsDelivered: boxed.delivered
                                    )
                                )
                                continue
                            default:
                                break
                            }
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
                        continuation.finish(throwing: SampleCompareError.unexpectedExit(
                            code: process.terminationStatus
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
                continuation.finish(throwing: SampleCompareError.launchFailed(
                    message: error.localizedDescription
                ))
            }
        }
    }

    static func compareArgs(for request: SampleCompareRequest) -> [String] {
        var args: [String] = [
            "sample-compare",
            "--model", request.model,
            "--prompt", request.prompt,
            "--max-tokens", String(request.maxTokens),
            "--temp", String(request.temperature),
            "--top-p", String(request.topP),
            "--seed", String(request.seed)
        ]
        for spec in request.variants {
            args += ["--variant", spec.cliToken()]
        }
        if let entry = request.generatorEntry {
            args += ["--generator-entry", entry]
        }
        return args
    }

    static func decode(line: String, promptEcho: String) throws -> SampleCompareEvent {
        guard let data = line.data(using: .utf8) else {
            throw SampleCompareError.decodingFailed(line: line, underlying: "not UTF-8")
        }
        do {
            return try decode(data: data, promptEcho: promptEcho)
        } catch {
            throw SampleCompareError.decodingFailed(
                line: line,
                underlying: error.localizedDescription
            )
        }
    }

    private static func decode(data: Data, promptEcho: String) throws -> SampleCompareEvent {
        let obj = try JSONDecoder().decode(WireEvent.self, from: data)
        switch obj.event {
        case "ready":
            return .ready(version: obj.version ?? "n/a", mlx: obj.mlx ?? "n/a")
        case "generation":
            guard
                let promptID = obj.promptID,
                let variant = SampleCompareVariant(rawValue: promptID),
                let completion = obj.completion
            else {
                throw SampleCompareError.decodingFailed(
                    line: "",
                    underlying: "generation event missing prompt_id or completion"
                )
            }
            return .generation(
                SampleCompareGeneration(
                    variant: variant,
                    prompt: obj.prompt ?? promptEcho,
                    completion: completion,
                    tokens: obj.tokens ?? 0,
                    tokensPerSec: obj.tokensPerSec ?? 0
                )
            )
        case "error":
            let variant = obj.context?.variant.flatMap { SampleCompareVariant(rawValue: $0) }
            return .variantFailed(
                variant: variant,
                message: obj.message ?? "unknown error",
                code: obj.code ?? "unknown"
            )
        case "done":
            return .done(
                interrupted: obj.interrupted ?? false,
                variantsDelivered: []
            )
        default:
            throw SampleCompareError.decodingFailed(
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
        // generation
        let prompt: String?
        let completion: String?
        let tokens: Int?
        let tokensPerSec: Double?
        let promptID: String?
        // error
        let code: String?
        let message: String?
        let context: Context?
        // done
        let interrupted: Bool?

        struct Context: Decodable {
            let variant: String?
        }

        enum CodingKeys: String, CodingKey {
            case event, version, mlx, prompt, completion, tokens, code, message, context, interrupted
            case tokensPerSec = "tokens_per_s"
            case promptID = "prompt_id"
        }
    }
}

/// Small accumulator we keep inside the producer task so we can pass the list
/// of successfully-delivered variants into the ``.done`` event. Can't use a
/// plain ``var`` inside the ``@Sendable`` closure without rewriting as an
/// actor — this mutable box sidesteps that without introducing async awaits in
/// the hot stdout loop.
private final class SampleCompareState: @unchecked Sendable {
    private let lock = NSLock()
    private var _delivered: [SampleCompareVariant] = []
    var interrupted: Bool = false

    var delivered: [SampleCompareVariant] {
        lock.lock()
        defer { lock.unlock() }
        return _delivered
    }

    func append(_ v: SampleCompareVariant) {
        lock.lock()
        defer { lock.unlock() }
        _delivered.append(v)
    }
}

public enum SampleCompareError: Error, Sendable, Equatable {
    case launchFailed(message: String)
    case unexpectedExit(code: Int32)
    case decodingFailed(line: String, underlying: String)
}
