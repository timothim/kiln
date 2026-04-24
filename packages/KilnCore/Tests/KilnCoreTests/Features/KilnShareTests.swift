import XCTest
@testable import KilnCore

final class KilnShareTests: XCTestCase {
    /// The legacy `export(voiceName:to:)` API stays on the type for callers
    /// that only have a voice name — it can't assemble a real manifest, so
    /// it deliberately throws `voiceNotFused` rather than succeeding with an
    /// empty bundle. Real exports go through `export(manifest:to:)`.
    func testLegacyExportByVoiceNameThrowsVoiceNotFused() async {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("out.kiln")
        do {
            _ = try await KilnShare.export(voiceName: "alex", to: tmp)
            XCTFail("Expected KilnShare.ShareError.voiceNotFused")
        } catch KilnShare.ShareError.voiceNotFused {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testImportStillThrowsNotImplemented() async {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("in.kiln")
        do {
            _ = try await KilnShare.import(bundleAt: tmp)
            XCTFail("Expected KilnShare.ShareError.notImplemented")
        } catch KilnShare.ShareError.notImplemented {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testIsImplementedFlipsOnceExporterLands() {
        // Sanity: once ShareExporter shipped, feature flags / preview paths
        // should see `isImplemented == true`.
        XCTAssertTrue(KilnShare.isImplemented)
    }
}
