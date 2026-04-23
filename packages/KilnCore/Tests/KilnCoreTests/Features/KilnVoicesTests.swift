import XCTest
@testable import KilnCore

final class KilnVoicesTests: XCTestCase {
    func testListThrowsNotImplemented() async {
        do {
            _ = try await KilnVoices.list()
            XCTFail("Expected KilnVoices.VoicesError.notImplemented")
        } catch KilnVoices.VoicesError.notImplemented {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testVoiceHasStableIdentity() {
        let uuid = UUID()
        let voice = KilnVoices.Voice(id: uuid, name: "alex", ollamaTag: "kiln/alex:1", createdAt: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(voice.id, uuid)
    }

    func testFutureActivationSwitchesModelfile() throws {
        try XCTSkipIf(!KilnVoices.isImplemented, "KilnVoices lands post-M6 once fuse-export is stable")
    }
}
