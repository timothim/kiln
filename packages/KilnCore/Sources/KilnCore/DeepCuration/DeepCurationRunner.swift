import Foundation
import OSLog

/// Saturday Phase 4 — Swift runner for the corpus-curator Managed
/// Agent. Spawns ``python -m kiln_trainer curate-agent`` and streams
/// ``agent_thinking`` / ``agent_progress`` / ``agent_completion``
/// events back to the consumer.

public enum DeepCurationEvent: Sendable, Hashable {
    case thinking(content: String)
    case progress(samplesReviewed: Int, removals: Int, flags: Int)
    case completion(samplesKept: Int, samplesRemoved: Int, samplesFlagged: Int, reportPath: String, curatedPath: String)
    case error(code: String, message: String)
}

public struct DeepCurationRequest: Sendable, Hashable {
    public let corpusPath: URL
    public let outputPath: URL
    public let reportPath: URL
    public let dryRun: Bool

    public init(corpusPath: URL, outputPath: URL, reportPath: URL, dryRun: Bool) {
        self.corpusPath = corpusPath
        self.outputPath = outputPath
        self.reportPath = reportPath
        self.dryRun = dryRun
    }
}

public enum DeepCurationError: Error, Equatable, Sendable {
    case launchFailed(message: String)
    case unexpectedExit(code: Int32, stderrTail: String)
}

public protocol DeepCurationRunner: Sendable {
    func runStreaming(
        request: DeepCurationRequest,
        apiKey: String?
    ) -> AsyncThrowingStream<DeepCurationEvent, Error>
}

public final class SubprocessDeepCurationRunner: DeepCurationRunner, @unchecked Sendable {
    private let launcher: TrainerLauncher
    private let log = Logger(subsystem: "dev.kiln.core", category: "deep-curation")

    public init(launcher: TrainerLauncher) {
        self.launcher = launcher
    }

    public func runStreaming(
        request: DeepCurationRequest,
        apiKey: String?
    ) -> AsyncThrowingStream<DeepCurationEvent, Error> {
        AsyncThrowingStream { continuation in
            let log = self.log
            var args = [
                "curate-agent",
                "--corpus", request.corpusPath.path,
                "--output", request.outputPath.path,
                "--report", request.reportPath.path,
            ]
            if request.dryRun { args.append("--dry-run") }

            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.executableURL = launcher.executableURL
            process.arguments = launcher.argumentPrefix + args
            if let cwd = launcher.workingDirectory {
                process.currentDirectoryURL = cwd
            }
            var env = launcher.environment ?? ProcessInfo.processInfo.environment
            if let apiKey, !apiKey.isEmpty {
                env["ANTHROPIC_API_KEY"] = apiKey
            }
            process.environment = env
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            let producer = Task.detached {
                do {
                    for try await line in stdoutPipe.fileHandleForReading.bytes.lines {
                        if Task.isCancelled { break }
                        guard !line.isEmpty else { continue }
                        guard let data = line.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let event = obj["event"] as? String
                        else {
                            log.debug("curate-agent: skip line: \(line, privacy: .public)")
                            continue
                        }
                        switch event {
                        case "agent_thinking":
                            continuation.yield(.thinking(content: obj["content"] as? String ?? ""))
                        case "agent_progress":
                            continuation.yield(.progress(
                                samplesReviewed: (obj["samples_reviewed"] as? Int) ?? 0,
                                removals: (obj["removals"] as? Int) ?? 0,
                                flags: (obj["flags"] as? Int) ?? 0
                            ))
                        case "agent_completion":
                            continuation.yield(.completion(
                                samplesKept: (obj["samples_kept"] as? Int) ?? 0,
                                samplesRemoved: (obj["samples_removed"] as? Int) ?? 0,
                                samplesFlagged: (obj["samples_flagged"] as? Int) ?? 0,
                                reportPath: obj["report_path"] as? String ?? "",
                                curatedPath: obj["curated_path"] as? String ?? ""
                            ))
                        case "error":
                            if (obj["recoverable"] as? Bool) == false {
                                continuation.yield(.error(
                                    code: obj["code"] as? String ?? "internal",
                                    message: obj["message"] as? String ?? ""
                                ))
                            }
                        case "ready", "done":
                            continue
                        default:
                            continue
                        }
                    }
                    process.waitUntilExit()
                    if process.terminationStatus == 0 {
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: DeepCurationError.unexpectedExit(
                            code: process.terminationStatus, stderrTail: ""
                        ))
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                // Saturday-final cancellation retrofit: SIGTERM, give the
                // child a 5 s grace, then SIGKILL if still alive. The
                // managed-agent path can sit on a long-running Anthropic
                // session-deploy call; without escalation an early stream
                // break would block on the full HTTP timeout.
                producer.cancel()
                if process.isRunning {
                    process.terminate()
                    let deadline = DispatchTime.now() + .seconds(5)
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
                producer.cancel()
                continuation.finish(throwing: DeepCurationError.launchFailed(
                    message: error.localizedDescription
                ))
            }
        }
    }
}
