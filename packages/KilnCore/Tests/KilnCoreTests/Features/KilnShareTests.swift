import XCTest
@testable import KilnCore

final class KilnShareTests: XCTestCase {
    func testExportThrowsNotImplemented() async {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("out.kiln")
        do {
            _ = try await KilnShare.export(voiceName: "alex", to: tmp)
            XCTFail("Expected KilnShare.ShareError.notImplemented")
        } catch KilnShare.ShareError.notImplemented {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testImportThrowsNotImplemented() async {
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

    func testFutureBundleIsZipWithManifest() throws {
        try XCTSkipIf(
            !KilnShare.isImplemented,
            "KilnShare bundle layout settles with the .kiln archive spec post-M6"
        )
    }
}
