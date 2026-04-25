import XCTest
import KilnCore
@testable import Kiln

@MainActor
final class CurationReviewModelTests: XCTestCase {

    private func writeReportFixture(
        in tmp: URL,
        decisions: [[String: Any]],
        summary: [String: Int] = ["keep": 0, "remove": 0, "flag": 0]
    ) throws -> URL {
        let reportURL = tmp.appendingPathComponent("report.json")
        let report: [String: Any] = [
            "component": "corpus-curator",
            "decisions": decisions,
            "summary": summary,
            "dry_run": true,
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted])
        try data.write(to: reportURL)
        return reportURL
    }

    private func writeCorpusFixture(in tmp: URL, rows: [(id: String, text: String)]) throws -> URL {
        let url = tmp.appendingPathComponent("corpus.jsonl")
        let lines = rows.map { row -> String in
            let obj: [String: Any] = ["request_id": row.id, "text": row.text]
            let data = try! JSONSerialization.data(withJSONObject: obj)
            return String(data: data, encoding: .utf8) ?? ""
        }
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kiln-curation-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - 1. Loads decisions and groups by category

    func test_loadFromReport_groups_decisions_by_reason_category() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let report = try writeReportFixture(in: tmp, decisions: [
            ["sample_id": "a", "recommended_action": "remove",
             "reason": "forwarded thread artifact (From:/Subject: header pattern)",
             "confidence": 0.9],
            ["sample_id": "b", "recommended_action": "remove",
             "reason": "corporate boilerplate, no voice signal",
             "confidence": 0.8],
            ["sample_id": "c", "recommended_action": "remove",
             "reason": "another forwarded thread sample",
             "confidence": 0.85],
            ["sample_id": "d", "recommended_action": "keep",
             "reason": "voice-bearing prose, kept as-is",
             "confidence": 0.95],
        ])
        let corpus = try writeCorpusFixture(in: tmp, rows: [
            (id: "a", text: "From: someone\nSubject: thing"),
            (id: "b", text: "stakeholder synergy going forward"),
            (id: "c", text: "From: again\nSubject: again"),
            (id: "d", text: "I went for a walk."),
        ])
        let review = try XCTUnwrap(
            CurationReviewModel.loadFromReport(reportPath: report, corpusPath: corpus)
        )
        XCTAssertEqual(review.decisions.count, 4)

        // Two decisions in "Forwarded thread", one in "Corporate boilerplate", one keep "Other".
        let groups = Dictionary(grouping: review.decisions, by: \.categoryKey)
        XCTAssertEqual(groups["Forwarded thread"]?.count, 2)
        XCTAssertEqual(groups["Corporate boilerplate"]?.count, 1)
        XCTAssertEqual(groups["Other"]?.count, 1)

        // Default acceptance: all "remove" actions accepted.
        XCTAssertEqual(review.pendingRemovalCount, 3)
    }

    // MARK: - 2. Per-category accept-all toggle

    func test_setAcceptance_for_category_toggles_only_that_bucket() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let report = try writeReportFixture(in: tmp, decisions: [
            ["sample_id": "a", "recommended_action": "remove",
             "reason": "forwarded thread", "confidence": 0.9],
            ["sample_id": "b", "recommended_action": "remove",
             "reason": "duplicate of a", "confidence": 0.9],
        ])
        let corpus = try writeCorpusFixture(in: tmp, rows: [
            (id: "a", text: "anything"),
            (id: "b", text: "anything"),
        ])
        let review = try XCTUnwrap(
            CurationReviewModel.loadFromReport(reportPath: report, corpusPath: corpus)
        )
        XCTAssertEqual(review.pendingRemovalCount, 2)
        review.setAcceptance(false, forCategory: "Forwarded thread")
        XCTAssertEqual(review.pendingRemovalCount, 1)
        review.setAcceptance(true, forCategory: "Forwarded thread")
        XCTAssertEqual(review.pendingRemovalCount, 2)
    }

    // MARK: - 3. Per-sample toggle flips one row at a time

    func test_toggleAcceptance_flips_single_decision() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let report = try writeReportFixture(in: tmp, decisions: [
            ["sample_id": "a", "recommended_action": "remove",
             "reason": "forwarded thread", "confidence": 0.9],
            ["sample_id": "b", "recommended_action": "remove",
             "reason": "forwarded thread", "confidence": 0.9],
        ])
        let corpus = try writeCorpusFixture(in: tmp, rows: [
            (id: "a", text: "anything"),
            (id: "b", text: "anything"),
        ])
        let review = try XCTUnwrap(
            CurationReviewModel.loadFromReport(reportPath: report, corpusPath: corpus)
        )
        let firstID = review.decisions[0].id
        XCTAssertEqual(review.pendingRemovalCount, 2)
        review.toggleAcceptance(decisionID: firstID)
        XCTAssertEqual(review.pendingRemovalCount, 1)
    }
}

@MainActor
final class DeepCurationModelApplyTests: XCTestCase {

    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kiln-deepcurate-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeCorpus(in tmp: URL, rows: [(id: String, text: String)]) throws -> URL {
        let url = tmp.appendingPathComponent("corpus.jsonl")
        let lines = rows.map { row -> String in
            let obj: [String: Any] = ["request_id": row.id, "text": row.text]
            let data = try! JSONSerialization.data(withJSONObject: obj)
            return String(data: data, encoding: .utf8) ?? ""
        }
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Stub runner that emits one completion event with a pre-baked report,
    /// without touching the real subprocess.
    private struct StubRunner: DeepCurationRunner {
        let reportPath: String
        let curatedPath: String
        func runStreaming(
            request: DeepCurationRequest,
            apiKey: String?
        ) -> AsyncThrowingStream<DeepCurationEvent, Error> {
            AsyncThrowingStream { continuation in
                continuation.yield(.thinking(content: "stub thinking"))
                continuation.yield(.completion(
                    samplesKept: 1,
                    samplesRemoved: 1,
                    samplesFlagged: 0,
                    reportPath: reportPath,
                    curatedPath: curatedPath
                ))
                continuation.finish()
            }
        }
    }

    // MARK: - 4. End-to-end apply rewrites the corpus and writes a history file

    func test_applyUserDecisions_filters_corpus_and_writes_history() async throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let corpus = try writeCorpus(in: tmp, rows: [
            (id: "remove-me", text: "From: bot\nSubject: ad"),
            (id: "keep-me", text: "I went for a walk this morning."),
        ])
        // Emit the report with one removal recommendation.
        let reportURL = tmp.appendingPathComponent("report.json")
        let reportPayload: [String: Any] = [
            "component": "corpus-curator",
            "decisions": [
                ["sample_id": "remove-me", "recommended_action": "remove",
                 "reason": "forwarded thread artifact", "confidence": 0.95],
                ["sample_id": "keep-me", "recommended_action": "keep",
                 "reason": "voice-bearing", "confidence": 0.95],
            ],
            "summary": ["keep": 1, "remove": 1, "flag": 0],
        ]
        let data = try JSONSerialization.data(withJSONObject: reportPayload)
        try data.write(to: reportURL)
        let curatedURL = tmp.appendingPathComponent("curated.jsonl")
        try Data().write(to: curatedURL)

        let historyDir = tmp.appendingPathComponent("history")
        let request = DeepCurationRequest(
            corpusPath: corpus,
            outputPath: tmp.appendingPathComponent("curated.jsonl"),
            reportPath: reportURL,
            dryRun: true
        )
        let model = DeepCurationModel(
            runner: StubRunner(reportPath: reportURL.path, curatedPath: curatedURL.path),
            request: request,
            apiKey: nil,
            historyDir: historyDir
        )
        await model.start()
        XCTAssertNotNil(model.review)
        XCTAssertEqual(model.review?.pendingRemovalCount, 1)
        model.applyUserDecisions()

        if case .applied(let removed, _) = model.status {
            XCTAssertEqual(removed, 1)
        } else {
            return XCTFail("expected .applied, got \(model.status)")
        }

        // The corpus now has only the kept row.
        let after = try String(contentsOf: corpus, encoding: .utf8)
        XCTAssertTrue(after.contains("keep-me"))
        XCTAssertFalse(after.contains("remove-me"))

        // History file written.
        let historyFiles = try FileManager.default.contentsOfDirectory(atPath: historyDir.path)
        XCTAssertEqual(historyFiles.count, 1)
        let historyURL = historyDir.appendingPathComponent(historyFiles[0])
        let historyData = try Data(contentsOf: historyURL)
        let history = try XCTUnwrap(
            JSONSerialization.jsonObject(with: historyData) as? [String: Any]
        )
        let removedIDs = try XCTUnwrap(history["removed_sample_ids"] as? [String])
        XCTAssertEqual(removedIDs, ["remove-me"])
    }

    // MARK: - 5. Apply with no acceptances is a safe no-op on the corpus

    func test_applyUserDecisions_with_no_pending_removals_leaves_corpus_alone() async throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let corpus = try writeCorpus(in: tmp, rows: [
            (id: "a", text: "I went for a walk."),
            (id: "b", text: "Coffee at six."),
        ])
        let reportURL = tmp.appendingPathComponent("report.json")
        // Two keeps, no removes.
        let reportPayload: [String: Any] = [
            "component": "corpus-curator",
            "decisions": [
                ["sample_id": "a", "recommended_action": "keep",
                 "reason": "voice-bearing", "confidence": 0.9],
                ["sample_id": "b", "recommended_action": "keep",
                 "reason": "voice-bearing", "confidence": 0.9],
            ],
            "summary": ["keep": 2, "remove": 0, "flag": 0],
        ]
        try JSONSerialization.data(withJSONObject: reportPayload).write(to: reportURL)
        let curatedURL = tmp.appendingPathComponent("curated.jsonl")
        try Data().write(to: curatedURL)
        let historyDir = tmp.appendingPathComponent("history")
        let request = DeepCurationRequest(
            corpusPath: corpus, outputPath: curatedURL, reportPath: reportURL, dryRun: true
        )
        let model = DeepCurationModel(
            runner: StubRunner(reportPath: reportURL.path, curatedPath: curatedURL.path),
            request: request, apiKey: nil, historyDir: historyDir
        )
        await model.start()
        XCTAssertEqual(model.review?.pendingRemovalCount, 0)
        let beforeText = try String(contentsOf: corpus, encoding: .utf8)
        model.applyUserDecisions()
        let afterText = try String(contentsOf: corpus, encoding: .utf8)
        XCTAssertEqual(beforeText, afterText)
    }
}
