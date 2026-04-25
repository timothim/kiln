import Foundation
import OSLog

/// Voice Inspector embedding-similarity search (M9.B).
///
/// Wraps ``python -m kiln_trainer embed-search``. The sidecar embeds the
/// query and corpus via ``sentence-transformers/all-MiniLM-L6-v2`` and
/// emits ``classification`` events with ``kind="embed_search"`` for the
/// top-K matches. This runner shells the subprocess, parses stdout, and
/// returns typed ``EmbedSearchMatch`` rows in rank order.
///
/// Mirrors ``SubprocessDistilledClassifierRunner`` (M9.C) — same launcher,
/// same synchronous-after-exit read pattern. Splitting the two runners
/// keeps the embed-search dependency on sentence-transformers contained;
/// the M9.C distilled-classifier path stays sklearn-only.

public struct EmbedSearchMatch: Sendable, Hashable, Codable {
    public let requestID: String
    public let similarity: Double
    public let rank: Int

    public init(requestID: String, similarity: Double, rank: Int) {
        self.requestID = requestID
        self.similarity = similarity
        self.rank = rank
    }
}

public struct EmbedSearchCorpusRow: Sendable, Hashable, Codable {
    public let requestID: String
    public let text: String

    public init(requestID: String, text: String) {
        self.requestID = requestID
        self.text = text
    }
}

public enum EmbedSearchError: Error, Equatable, Sendable {
    case launchFailed(message: String)
    case unexpectedExit(code: Int32, stderrTail: String)
    case sidecarError(code: String, message: String)
    case writeFailed(path: String)
}

public protocol EmbedSearchRunner: Sendable {
    /// Embeds ``query`` against ``corpus``, returns the top-K matches in
    /// descending similarity. ``embedder`` is normally
    /// ``"sentence-transformers"`` in production; tests pass
    /// ``"fake-hash"`` for a deterministic offline embedder.
    func search(
        query: String,
        corpus: [EmbedSearchCorpusRow],
        topK: Int,
        embedder: String
    ) async throws -> [EmbedSearchMatch]
}

public final class SubprocessEmbedSearchRunner: EmbedSearchRunner, @unchecked Sendable {
    private let launcher: TrainerLauncher
    private let log = Logger(subsystem: "dev.kiln.core", category: "embed-search")

    public init(launcher: TrainerLauncher) {
        self.launcher = launcher
    }

    public func search(
        query: String,
        corpus: [EmbedSearchCorpusRow],
        topK: Int = 3,
        embedder: String = "sentence-transformers"
    ) async throws -> [EmbedSearchMatch] {
        guard !corpus.isEmpty else { return [] }

        let corpusURL = try Self.writeCorpusJSONL(rows: corpus)
        defer { try? FileManager.default.removeItem(at: corpusURL) }

        let args: [String] = [
            "embed-search",
            "--query", query,
            "--corpus-file", corpusURL.path,
            "--top-k", String(topK),
            "--embedder", embedder,
        ]
        return try await runProcess(arguments: args)
    }

    private func runProcess(arguments subcommandArgs: [String]) async throws -> [EmbedSearchMatch] {
        let log = self.log
        return try await Task.detached(priority: .userInitiated) { [launcher] in
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

            do {
                try process.run()
            } catch {
                throw EmbedSearchError.launchFailed(message: error.localizedDescription)
            }

            // Synchronous read-to-EOF — output is bounded (≤ topK + 2 lines).
            // Same rationale as ``SubprocessDistilledClassifierRunner``: the
            // streaming async-bytes path hangs intermittently in the suite
            // when sibling tests run first; sync read avoids that entirely.
            let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            let stdoutText = String(data: stdoutData, encoding: .utf8) ?? ""
            let stderrText = String(data: stderrData, encoding: .utf8) ?? ""

            var matches: [EmbedSearchMatch] = []
            var sidecarError: EmbedSearchError? = nil
            for raw in stdoutText.split(separator: "\n", omittingEmptySubsequences: true) {
                let line = String(raw)
                guard let data = line.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let event = obj["event"] as? String
                else {
                    log.debug("embed-search: skipping unparseable line: \(line, privacy: .public)")
                    continue
                }
                switch event {
                case "classification":
                    guard let req = obj["request_id"] as? String,
                          let payload = obj["payload"] as? [String: Any],
                          let sim = payload["similarity"] as? Double ?? (payload["similarity"] as? NSNumber).map(\.doubleValue),
                          let rank = payload["rank"] as? Int ?? (payload["rank"] as? NSNumber).map(\.intValue)
                    else {
                        continue
                    }
                    matches.append(
                        EmbedSearchMatch(requestID: req, similarity: sim, rank: rank)
                    )
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
                throw EmbedSearchError.unexpectedExit(
                    code: process.terminationStatus,
                    stderrTail: String(stderrText.suffix(4096))
                )
            }
            // Already in rank order from the sidecar, but enforce here for
            // robustness — the sidecar guarantees descending similarity, so
            // sorting by rank ascending is equivalent and lets us survive a
            // future sidecar bug without scrambling the UI.
            matches.sort { $0.rank < $1.rank }
            return matches
        }.value
    }

    private static func writeCorpusJSONL(rows: [EmbedSearchCorpusRow]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kiln-embed-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("corpus.jsonl")
        let body = rows.map { row -> String in
            let obj: [String: Any] = ["request_id": row.requestID, "text": row.text]
            let bytes = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
            return String(data: bytes, encoding: .utf8) ?? ""
        }.joined(separator: "\n")
        do {
            try body.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw EmbedSearchError.writeFailed(path: url.path)
        }
        return url
    }
}
