import Foundation

public enum JSONLWriter {
    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    public static func write<T: Encodable>(
        _ items: [T],
        to url: URL,
        encoder: JSONEncoder? = nil
    ) throws {
        let enc = encoder ?? makeEncoder()
        let fm = FileManager.default
        let directory = url.deletingLastPathComponent()
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
        guard fm.createFile(atPath: url.path, contents: nil) else {
            throw JSONLWriterError.cannotCreate(url)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }

        for item in items {
            var data = try enc.encode(item)
            data.append(0x0A)
            try handle.write(contentsOf: data)
        }
    }
}

public enum JSONLWriterError: Error, Equatable {
    case cannotCreate(URL)
}
