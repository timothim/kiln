import XCTest
import KilnCore
@testable import Kiln

@MainActor
final class PrepareIntegrationTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory
        tempDir = base.appendingPathComponent("kiln-integ-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    /// Repo-root resolution mirrors KilnCore's TestFixtures — walk up from this file.
    private var sampleCorpusURL: URL {
        let thisFile = URL(fileURLWithPath: #filePath)
        let repoRoot = thisFile
            .deletingLastPathComponent() // KilnTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // Kiln/
            .deletingLastPathComponent() // apps/
            .deletingLastPathComponent() // repo root
        return repoRoot
            .appendingPathComponent("tests")
            .appendingPathComponent("fixtures")
            .appendingPathComponent("sample_corpus")
    }

    private func waitForStatus(
        _ model: PrepareModel,
        timeout: TimeInterval = 30.0,
        file: StaticString = #file,
        line: UInt = #line,
        predicate: @escaping @MainActor (PrepareModel.Status) -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate(model.status) { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("timed out waiting for status; observed \(model.status)", file: file, line: line)
    }

    func test_integration_on_sample_corpus_completes() async throws {
        let out = tempDir.appendingPathComponent("out")
        let model = PrepareModel()

        // Sanity baseline via direct pipeline run.
        let direct = try await IngestPipeline().run(
            sourceDirectory: sampleCorpusURL,
            outputDirectory: tempDir.appendingPathComponent("direct")
        )

        model.start(folderURL: sampleCorpusURL, outputDirectory: out)
        await waitForStatus(model) { status in
            if case .completed = status { return true }
            return false
        }
        guard case .completed(let report) = model.status else {
            XCTFail("expected .completed")
            return
        }
        XCTAssertEqual(report.trainCount, direct.trainCount)
        XCTAssertEqual(report.evalCount, direct.evalCount)
        XCTAssertEqual(report.chunksAfterQuality, direct.chunksAfterQuality)
        XCTAssertGreaterThan(model.counts.filesParsed, 0)
    }

    func test_integration_cancellation_propagates_through_streaming_api() async throws {
        let src = tempDir.appendingPathComponent("big-src", isDirectory: true)
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        let body = String(repeating: "This paragraph has enough words to pass the minimum chunk length threshold and avoid being skipped as too short. ", count: 8)
        for i in 0..<4000 {
            let url = src.appendingPathComponent("f-\(i).md")
            try (body + "tail \(i).").data(using: .utf8)?.write(to: url)
        }
        let out = tempDir.appendingPathComponent("out")
        let model = PrepareModel()
        model.start(folderURL: src, outputDirectory: out)

        await waitForStatus(model, timeout: 5.0) { status in
            if case .running = status { return true }
            return false
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        model.cancel()
        await waitForStatus(model, timeout: 5.0) { status in
            if case .failed(.cancelled) = status { return true }
            if case .completed = status { return true }
            return false
        }
        // We accept either outcome: fast machines may complete before cancel lands.
        // What we do NOT accept is remaining stuck in .cancelling or .running.
        switch model.status {
        case .failed(.cancelled): break
        case .completed: break
        default:
            XCTFail("expected .failed(.cancelled) or .completed, got \(model.status)")
        }
    }

    func test_integration_failure_propagates_directory_not_found() async {
        let missing = URL(fileURLWithPath: "/tmp/kiln-does-not-exist-\(UUID().uuidString)")
        let out = tempDir.appendingPathComponent("out")
        let model = PrepareModel()
        model.start(folderURL: missing, outputDirectory: out)

        await waitForStatus(model) { status in
            if case .failed(.directoryNotFound) = status { return true }
            return false
        }
    }
}
