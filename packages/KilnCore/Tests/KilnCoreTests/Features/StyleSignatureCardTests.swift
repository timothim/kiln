import XCTest
@testable import KilnCore

final class StyleSignatureCardTests: XCTestCase {
    func testGenerateThrowsNotImplemented() async {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        do {
            _ = try await StyleSignatureCard.generate(forCorpus: tmp)
            XCTFail("Expected StyleSignatureCard.SignatureError.notImplemented")
        } catch StyleSignatureCard.SignatureError.notImplemented {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFutureSignatureHonoursBar() throws {
        try XCTSkipIf(
            !StyleSignatureCard.isImplemented,
            "StyleSignatureCard requires the style-extractor artifact above cosine ≥ 0.75"
        )
    }
}
