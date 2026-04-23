import Foundation

public struct ParserRegistry: Sendable {
    public let parsers: [CorpusParser]

    public init(parsers: [CorpusParser] = ParserRegistry.defaultParsers) {
        self.parsers = parsers
    }

    public static let defaultParsers: [CorpusParser] = [
        IMessageParser(),
        OpenAIChatParser(),
        MarkdownTextParser(),
        CodeParser(),
        EmailParser()
    ]

    public func parser(for url: URL) -> CorpusParser? {
        let ext = url.pathExtension.lowercased()
        if ext == "json" {
            if let data = try? Data(contentsOf: url) {
                for parser in parsers {
                    if parser.canParse(url: url, probe: data) { return parser }
                }
            }
            return nil
        }
        for parser in parsers {
            if parser.canParse(url: url, probe: nil) { return parser }
        }
        return nil
    }
}
