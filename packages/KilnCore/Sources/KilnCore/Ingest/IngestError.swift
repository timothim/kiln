import Foundation

public enum IngestError: Error, LocalizedError, Equatable {
    case directoryNotFound(URL)
    case outputDirectoryNotWritable(URL)
    case parserFailed(path: URL, message: String)
    case noExamplesGenerated

    public var errorDescription: String? {
        switch self {
        case .directoryNotFound(let url):
            return "Directory not found: \(url.path)"
        case .outputDirectoryNotWritable(let url):
            return "Output directory is not writable: \(url.path)"
        case .parserFailed(let path, let message):
            return "Parser failed for \(path.lastPathComponent): \(message)"
        case .noExamplesGenerated:
            return "No training examples were generated from the corpus."
        }
    }
}
