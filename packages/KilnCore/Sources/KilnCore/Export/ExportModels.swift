import Foundation

/// Four export stages in wall-clock order. Matches the Python sidecar's
/// ``STAGES`` set values that ``export`` emits ``done(stage=...)`` for.
public enum ExportStage: String, Sendable, Hashable, Codable, CaseIterable {
    case fuse
    case gguf
    case modelfile   // emitted only as part of `done(stage="modelfile")` from Swift's POV; sidecar skips a `done` for it today
    case ollama
}

public struct ExportRequest: Sendable, Hashable {
    public let model: String
    public let adapterURL: URL
    public let runDir: URL
    public let userName: String
    public let outputName: String
    public let llamaCppDir: URL?
    public let quantization: String?
    public let skipGGUF: Bool
    public let skipOllama: Bool
    /// Hidden test seam — forwarded as ``--fuser-entry``.
    public let fuserEntry: String?
    /// Hidden test seam — forwarded as ``--ollama-bin``.
    public let ollamaBin: String?

    public init(
        model: String,
        adapterURL: URL,
        runDir: URL,
        userName: String,
        outputName: String,
        llamaCppDir: URL?,
        quantization: String? = nil,
        skipGGUF: Bool = false,
        skipOllama: Bool = false,
        fuserEntry: String? = nil,
        ollamaBin: String? = nil
    ) {
        self.model = model
        self.adapterURL = adapterURL
        self.runDir = runDir
        self.userName = userName
        self.outputName = outputName
        self.llamaCppDir = llamaCppDir
        self.quantization = quantization
        self.skipGGUF = skipGGUF
        self.skipOllama = skipOllama
        self.fuserEntry = fuserEntry
        self.ollamaBin = ollamaBin
    }
}

public enum ExportEvent: Sendable, Hashable {
    case ready(version: String, mlx: String)
    case stageDone(stage: ExportStage, artifact: String, interrupted: Bool)
    case stageFailed(stage: ExportStage, code: String, message: String, recoverable: Bool)
}

public enum ExportError: Error, Sendable, Equatable {
    case launchFailed(message: String)
    case unexpectedExit(code: Int32, stderrTail: String)
    case decodingFailed(line: String, underlying: String)
}
