import XCTest
@testable import KilnCore

final class KilnCoreTests: XCTestCase {
    func testVersionMatchesPackageVersion() {
        XCTAssertEqual(KilnCore.version, "0.1.0")
    }
}
