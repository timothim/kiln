import XCTest
@testable import KilnCore

final class VoiceInspectorTests: XCTestCase {
    func testAttributeThrowsNotImplemented() async {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        do {
            _ = try await VoiceInspector.attribute("hello world", against: tmp)
            XCTFail("Expected VoiceInspector.InspectorError.notImplemented")
        } catch VoiceInspector.InspectorError.notImplemented {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFutureAttributionSurfacesNearestChunks() throws {
        try XCTSkipIf(
            !VoiceInspector.isImplemented,
            "VoiceInspector depends on the style-extractor embedding shipping above bar"
        )
    }
}
