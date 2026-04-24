import XCTest
@testable import KilnCore

final class VoiceMirrorTests: XCTestCase {
    func testReflectionThrowsNotImplemented() async {
        do {
            _ = try await VoiceMirror.reflect(prompt: "hello", adapterStep: 1)
            XCTFail("Expected VoiceMirror.MirrorError.notImplemented")
        } catch VoiceMirror.MirrorError.notImplemented {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFutureMirrorStreamsPerStep() throws {
        try XCTSkipIf(!VoiceMirror.isImplemented, "VoiceMirror lands with the M6 streaming pipe")
    }
}
