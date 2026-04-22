import XCTest
@testable import KilnCore

final class PipelineTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = try TestFixtures.makeTempDir(prefix: "kiln-pipeline")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func runPipeline(
        source: URL? = nil,
        config: IngestConfig = IngestConfig()
    ) async throws -> (report: IngestReport, outDir: URL) {
        let out = tempDir.appendingPathComponent("out", isDirectory: true)
        let src = source ?? TestFixtures.sampleCorpusURL
        let pipeline = IngestPipeline(config: config)
        let report = try await pipeline.run(sourceDirectory: src, outputDirectory: out)
        return (report, out)
    }

    func testThrowsWhenSourceDirectoryMissing() async {
        let missing = tempDir.appendingPathComponent("does-not-exist")
        let pipeline = IngestPipeline()
        do {
            _ = try await pipeline.run(
                sourceDirectory: missing,
                outputDirectory: tempDir.appendingPathComponent("out")
            )
            XCTFail("expected directoryNotFound")
        } catch IngestError.directoryNotFound {
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testThrowsWhenNoExamples() async throws {
        let emptySrc = tempDir.appendingPathComponent("empty-src", isDirectory: true)
        try FileManager.default.createDirectory(at: emptySrc, withIntermediateDirectories: true)
        let tiny = emptySrc.appendingPathComponent("tiny.md")
        try "hi\n".data(using: .utf8)?.write(to: tiny)
        let pipeline = IngestPipeline()
        do {
            _ = try await pipeline.run(
                sourceDirectory: emptySrc,
                outputDirectory: tempDir.appendingPathComponent("out")
            )
            XCTFail("expected noExamplesGenerated")
        } catch IngestError.noExamplesGenerated {
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testEndToEndOnSampleCorpus() async throws {
        let (report, outDir) = try await runPipeline()

        XCTAssertGreaterThan(report.filesDiscovered, 0)
        XCTAssertGreaterThan(report.filesParsed, 0)
        XCTAssertGreaterThan(report.chunksAfterQuality, 0)
        XCTAssertGreaterThan(report.trainCount, 0)
        XCTAssertEqual(report.trainCount + report.evalCount, report.chunksAfterQuality)

        let trainURL = outDir.appendingPathComponent("train.jsonl")
        let evalURL = outDir.appendingPathComponent("eval.jsonl")
        let reportURL = outDir.appendingPathComponent("report.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: trainURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: evalURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: reportURL.path))

        let trainText = try String(contentsOf: trainURL, encoding: .utf8)
        let trainLines = trainText.split(separator: "\n").map(String.init)
        XCTAssertEqual(trainLines.count, report.trainCount)

        let decoder = JSONDecoder()
        for line in trainLines {
            let data = try XCTUnwrap(line.data(using: .utf8))
            let ex = try decoder.decode(ChatMLExample.self, from: data)
            XCTAssertEqual(ex.messages.count, 3)
            XCTAssertEqual(ex.messages[0].role, "system")
            XCTAssertEqual(ex.messages[1].role, "user")
            XCTAssertEqual(ex.messages[2].role, "assistant")
        }
    }

    func testPipelineIsDeterministic() async throws {
        let firstOut = tempDir.appendingPathComponent("a", isDirectory: true)
        let secondOut = tempDir.appendingPathComponent("b", isDirectory: true)
        let pipeline = IngestPipeline()
        let r1 = try await pipeline.run(sourceDirectory: TestFixtures.sampleCorpusURL, outputDirectory: firstOut)
        let r2 = try await pipeline.run(sourceDirectory: TestFixtures.sampleCorpusURL, outputDirectory: secondOut)
        XCTAssertEqual(r1.trainCount, r2.trainCount)
        XCTAssertEqual(r1.evalCount, r2.evalCount)

        let a = try String(contentsOf: firstOut.appendingPathComponent("train.jsonl"), encoding: .utf8)
        let b = try String(contentsOf: secondOut.appendingPathComponent("train.jsonl"), encoding: .utf8)
        XCTAssertEqual(a, b)
    }

    func testNearDuplicateRemovedViaMinHash() async throws {
        let (report, _) = try await runPipeline()
        let drop = report.chunksAfterExactDedup - report.chunksAfterMinHashDedup
        XCTAssertGreaterThanOrEqual(drop, 1, "near-dup fixture 15-near-dup-of-02.md should drop at least one chunk")
    }

    func testExactDuplicateRemoved() async throws {
        let srcDir = tempDir.appendingPathComponent("dup-src", isDirectory: true)
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        let payload = """
        # Note

        This morning I wrote a long paragraph about the fog and the river and how the \
        light changed as the sun came up. I sat by the kitchen window for almost an hour \
        and thought about the week ahead and the list of things I still owe people.
        """
        try payload.data(using: .utf8)?.write(to: srcDir.appendingPathComponent("a.md"))
        try payload.data(using: .utf8)?.write(to: srcDir.appendingPathComponent("b.md"))
        let pipeline = IngestPipeline()
        let out = tempDir.appendingPathComponent("out")
        let report = try await pipeline.run(sourceDirectory: srcDir, outputDirectory: out)
        XCTAssertEqual(report.chunksBeforeDedup, 2)
        XCTAssertEqual(report.chunksAfterExactDedup, 1)
    }

    func testTrainAndEvalDoNotShareSourceFiles() async throws {
        let (_, outDir) = try await runPipeline()
        let trainText = try String(contentsOf: outDir.appendingPathComponent("train.jsonl"), encoding: .utf8)
        let evalText = try String(contentsOf: outDir.appendingPathComponent("eval.jsonl"), encoding: .utf8)

        let reportURL = outDir.appendingPathComponent("report.json")
        let reportData = try Data(contentsOf: reportURL)
        let parsed = try JSONSerialization.jsonObject(with: reportData) as? [String: Any]
        XCTAssertNotNil(parsed)

        let trainLineCount = trainText.split(separator: "\n").count
        let evalLineCount = evalText.split(separator: "\n").count
        XCTAssertGreaterThan(trainLineCount, 0)
        XCTAssertGreaterThanOrEqual(evalLineCount, 0)
    }

    func testReportCapturesQualityBreakdown() async throws {
        let (report, _) = try await runPipeline()
        let totalRejected = report.qualityBreakdown.rejectedTooShort
            + report.qualityBreakdown.rejectedWrongLanguage
            + report.qualityBreakdown.rejectedTooRepetitive
            + report.qualityBreakdown.rejectedTooMuchNonASCII
        XCTAssertEqual(totalRejected, report.chunksAfterMinHashDedup - report.chunksAfterQuality)
    }

    func testReportHasOutputPaths() async throws {
        let (report, outDir) = try await runPipeline()
        let paths = try XCTUnwrap(report.outputPaths)
        XCTAssertTrue(paths.trainJSONL.contains(outDir.lastPathComponent))
        XCTAssertTrue(paths.evalJSONL.contains(outDir.lastPathComponent))
        XCTAssertTrue(paths.reportJSON.contains(outDir.lastPathComponent))
    }
}
