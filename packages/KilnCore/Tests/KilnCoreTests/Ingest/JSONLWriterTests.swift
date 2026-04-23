import XCTest
@testable import KilnCore

final class JSONLWriterTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = try TestFixtures.makeTempDir(prefix: "kiln-jsonl")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testWritesOneObjectPerLineWithTrailingNewline() throws {
        let items = [
            ChatMLExample(
                messages: [ChatMLMessage(role: "user", content: "hi")],
                sourcePath: "a.md"
            ),
            ChatMLExample(
                messages: [ChatMLMessage(role: "user", content: "there")],
                sourcePath: "b.md"
            )
        ]
        let url = tempDir.appendingPathComponent("out.jsonl")
        try JSONLWriter.write(items, to: url)

        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(text.hasSuffix("\n"))
        XCTAssertEqual(lines[2], "")
    }

    func testRoundTripDecodesEachLine() throws {
        let items = (0..<5).map { i in
            ChatMLExample(
                messages: [ChatMLMessage(role: "user", content: "msg-\(i)")],
                sourcePath: "f\(i).md"
            )
        }
        let url = tempDir.appendingPathComponent("rt.jsonl")
        try JSONLWriter.write(items, to: url)

        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 5)

        let decoder = JSONDecoder()
        for (i, line) in lines.enumerated() {
            let data = try XCTUnwrap(line.data(using: .utf8))
            let decoded = try decoder.decode(ChatMLExample.self, from: data)
            XCTAssertEqual(decoded.messages.count, 1)
            XCTAssertEqual(decoded.messages[0].content, "msg-\(i)")
        }
    }

    func testEmptyArrayProducesEmptyFile() throws {
        let url = tempDir.appendingPathComponent("empty.jsonl")
        try JSONLWriter.write([ChatMLExample](), to: url)
        let data = try Data(contentsOf: url)
        XCTAssertTrue(data.isEmpty)
    }

    func testOverwritesExistingFile() throws {
        let url = tempDir.appendingPathComponent("over.jsonl")
        try "old content\n".data(using: .utf8)?.write(to: url)
        let items = [
            ChatMLExample(
                messages: [ChatMLMessage(role: "user", content: "fresh")],
                sourcePath: "x.md"
            )
        ]
        try JSONLWriter.write(items, to: url)
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(text.contains("old content"))
        XCTAssertTrue(text.contains("fresh"))
    }

    func testCreatesIntermediateDirectories() throws {
        let url = tempDir.appendingPathComponent("a/b/c/out.jsonl")
        try JSONLWriter.write(
            [ChatMLExample(messages: [ChatMLMessage(role: "user", content: "hi")], sourcePath: "a")],
            to: url
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
}
