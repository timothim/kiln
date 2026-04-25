import Foundation

/// Resolves the on-disk path of the shared fixture corpus relative to this source file.
/// Uses `#filePath` so tests work regardless of how SwiftPM stages resources.
enum TestFixtures {
    static let sampleCorpusURL: URL = {
        let thisFile = URL(fileURLWithPath: #filePath)
        // .../packages/KilnCore/Tests/KilnCoreTests/Support/TestFixtures.swift
        // → repo root is 5 levels up from this file's parent directory.
        let repoRoot = thisFile
            .deletingLastPathComponent()          // Support/
            .deletingLastPathComponent()          // KilnCoreTests/
            .deletingLastPathComponent()          // Tests/
            .deletingLastPathComponent()          // KilnCore/
            .deletingLastPathComponent()          // packages/
            .deletingLastPathComponent()          // repo root
        return repoRoot
            .appendingPathComponent("tests")
            .appendingPathComponent("fixtures")
            .appendingPathComponent("sample_corpus")
    }()

    static func fixture(_ name: String) -> URL {
        sampleCorpusURL.appendingPathComponent(name)
    }

    /// Path to the demo corpus used in the recorded video walkthrough.
    /// 223 files spanning notes/journal/emails/chat/code, hand-curated
    /// to look like a believable single-user folder. Phase 3 of the
    /// Saturday autonomous session uses this to assert the full ingest
    /// pipeline produces a non-trivial report end-to-end.
    static let demoCorpusURL: URL = {
        let thisFile = URL(fileURLWithPath: #filePath)
        let repoRoot = thisFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return repoRoot
            .appendingPathComponent("tests")
            .appendingPathComponent("fixtures")
            .appendingPathComponent("demo_corpus")
    }()

    static func makeTempDir(prefix: String = "kiln-test") throws -> URL {
        let base = FileManager.default.temporaryDirectory
        let unique = "\(prefix)-\(UUID().uuidString)"
        let url = base.appendingPathComponent(unique, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
