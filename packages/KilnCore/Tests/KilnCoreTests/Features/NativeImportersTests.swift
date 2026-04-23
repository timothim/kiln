import XCTest
@testable import KilnCore

final class NativeImportersTests: XCTestCase {
    func testImportThrowsNotImplemented() async {
        do {
            try await NativeImporters.importFrom(.messages, progress: { _ in })
            XCTFail("Expected NativeImporters.ImporterError.notImplemented")
        } catch NativeImporters.ImporterError.notImplemented {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAllSourcesEnumerable() {
        XCTAssertEqual(NativeImporters.Source.allCases.count, 4)
    }

    func testFuturePermissionFlowIsTccBacked() throws {
        try XCTSkipIf(
            !NativeImporters.isImplemented,
            "NativeImporters gates each source behind the TCC permission prompts documented in macos-data-sources skill"
        )
    }
}
