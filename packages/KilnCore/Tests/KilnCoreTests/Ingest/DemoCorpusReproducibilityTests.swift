import XCTest
@testable import KilnCore

/// Phase 3 reproducibility check (Saturday autonomous session). The
/// demo corpus at ``tests/fixtures/demo_corpus/`` is what Tim drops
/// into the app during the recorded walkthrough. Running it through
/// the full ingest pipeline must produce a non-trivial ``IngestReport``
/// without surfacing any unexpected errors — if any step fails the
/// recording fails too.
///
/// Numbers asserted below are *floors*, not exact equalities — small
/// drift across pipeline tweaks shouldn't break the test, but a
/// silent regression that drops every chunk to zero (e.g. a parser
/// crash on the markdown frontmatter, a dedup pass collapsing the
/// whole corpus) would.
final class DemoCorpusReproducibilityTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = try TestFixtures.makeTempDir(prefix: "kiln-demo-corpus")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_demo_corpus_directory_exists_with_expected_shape() {
        let demo = TestFixtures.demoCorpusURL
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: demo.path, isDirectory: &isDir)
        XCTAssertTrue(exists, "demo_corpus directory must ship in the repo")
        XCTAssertTrue(isDir.boolValue)

        // The corpus is structured into five top-level groups; the demo
        // narrative leans on each group looking like a different source.
        let expected = ["notes", "journal", "emails", "chat", "code_comments"]
        for sub in expected {
            let url = demo.appendingPathComponent(sub, isDirectory: true)
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: url.path),
                "missing demo group: \(sub)"
            )
        }
    }

    func test_demo_corpus_has_at_least_150_files_to_train_on() throws {
        let demo = TestFixtures.demoCorpusURL
        guard let enumerator = FileManager.default.enumerator(at: demo, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return XCTFail("demo corpus enumerator failed")
        }
        var n = 0
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            if values.isRegularFile == true { n += 1 }
        }
        // 223 files at audit time. Floor at 150 lets the corpus shrink
        // without breaking the test, but catches a catastrophic loss.
        XCTAssertGreaterThanOrEqual(n, 150, "demo corpus shrunk to \(n) files — recording will look anemic")
    }

    func test_full_pipeline_run_against_demo_corpus_produces_non_trivial_report() async throws {
        let outDir = tempDir.appendingPathComponent("out", isDirectory: true)
        let pipeline = IngestPipeline()
        let report = try await pipeline.run(
            sourceDirectory: TestFixtures.demoCorpusURL,
            outputDirectory: outDir
        )

        // Pipeline read more than zero files.
        XCTAssertGreaterThan(report.filesParsed, 100, "pipeline parsed only \(report.filesParsed) files")

        // Every gate produces *some* survivors. A regression that drops
        // every chunk to zero on any single gate would break the demo.
        XCTAssertGreaterThan(report.chunksBeforeDedup, 0)
        XCTAssertGreaterThan(report.chunksAfterExactDedup, 0)
        XCTAssertGreaterThan(report.chunksAfterMinHashDedup, 0)
        XCTAssertGreaterThan(report.chunksAfterQuality, 0,
                             "no chunks survived the quality gate — demo would show 'Kept: 0'")

        // Output JSONL paths are populated.
        XCTAssertNotNil(report.outputPaths)

        // Train + eval splits both have entries.
        XCTAssertGreaterThan(report.trainCount, 0)
        XCTAssertGreaterThan(report.evalCount, 0)
    }

    func test_pipeline_run_against_demo_corpus_completes_within_reasonable_time() async throws {
        // Tim's demo recording is a 3-minute video. The ingest take
        // shouldn't take more than ~10 s on a warm machine; we floor
        // the test budget at 60 s to leave headroom for CI variance.
        let outDir = tempDir.appendingPathComponent("out", isDirectory: true)
        let start = Date()
        let pipeline = IngestPipeline()
        _ = try await pipeline.run(
            sourceDirectory: TestFixtures.demoCorpusURL,
            outputDirectory: outDir
        )
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 60.0, "demo corpus ingest took \(elapsed) s — recording will feel slow")
    }
}
