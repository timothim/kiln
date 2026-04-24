import XCTest
@testable import KilnCore

final class CloudBackupTests: XCTestCase {
    func testUploadIsDisabledByScope() async {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("voice.kiln")
        do {
            try await CloudBackup.upload(bundleAt: tmp, to: .iCloudDrive)
            XCTFail("Expected CloudBackup.BackupError.disabledByScope")
        } catch CloudBackup.BackupError.disabledByScope {
            // expected — CLAUDE.md forbids cloud sync until a DECISIONS entry opts in
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testListBackupsIsDisabledByScope() async {
        do {
            _ = try await CloudBackup.listBackups(.userProvidedS3)
            XCTFail("Expected CloudBackup.BackupError.disabledByScope")
        } catch CloudBackup.BackupError.disabledByScope {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testIsImplementedStaysFalseUntilDecisionEntry() {
        XCTAssertFalse(CloudBackup.isImplemented, "Flip only after a new DECISIONS.md entry defines custody and consent")
    }
}
