import Foundation
import OSLog

/// Saturday Phase 3 — Swift runner for the ingest-agent orchestrator.
/// Spawns ``python -m kiln_trainer ingest-via-agent`` and streams
/// progress events back to the SwiftUI consumer.
///
/// The orchestrator emits five custom event types beyond the standard
/// ready/done/error: ``agent_thinking``, ``subagent_spawned``,
/// ``sample_found``, ``agent_decision``, ``completion``. The runner
/// decodes them into a typed ``IngestAgentEvent`` enum so the UI can
/// branch cleanly on each.

public enum IngestAgentEvent: Sendable, Hashable {
    case agentThinking(content: String)
    case orchestratorThinking(content: String)
    case subagentSpawned(source: String)
    case subagentReturned(source: String, samplesCount: Int)
    case sampleFound(source: String, sampleID: String, preview: String, confidence: Double)
    case agentDecision(content: String)
    case deduplicationRound(before: Int, after: Int)
    case qualityFilterRound(before: Int, after: Int)
    case finalization(totalSamples: Int)
    case completion(samplesKept: Int, sourcesProcessed: Int, sourcesSkipped: [String])
    case error(code: String, message: String)
}

public struct IngestAgentRequest: Sendable, Hashable {
    public let sources: [String]
    public let intent: String?
    public let local: Bool
    public let outputPath: URL
    public let documentsRoot: URL?
    public let perSourceLimit: Int

    public init(
        sources: [String],
        intent: String?,
        local: Bool,
        outputPath: URL,
        documentsRoot: URL? = nil,
        perSourceLimit: Int = 200
    ) {
        self.sources = sources
        self.intent = intent
        self.local = local
        self.outputPath = outputPath
        self.documentsRoot = documentsRoot
        self.perSourceLimit = perSourceLimit
    }
}

public enum IngestAgentError: Error, Equatable, Sendable {
    case launchFailed(message: String)
    case unexpectedExit(code: Int32, stderrTail: String)
}

public protocol IngestAgentRunner: Sendable {
    func runStreaming(request: IngestAgentRequest) -> AsyncThrowingStream<IngestAgentEvent, Error>
}

public final class SubprocessIngestAgentRunner: IngestAgentRunner, @unchecked Sendable {
    private let launcher: TrainerLauncher
    private let log = Logger(subsystem: "dev.kiln.core", category: "ingest-agent")

    public init(launcher: TrainerLauncher) {
        self.launcher = launcher
    }

    public func runStreaming(request: IngestAgentRequest) -> AsyncThrowingStream<IngestAgentEvent, Error> {
        AsyncThrowingStream { continuation in
            let log = self.log
            let launcher = self.launcher

            var args = [
                "ingest-via-agent",
                "--sources", request.sources.joined(separator: ","),
                "--output", request.outputPath.path,
                "--per-source-limit", String(request.perSourceLimit),
            ]
            if request.local { args.append("--local") }
            if let intent = request.intent, !intent.isEmpty {
                args.append(contentsOf: ["--intent", intent])
            }
            if let root = request.documentsRoot {
                args.append(contentsOf: ["--documents-root", root.path])
            }

            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.executableURL = launcher.executableURL
            process.arguments = launcher.argumentPrefix + args
            if let cwd = launcher.workingDirectory {
                process.currentDirectoryURL = cwd
            }
            if let env = launcher.environment {
                process.environment = env
            }
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            let stderrCollector = StderrCollector()
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
                stderrCollector.append(chunk)
            }

            let producer = Task.detached {
                let stdoutHandle = stdoutPipe.fileHandleForReading
                do {
                    for try await line in stdoutHandle.bytes.lines {
                        if Task.isCancelled { break }
                        guard !line.isEmpty else { continue }
                        guard let data = line.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let event = obj["event"] as? String
                        else {
                            log.debug("ingest-agent: skip line: \(line, privacy: .public)")
                            continue
                        }
                        switch event {
                        case "agent_thinking":
                            continuation.yield(.agentThinking(
                                content: obj["content"] as? String ?? ""
                            ))
                        case "orchestrator_thinking":
                            continuation.yield(.orchestratorThinking(
                                content: obj["content"] as? String ?? ""
                            ))
                        case "subagent_spawned":
                            continuation.yield(.subagentSpawned(
                                source: obj["source"] as? String ?? ""
                            ))
                        case "subagent_returned":
                            continuation.yield(.subagentReturned(
                                source: obj["source"] as? String ?? "",
                                samplesCount: (obj["samples_count"] as? Int) ?? 0
                            ))
                        case "sample_found":
                            continuation.yield(.sampleFound(
                                source: obj["source"] as? String ?? "",
                                sampleID: obj["sample_id"] as? String ?? "",
                                preview: obj["preview"] as? String ?? "",
                                confidence: (obj["confidence"] as? Double) ?? 0.5
                            ))
                        case "agent_decision":
                            continuation.yield(.agentDecision(
                                content: obj["content"] as? String ?? ""
                            ))
                        case "deduplication_round":
                            continuation.yield(.deduplicationRound(
                                before: (obj["before"] as? Int) ?? 0,
                                after: (obj["after"] as? Int) ?? 0
                            ))
                        case "quality_filter_round":
                            continuation.yield(.qualityFilterRound(
                                before: (obj["before"] as? Int) ?? 0,
                                after: (obj["after"] as? Int) ?? 0
                            ))
                        case "finalization":
                            continuation.yield(.finalization(
                                totalSamples: (obj["total_samples"] as? Int) ?? 0
                            ))
                        case "completion":
                            continuation.yield(.completion(
                                samplesKept: (obj["samples_kept"] as? Int) ?? 0,
                                sourcesProcessed: (obj["sources_processed"] as? Int) ?? 0,
                                sourcesSkipped: (obj["sources_skipped"] as? [String]) ?? []
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
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    if process.terminationStatus == 0 {
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: IngestAgentError.unexpectedExit(
                            code: process.terminationStatus,
                            stderrTail: stderrCollector.snapshot()
                        ))
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                // Saturday-final cancellation retrofit: SIGTERM, give the
                // child a 5 s grace window, then SIGKILL if still alive.
                // Mirrors the OllamaExporter pattern. Without the
                // escalation, an agent loop that's mid-Anthropic-API-call
                // could hang for the full HTTP timeout (~60 s) instead of
                // exiting promptly when the user cancels.
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
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                producer.cancel()
                continuation.finish(throwing: IngestAgentError.launchFailed(
                    message: error.localizedDescription
                ))
            }
        }
    }
}

private final class StderrCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""
    func append(_ s: String) {
        lock.lock(); defer { lock.unlock() }
        buffer.append(s)
        if buffer.count > 4096 { buffer = String(buffer.suffix(4096)) }
    }
    func snapshot() -> String {
        lock.lock(); defer { lock.unlock() }
        return buffer
    }
}
