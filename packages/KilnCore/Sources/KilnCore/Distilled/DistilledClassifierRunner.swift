import Foundation
import OSLog

/// One row to classify — paired ``requestID`` is echoed back on the
/// emitted event so the caller can match results to inputs.
public struct ClassifierInputRow: Sendable, Hashable {
    public let requestID: String
    public let text: String

    public init(requestID: String, text: String) {
        self.requestID = requestID
        self.text = text
    }
}

/// Quality classifier — scores corpus chunks for the keep / chosen-only /
/// discard routing used by the Dataset Doctor and the DPO prep pipeline.
public protocol QualityClassifierRunner: Sendable {
    func classify(_ rows: [ClassifierInputRow]) async throws -> [QualityScore]
}

/// Style extractor — produces a ``DistilledStyleProfile`` per corpus.
///
/// The Python side's ``--mode style`` runs descriptor + TF-IDF n-gram
/// extraction over a single text; passing many rows therefore returns
/// many per-row profiles. The Style Signature Card consumer pools rows
/// into one corpus-level call, then derives a single profile from the
/// aggregate.
public protocol StyleExtractorRunner: Sendable {
    func extract(_ rows: [ClassifierInputRow]) async throws -> [DistilledStyleProfile]
}

// MARK: - Subprocess implementation

/// Production runner: spawns ``python -m kiln_trainer classify ...``,
/// reads stdout JSON-line events, returns typed results.
///
/// One process per ``classify(_:)`` call — for a 500-row corpus that
/// pays the ~0.7s sklearn-load cost once. Tests can substitute a
/// custom ``TrainerLauncher`` (e.g. pointing at a fake script) the same
/// way ``SubprocessTrainingRunner`` does.
public final class SubprocessDistilledClassifierRunner: QualityClassifierRunner, StyleExtractorRunner, @unchecked Sendable {
    public enum Mode: String, Sendable {
        case quality
        case style
        case preference
    }

    private let launcher: TrainerLauncher
    private let qualityArtifactPath: URL?
    private let sigtermGraceSeconds: TimeInterval
    private let log = Logger(subsystem: "dev.kiln.core", category: "classifier")

    public init(
        launcher: TrainerLauncher,
        qualityArtifactPath: URL?,
        sigtermGraceSeconds: TimeInterval = 5
    ) {
        self.launcher = launcher
        self.qualityArtifactPath = qualityArtifactPath
        self.sigtermGraceSeconds = sigtermGraceSeconds
    }

    public func classify(_ rows: [ClassifierInputRow]) async throws -> [QualityScore] {
        let payloads = try await runStreaming(mode: .quality, rows: rows)
        return try payloads.map { req, dict in
            guard let score = dict["score"] as? Double,
                  let bucketRaw = dict["bucket"] as? String,
                  let bucket = QualityBucket(rawValue: bucketRaw)
            else {
                throw DistilledClassifierError.sidecarError(
                    code: "decode",
                    message: "quality payload missing score/bucket: \(dict)"
                )
            }
            return QualityScore(requestID: req, score: score, bucket: bucket)
        }
    }

    public func extract(_ rows: [ClassifierInputRow]) async throws -> [DistilledStyleProfile] {
        let payloads = try await runStreaming(mode: .style, rows: rows)
        return try payloads.map { req, dict in
            guard let descDict = dict["style_descriptors"] as? [String: Any],
                  let ngrams = dict["distinctive_ngrams"] as? [String],
                  let markdown = dict["style_card_md"] as? String
            else {
                throw DistilledClassifierError.sidecarError(
                    code: "decode",
                    message: "style payload missing fields: \(dict)"
                )
            }
            let descriptors = try Self.descriptors(from: descDict)
            return DistilledStyleProfile(
                requestID: req,
                descriptors: descriptors,
                distinctiveNgrams: ngrams,
                styleCardMarkdown: markdown
            )
        }
    }

    // MARK: - Internals

    /// Writes ``rows`` to a temp JSONL, spawns the subprocess, parses
    /// ``classification`` events, returns ``(requestID, payloadDict)``
    /// in input order. Throws on non-zero exit or missing results.
    private func runStreaming(
        mode: Mode,
        rows: [ClassifierInputRow]
    ) async throws -> [(String, [String: Any])] {
        guard !rows.isEmpty else { return [] }

        // Use a temp JSONL — keeps argv length bounded for large corpora.
        let inputURL = try Self.writeInputJSONL(rows: rows)
        defer { try? FileManager.default.removeItem(at: inputURL) }

        var args: [String] = [
            "classify",
            "--mode", mode.rawValue,
            "--input-file", inputURL.path,
        ]
        if mode == .quality {
            guard let artifact = qualityArtifactPath else {
                throw DistilledClassifierError.launchFailed(
                    message: "quality artifact path required but not configured"
                )
            }
            args.append(contentsOf: ["--artifact", artifact.path])
        }

        return try await runProcess(arguments: args, expected: rows.count)
    }

    private func runProcess(
        arguments subcommandArgs: [String],
        expected: Int
    ) async throws -> [(String, [String: Any])] {
        let log = self.log
        // Saturday-audit T2: pre-launch cancellation check + SIGTERM
        // hook on outer-task cancellation. ``Task.detached`` does not
        // propagate the parent's cancellation, so we register a
        // ``withTaskCancellationHandler`` whose ``onCancel`` runs on
        // the cancelling task and SIGTERMs the child synchronously.
        try Task.checkCancellation()

        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = launcher.executableURL
        process.arguments = launcher.argumentPrefix + subcommandArgs
        if let cwd = launcher.workingDirectory {
            process.currentDirectoryURL = cwd
        }
        if let env = launcher.environment {
            process.environment = env
        }
        process.standardOutput = stdout
        process.standardError = stderr

        // Wrap the Process in a tiny @unchecked Sendable box so we can
        // reach it from the cancellation handler without crossing the
        // Sendable warning. ``Process`` is internally thread-safe for
        // ``isRunning`` / ``terminate`` calls.
        struct ProcessBox: @unchecked Sendable { let p: Process }
        let box = ProcessBox(p: process)

        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) {
                do {
                    try process.run()
                } catch {
                    throw DistilledClassifierError.launchFailed(message: error.localizedDescription)
                }

            // Read stdout and stderr concurrently to EOF — verifier T3
            // finding from PR #15 / PR #17. Reading them sequentially
            // (stdout first) deadlocks if the child ever fills the
            // 64 KB stderr pipe buffer before closing stdout (e.g. a
            // sklearn version-skew traceback on a corrupted pickle).
            // The classify / embed-search subcommands are bounded in
            // practice but a real production failure mode still
            // motivates the concurrent drain.
            //
            // ``Task.detached`` runs both pipe reads off the cooperative
            // pool; ``readDataToEndOfFile`` is otherwise the same call.
            async let stdoutTask = Task.detached { stdout.fileHandleForReading.readDataToEndOfFile() }.value
            async let stderrTask = Task.detached { stderr.fileHandleForReading.readDataToEndOfFile() }.value
            let stdoutData = await stdoutTask
            let stderrData = await stderrTask

            process.waitUntilExit()

            let stdoutText = String(data: stdoutData, encoding: .utf8) ?? ""
            let stderrText = String(data: stderrData, encoding: .utf8) ?? ""

            var collected: [(String, [String: Any])] = []
            var sidecarError: DistilledClassifierError? = nil
            for raw in stdoutText.split(separator: "\n", omittingEmptySubsequences: true) {
                let line = String(raw)
                guard let data = line.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let event = obj["event"] as? String
                else {
                    log.debug("classify: skipping unparseable line: \(line, privacy: .public)")
                    continue
                }
                switch event {
                case "classification":
                    if let req = obj["request_id"] as? String,
                       let payload = obj["payload"] as? [String: Any] {
                        collected.append((req, payload))
                    }
                case "error":
                    if (obj["recoverable"] as? Bool) == false {
                        let code = obj["code"] as? String ?? "internal"
                        let message = obj["message"] as? String ?? ""
                        sidecarError = .sidecarError(code: code, message: message)
                    }
                case "ready", "done":
                    continue
                default:
                    continue
                }
            }

            if let sidecarError {
                throw sidecarError
            }
            if process.terminationStatus != 0 {
                throw DistilledClassifierError.unexpectedExit(
                    code: process.terminationStatus,
                    stderrTail: String(stderrText.suffix(4096))
                )
            }
            if collected.count != expected {
                throw DistilledClassifierError.missingResults(
                    expected: expected,
                    received: collected.count
                )
            }
            return collected
            }.value
        } onCancel: {
            // Outer task was cancelled; SIGTERM the child so the
            // detached body's ``waitUntilExit`` returns and the
            // continuation completes. ``terminate`` is a no-op if the
            // child already exited.
            if box.p.isRunning {
                box.p.terminate()
            }
        }
    }

    private static func writeInputJSONL(rows: [ClassifierInputRow]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kiln-classify-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("input.jsonl")
        let data = rows.map { row -> String in
            let obj: [String: Any] = ["request_id": row.requestID, "text": row.text]
            let bytes = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
            return String(data: bytes, encoding: .utf8) ?? ""
        }.joined(separator: "\n")
        try data.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func descriptors(from dict: [String: Any]) throws -> StyleDescriptors {
        func grab(_ key: String) throws -> Double {
            if let n = dict[key] as? Double { return n }
            if let n = dict[key] as? NSNumber { return n.doubleValue }
            throw DistilledClassifierError.sidecarError(
                code: "decode",
                message: "missing style descriptor: \(key)"
            )
        }
        return StyleDescriptors(
            formality: try grab("formality"),
            verbosity: try grab("verbosity"),
            warmth: try grab("warmth"),
            hedging: try grab("hedging"),
            humor: try grab("humor"),
            directness: try grab("directness")
        )
    }
}

