import Foundation

public protocol CorpusParser: Sendable {
    func canParse(url: URL, probe: Data?) -> Bool
    func parse(url: URL, config: IngestConfig) throws -> [Chunk]
}

enum ParserUtilities {
    static func readString(_ url: URL) throws -> String {
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            if let data = try? Data(contentsOf: url),
               let s = String(data: data, encoding: .utf8) {
                return s
            }
            throw IngestError.parserFailed(path: url, message: "unable to read as UTF-8")
        }
    }
}
