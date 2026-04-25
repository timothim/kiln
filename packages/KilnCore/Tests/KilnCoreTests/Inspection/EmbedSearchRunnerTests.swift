import Foundation
import XCTest
@testable import KilnCore

/// Tests for the M9.B ``EmbedSearchRunner`` against a shell-script fake
/// launcher. Same pattern as ``DistilledClassifierRunnerTests`` (M9.C);
/// no Python or sentence-transformers dependency in CI.
final class EmbedSearchRunnerTests: XCTestCase {

    private func makeFakeLauncher(
        emit lines: [String],
        exitCode: Int32 = 0
    ) throws -> (TrainerLauncher, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kiln-embed-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let script = dir.appendingPathComponent("fake-embed.sh")
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

    func test_search_returns_matches_in_rank_order() async throws {
        let canned = [
            #"{"event":"ready","version":"0.1.0","mlx":"0.22.1"}"#,
            #"{"event":"classification","request_id":"r2","kind":"embed_search","payload":{"similarity":0.91,"rank":0}}"#,
            #"{"event":"classification","request_id":"r1","kind":"embed_search","payload":{"similarity":0.74,"rank":1}}"#,
            #"{"event":"classification","request_id":"r3","kind":"embed_search","payload":{"similarity":0.62,"rank":2}}"#,
            #"{"event":"done","stage":"generation","artifact":"stdout","interrupted":false}"#,
        ]
        let (launcher, dir) = try makeFakeLauncher(emit: canned)
        defer { try? FileManager.default.removeItem(at: dir) }

        let runner = SubprocessEmbedSearchRunner(launcher: launcher)
        let matches = try await runner.search(
            query: "anything",
            corpus: [
                EmbedSearchCorpusRow(requestID: "r1", text: "one"),
                EmbedSearchCorpusRow(requestID: "r2", text: "two"),
                EmbedSearchCorpusRow(requestID: "r3", text: "three"),
            ],
            topK: 3,
            embedder: "fake-hash"
        )
        XCTAssertEqual(matches.count, 3)
        XCTAssertEqual(matches[0].requestID, "r2")
        XCTAssertEqual(matches[0].rank, 0)
        XCTAssertEqual(matches[0].similarity, 0.91, accuracy: 1e-9)
        XCTAssertEqual(matches[1].rank, 1)
        XCTAssertEqual(matches[2].rank, 2)
    }

    func test_search_throws_on_sidecar_error() async throws {
        let canned = [
            #"{"event":"ready","version":"0.1.0","mlx":"0.22.1"}"#,
            #"{"event":"error","code":"data_invalid","message":"--query is required","recoverable":false}"#,
            #"{"event":"done","stage":"generation","artifact":"stdout","interrupted":false}"#,
        ]
        let (launcher, dir) = try makeFakeLauncher(emit: canned, exitCode: 1)
        defer { try? FileManager.default.removeItem(at: dir) }

        let runner = SubprocessEmbedSearchRunner(launcher: launcher)
        do {
            _ = try await runner.search(
                query: "irrelevant",
                corpus: [EmbedSearchCorpusRow(requestID: "r1", text: "x")],
                topK: 1,
                embedder: "fake-hash"
            )
            XCTFail("expected sidecarError")
        } catch EmbedSearchError.sidecarError(let code, _) {
            XCTAssertEqual(code, "data_invalid")
        } catch {
            XCTFail("expected sidecarError, got \(error)")
        }
    }

    func test_search_throws_on_unexpected_exit() async throws {
        let canned = [
            #"{"event":"ready","version":"0.1.0","mlx":"0.22.1"}"#,
            #"{"event":"done","stage":"generation","artifact":"stdout","interrupted":false}"#,
        ]
        let (launcher, dir) = try makeFakeLauncher(emit: canned, exitCode: 7)
        defer { try? FileManager.default.removeItem(at: dir) }

        let runner = SubprocessEmbedSearchRunner(launcher: launcher)
        do {
            _ = try await runner.search(
                query: "q",
                corpus: [EmbedSearchCorpusRow(requestID: "r1", text: "x")],
                topK: 1,
                embedder: "fake-hash"
            )
            XCTFail("expected unexpectedExit")
        } catch EmbedSearchError.unexpectedExit(let code, _) {
            XCTAssertEqual(code, 7)
        } catch {
            XCTFail("expected unexpectedExit, got \(error)")
        }
    }

    func test_search_short_circuits_on_empty_corpus() async throws {
        // Use a launcher that would FAIL if invoked — empty corpus must
        // bypass the subprocess entirely.
        let launcher = TrainerLauncher(
            executableURL: URL(fileURLWithPath: "/usr/bin/false"),
            argumentPrefix: [],
            workingDirectory: nil,
            environment: nil
        )
        let runner = SubprocessEmbedSearchRunner(launcher: launcher)
        let matches = try await runner.search(
            query: "q",
            corpus: [],
            topK: 5,
            embedder: "fake-hash"
        )
        XCTAssertEqual(matches, [])
    }

    func test_results_sorted_by_rank_even_if_sidecar_emits_unordered() async throws {
        // Sidecar today sorts before emitting, but the runner enforces it
        // too. Feed unsorted ranks; expect ascending rank order in output.
        let canned = [
            #"{"event":"ready","version":"0.1.0","mlx":"0.22.1"}"#,
            #"{"event":"classification","request_id":"rA","kind":"embed_search","payload":{"similarity":0.5,"rank":2}}"#,
            #"{"event":"classification","request_id":"rB","kind":"embed_search","payload":{"similarity":0.9,"rank":0}}"#,
            #"{"event":"classification","request_id":"rC","kind":"embed_search","payload":{"similarity":0.7,"rank":1}}"#,
            #"{"event":"done","stage":"generation","artifact":"stdout","interrupted":false}"#,
        ]
        let (launcher, dir) = try makeFakeLauncher(emit: canned)
        defer { try? FileManager.default.removeItem(at: dir) }

        let runner = SubprocessEmbedSearchRunner(launcher: launcher)
        let matches = try await runner.search(
            query: "q",
            corpus: [
                EmbedSearchCorpusRow(requestID: "rA", text: "a"),
                EmbedSearchCorpusRow(requestID: "rB", text: "b"),
                EmbedSearchCorpusRow(requestID: "rC", text: "c"),
            ],
            topK: 3,
            embedder: "fake-hash"
        )
        XCTAssertEqual(matches.map(\.rank), [0, 1, 2])
        XCTAssertEqual(matches.map(\.requestID), ["rB", "rC", "rA"])
    }
}
