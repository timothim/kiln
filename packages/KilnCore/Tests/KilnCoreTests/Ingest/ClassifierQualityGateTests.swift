import XCTest
@testable import KilnCore

/// Tests for the M9.C ``ClassifierQualityGate`` (Phase 1.4 wiring).
final class ClassifierQualityGateTests: XCTestCase {

    /// Fake runner that returns canned bucket assignments.
    final class FakeRunner: QualityClassifierRunner, @unchecked Sendable {
        var bucketsByID: [String: QualityBucket] = [:]
        var error: Error? = nil
        var calls: Int = 0

        func classify(_ rows: [ClassifierInputRow]) async throws -> [QualityScore] {
            calls += 1
            if let error { throw error }
            return rows.map { row in
                let bucket = bucketsByID[row.requestID] ?? .keep
                let score: Double
                switch bucket {
                case .keep: score = 0.9
                case .chosenOnly: score = 0.5
                case .discard: score = 0.2
                }
                return QualityScore(requestID: row.requestID, score: score, bucket: bucket)
            }
        }
    }

    func test_gate_routes_into_three_buckets() async throws {
        let runner = FakeRunner()
        runner.bucketsByID = [
            "r1": .keep,
            "r2": .chosenOnly,
            "r3": .discard,
            "r4": .keep,
        ]
        let gate = ClassifierQualityGate(runner: runner)
        let routing = await gate.route([
            ClassifierInputRow(requestID: "r1", text: "voice"),
            ClassifierInputRow(requestID: "r2", text: "midline"),
            ClassifierInputRow(requestID: "r3", text: "boilerplate"),
            ClassifierInputRow(requestID: "r4", text: "voice"),
        ])
        XCTAssertEqual(routing.keep.map(\.requestID), ["r1", "r4"])
        XCTAssertEqual(routing.chosenOnly.map(\.requestID), ["r2"])
        XCTAssertEqual(routing.discard.map(\.requestID), ["r3"])
        XCTAssertEqual(routing.counts.keep, 2)
        XCTAssertEqual(routing.counts.chosenOnly, 1)
        XCTAssertEqual(routing.counts.discard, 1)
        XCTAssertEqual(routing.counts.total, 4)
    }

    func test_gate_returns_all_keep_when_runner_is_nil() async {
        let gate = ClassifierQualityGate(runner: nil)
        let chunks = [
            ClassifierInputRow(requestID: "a", text: "x"),
            ClassifierInputRow(requestID: "b", text: "y"),
        ]
        let routing = await gate.route(chunks)
        XCTAssertEqual(routing.keep.count, 2)
        XCTAssertEqual(routing.chosenOnly.count, 0)
        XCTAssertEqual(routing.discard.count, 0)
        // total == 0 signals "gate didn't run" to the UI.
        XCTAssertEqual(routing.counts.total, 0)
    }

    func test_gate_degrades_to_all_keep_on_runner_error() async throws {
        let runner = FakeRunner()
        runner.error = DistilledClassifierError.sidecarError(
            code: "subprocess_failed",
            message: "simulated"
        )
        let gate = ClassifierQualityGate(runner: runner)
        let chunks = [ClassifierInputRow(requestID: "a", text: "x")]
        let routing = await gate.route(chunks)
        XCTAssertEqual(routing.keep.count, 1)
        XCTAssertEqual(routing.counts.total, 0)  // no successful classification
    }

    func test_gate_falls_back_when_runner_returns_count_mismatch() async throws {
        // Runner that intentionally returns one fewer score than input.
        final class TruncatingRunner: QualityClassifierRunner, @unchecked Sendable {
            func classify(_ rows: [ClassifierInputRow]) async throws -> [QualityScore] {
                rows.dropLast().map {
                    QualityScore(requestID: $0.requestID, score: 0.9, bucket: .keep)
                }
            }
        }
        let gate = ClassifierQualityGate(runner: TruncatingRunner())
        let routing = await gate.route([
            ClassifierInputRow(requestID: "a", text: "x"),
            ClassifierInputRow(requestID: "b", text: "y"),
        ])
        XCTAssertEqual(routing.keep.count, 2)
        XCTAssertEqual(routing.counts.total, 0)
    }

    func test_ingest_report_classifier_buckets_total_zero_means_gate_skipped() {
        var report = IngestReport()
        report.chunksAfterQuality = 100
        report.chunksAfterClassifierQuality = 100
        // Default ClassifierBucketCounts has total 0.
        XCTAssertEqual(report.classifierBuckets.total, 0)
    }

    func test_ingest_report_round_trips_classifier_fields_via_codable() throws {
        var report = IngestReport()
        report.chunksAfterQuality = 100
        report.chunksAfterClassifierQuality = 80
        report.classifierBuckets = ClassifierBucketCounts(keep: 80, chosenOnly: 15, discard: 5)
        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(IngestReport.self, from: data)
        XCTAssertEqual(decoded.chunksAfterClassifierQuality, 80)
        XCTAssertEqual(decoded.classifierBuckets.keep, 80)
        XCTAssertEqual(decoded.classifierBuckets.chosenOnly, 15)
        XCTAssertEqual(decoded.classifierBuckets.discard, 5)
        XCTAssertEqual(decoded.classifierBuckets.total, 100)
    }
}
