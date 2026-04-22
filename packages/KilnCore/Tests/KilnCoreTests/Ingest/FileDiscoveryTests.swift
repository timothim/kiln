import XCTest
@testable import KilnCore

final class FileDiscoveryTests: XCTestCase {
    func testWalkFindsAllKnownFixtureTypes() throws {
        let cfg = IngestConfig()
        let files = try FileDiscovery.walk(
            TestFixtures.sampleCorpusURL,
            excludedDirNames: cfg.excludedDirNames,
            maxFileBytes: cfg.maxFileBytes
        )
        let exts = Set(files.map { $0.url.pathExtension.lowercased() })
        XCTAssertTrue(exts.contains("md"))
        XCTAssertTrue(exts.contains("json"))
        XCTAssertTrue(exts.contains("py"))
        XCTAssertTrue(exts.contains("swift"))
        XCTAssertTrue(exts.contains("ts"))
        XCTAssertGreaterThanOrEqual(files.count, 10)
    }

    func testWalkExcludesDotDirectoriesAndDotFiles() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let visible = tmp.appendingPathComponent("visible.md")
        let hiddenFile = tmp.appendingPathComponent(".hidden.md")
        let hiddenDir = tmp.appendingPathComponent(".git")
        let inHiddenDir = hiddenDir.appendingPathComponent("config")
        let excludedDir = tmp.appendingPathComponent("node_modules")
        let inExcludedDir = excludedDir.appendingPathComponent("dep.md")

        try FileManager.default.createDirectory(at: hiddenDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: excludedDir, withIntermediateDirectories: true)
        try "keep".write(to: visible, atomically: true, encoding: .utf8)
        try "drop".write(to: hiddenFile, atomically: true, encoding: .utf8)
        try "drop".write(to: inHiddenDir, atomically: true, encoding: .utf8)
        try "drop".write(to: inExcludedDir, atomically: true, encoding: .utf8)

        let files = try FileDiscovery.walk(
            tmp,
            excludedDirNames: ["node_modules"],
            maxFileBytes: 1_000_000
        )
        let names = files.map { $0.url.lastPathComponent }
        XCTAssertEqual(names, ["visible.md"])
    }

    func testWalkDoesNotFollowSymlinks() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let real = tmp.appendingPathComponent("real.md")
        try "content".write(to: real, atomically: true, encoding: .utf8)

        let linkToFile = tmp.appendingPathComponent("link.md")
        try FileManager.default.createSymbolicLink(at: linkToFile, withDestinationURL: real)

        let linkedDir = tmp.appendingPathComponent("linked_dir")
        let externalDir = tmp.appendingPathComponent("external")
        try FileManager.default.createDirectory(at: externalDir, withIntermediateDirectories: true)
        try "outside".write(
            to: externalDir.appendingPathComponent("outside.md"),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.createSymbolicLink(at: linkedDir, withDestinationURL: externalDir)

        let files = try FileDiscovery.walk(
            tmp,
            excludedDirNames: [],
            maxFileBytes: 1_000_000
        )
        let names = files.map { $0.url.lastPathComponent }
        XCTAssertTrue(names.contains("real.md"))
        XCTAssertTrue(names.contains("outside.md"))
        XCTAssertFalse(names.contains("link.md"))
    }

    func testWalkThrowsOnMissingDirectory() {
        let missing = URL(fileURLWithPath: "/tmp/kiln-does-not-exist-\(UUID().uuidString)")
        XCTAssertThrowsError(
            try FileDiscovery.walk(missing, excludedDirNames: [], maxFileBytes: 100)
        ) { error in
            guard case IngestError.directoryNotFound = error else {
                return XCTFail("expected directoryNotFound, got \(error)")
            }
        }
    }

    private func makeTempDir() throws -> URL {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("kiln-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
}
