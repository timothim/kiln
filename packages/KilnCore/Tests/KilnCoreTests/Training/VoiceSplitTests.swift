import XCTest
@testable import KilnCore

final class VoiceSplitTests: XCTestCase {

    // MARK: - VoiceSplit derivations

    func testSelectedPersonasFiltersByFlag() {
        let split = VoiceSplit(personas: [
            Persona(label: "drafts", sampleCount: 1_000, selected: true),
            Persona(label: "formal", sampleCount: 500, selected: false),
            Persona(label: "notes",  sampleCount: 200, selected: true)
        ])

        let selected = split.selectedPersonas
        XCTAssertEqual(selected.count, 2)
        XCTAssertEqual(Set(selected.map(\.label)), ["drafts", "notes"])
    }

    func testSelectedSampleCountSumsOnlySelected() {
        let split = VoiceSplit(personas: [
            Persona(label: "drafts", sampleCount: 1_000, selected: true),
            Persona(label: "formal", sampleCount: 500, selected: false),
            Persona(label: "notes",  sampleCount: 200, selected: true)
        ])

        XCTAssertEqual(split.selectedSampleCount, 1_200)
    }

    func testEmptyPersonasYieldsZeroSelectedSamples() {
        let split = VoiceSplit(personas: [])
        XCTAssertEqual(split.selectedPersonas, [])
        XCTAssertEqual(split.selectedSampleCount, 0)
    }

    // MARK: - Codable round-trip

    func testVoiceSplitCodableRoundTrip() throws {
        let original = VoiceSplit(personas: [
            Persona(label: "drafts", sampleCount: 1_240, selected: true),
            Persona(label: "formal", sampleCount: 860,   selected: false)
        ])

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(VoiceSplit.self, from: data)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.personas.map(\.id), original.personas.map(\.id))
    }

    func testPersonaDefaultsToSelectedTrue() {
        let p = Persona(label: "drafts", sampleCount: 1)
        XCTAssertTrue(p.selected, "new personas should opt-in by default so a first-run user doesn't have to check every box")
    }

    // MARK: - TrainingRequest threading

    func testTrainingRequestCarriesVoiceSplit() {
        let split = VoiceSplit(personas: [
            Persona(label: "drafts", sampleCount: 100, selected: true)
        ])
        let request = TrainingRequest(
            datasetURL: URL(fileURLWithPath: "/tmp/train.jsonl"),
            runDir: URL(fileURLWithPath: "/tmp/run"),
            voiceSplit: split
        )

        XCTAssertEqual(request.voiceSplit, split)
    }

    func testTrainingRequestDefaultsVoiceSplitToNil() {
        let request = TrainingRequest(
            datasetURL: URL(fileURLWithPath: "/tmp/train.jsonl"),
            runDir: URL(fileURLWithPath: "/tmp/run")
        )
        XCTAssertNil(request.voiceSplit, "requests without an explicit split must not synthesize one — the trainer reads this as 'no slicing'")
    }

    func testWithVoiceSplitReturnsCopyWithNewField() {
        let base = TrainingRequest(
            datasetURL: URL(fileURLWithPath: "/tmp/train.jsonl"),
            runDir: URL(fileURLWithPath: "/tmp/run")
        )
        let split = VoiceSplit(personas: [
            Persona(label: "drafts", sampleCount: 1, selected: true)
        ])

        let updated = base.withVoiceSplit(split)

        XCTAssertNil(base.voiceSplit, "withVoiceSplit must not mutate the source")
        XCTAssertEqual(updated.voiceSplit, split)
        XCTAssertEqual(updated.datasetURL, base.datasetURL)
        XCTAssertEqual(updated.runDir, base.runDir)
        XCTAssertEqual(updated.model, base.model)
    }

    func testWithVoiceSplitAcceptsNilToClear() {
        let split = VoiceSplit(personas: [
            Persona(label: "drafts", sampleCount: 1, selected: true)
        ])
        let seeded = TrainingRequest(
            datasetURL: URL(fileURLWithPath: "/tmp/train.jsonl"),
            runDir: URL(fileURLWithPath: "/tmp/run"),
            voiceSplit: split
        )

        let cleared = seeded.withVoiceSplit(nil)
        XCTAssertNil(cleared.voiceSplit)
    }
}
