import Foundation

public enum ChunkKind: String, Codable, Sendable, Hashable {
    case text
    case chat
    case code
}

public struct Chunk: Hashable, Sendable {
    public let sourcePath: String
    public let kind: ChunkKind
    public let userPrompt: String
    public let assistantText: String

    public init(sourcePath: String, kind: ChunkKind, userPrompt: String, assistantText: String) {
        self.sourcePath = sourcePath
        self.kind = kind
        self.userPrompt = userPrompt
        self.assistantText = assistantText
    }
}

public struct ChatMLMessage: Codable, Sendable, Hashable {
    public let role: String
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

public struct ChatMLExample: Sendable, Hashable {
    public let messages: [ChatMLMessage]
    public let sourcePath: String

    public init(messages: [ChatMLMessage], sourcePath: String) {
        self.messages = messages
        self.sourcePath = sourcePath
    }
}

extension ChatMLExample: Codable {
    private enum CodingKeys: String, CodingKey { case messages }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.messages = try c.decode([ChatMLMessage].self, forKey: .messages)
        self.sourcePath = ""
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(messages, forKey: .messages)
    }
}

public enum SkipReason: String, Codable, Sendable, Hashable {
    case unsupportedExtension
    case tooLarge
    case unreadable
    case parserFailure
    case emptyAfterParse
    case tooShort
    case wrongLanguage
    case tooRepetitive
    case tooMuchNonASCII
    case exactDuplicate
    case nearDuplicate
}

public struct SkippedFile: Codable, Sendable, Hashable {
    public let path: String
    public let reason: SkipReason

    public init(path: String, reason: SkipReason) {
        self.path = path
        self.reason = reason
    }
}

public struct QualityRejectionCounts: Codable, Sendable, Hashable {
    public var tooShort: Int = 0
    public var wrongLanguage: Int = 0
    public var tooRepetitive: Int = 0
    public var tooMuchNonASCII: Int = 0

    public init() {}

    public var total: Int { tooShort + wrongLanguage + tooRepetitive + tooMuchNonASCII }
}

public struct QualityBreakdown: Codable, Sendable, Hashable {
    public var softRejected: QualityRejectionCounts = QualityRejectionCounts()
    public var hardRejected: QualityRejectionCounts = QualityRejectionCounts()

    public init() {}
}

public struct OutputPaths: Codable, Sendable, Hashable {
    public let trainJSONL: String
    public let evalJSONL: String
    public let reportJSON: String

    public init(trainJSONL: String, evalJSONL: String, reportJSON: String) {
        self.trainJSONL = trainJSONL
        self.evalJSONL = evalJSONL
        self.reportJSON = reportJSON
    }
}

public struct IngestReport: Codable, Sendable, Hashable {
    public var filesDiscovered: Int = 0
    public var filesParsed: Int = 0
    public var filesSkipped: [SkippedFile] = []
    public var chunksBeforeDedup: Int = 0
    public var chunksAfterExactDedup: Int = 0
    public var chunksAfterMinHashDedup: Int = 0
    public var chunksAfterQuality: Int = 0
    /// Count after the M9.C distilled-classifier quality gate fires.
    /// When the classifier isn't available (no artifact present, runner
    /// not configured), this equals ``chunksAfterQuality`` — the gate
    /// is additive and degrades gracefully to a no-op.
    public var chunksAfterClassifierQuality: Int = 0
    /// Per-bucket counts produced by the M9.C classifier on the chunks
    /// that survived the rule-based quality stage. ``keep`` flows on,
    /// ``chosen_only`` is held back for DPO chosen-only feedstock,
    /// ``discard`` is dropped before training. All zero when the gate
    /// degrades to no-op.
    public var classifierBuckets: ClassifierBucketCounts = ClassifierBucketCounts()
    public var qualityBreakdown: QualityBreakdown = QualityBreakdown()
    public var softRejectedCount: Int = 0
    public var hardRejectedCount: Int = 0
    public var trainCount: Int = 0
    public var evalCount: Int = 0
    public var outputPaths: OutputPaths?

    public init() {}
}

public struct ClassifierBucketCounts: Codable, Sendable, Hashable {
    public var keep: Int = 0
    public var chosenOnly: Int = 0
    public var discard: Int = 0

    public init(keep: Int = 0, chosenOnly: Int = 0, discard: Int = 0) {
        self.keep = keep
        self.chosenOnly = chosenOnly
        self.discard = discard
    }

    /// Total scored. When zero the classifier didn't run (gate
    /// degraded to no-op).
    public var total: Int { keep + chosenOnly + discard }
}

public enum IngestStage: String, Codable, Sendable, Hashable, CaseIterable {
    case discovery
    case parsing
    case dedup
    case quality
    case writing
}

public struct IngestProgress: Sendable, Hashable {
    public let stage: IngestStage
    public let done: Int
    public let total: Int

    public init(stage: IngestStage, done: Int, total: Int) {
        self.stage = stage
        self.done = done
        self.total = total
    }

    public var fraction: Double {
        total > 0 ? min(1.0, Double(done) / Double(total)) : 0
    }
}

public struct ChunkPreview: Sendable, Hashable, Identifiable {
    public let id: UUID
    public let sourcePath: String
    public let kind: ChunkKind
    public let assistantSnippet: String
    public let userPromptSnippet: String

    /// Combined hard cap of 200 chars (ellipsis inclusive): 120 for the
    /// assistant snippet, 80 for the user prompt. Enforced at construction.
    public init(
        id: UUID = UUID(),
        sourcePath: String,
        kind: ChunkKind,
        assistantSnippet: String,
        userPromptSnippet: String
    ) {
        self.id = id
        self.sourcePath = sourcePath
        self.kind = kind
        self.assistantSnippet = Self.snippet(assistantSnippet, limit: 120)
        self.userPromptSnippet = Self.snippet(userPromptSnippet, limit: 80)
    }

    public static func from(_ chunk: Chunk) -> ChunkPreview {
        ChunkPreview(
            sourcePath: chunk.sourcePath,
            kind: chunk.kind,
            assistantSnippet: chunk.assistantText,
            userPromptSnippet: chunk.userPrompt
        )
    }

    private static func snippet(_ s: String, limit: Int) -> String {
        let collapsed = s
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        if collapsed.count <= limit { return collapsed }
        let end = collapsed.index(collapsed.startIndex, offsetBy: limit - 1)
        return String(collapsed[..<end]) + "…"
    }
}

public struct RunningCounts: Sendable, Hashable {
    public var filesDiscovered: Int = 0
    public var filesParsed: Int = 0
    public var filesSkipped: Int = 0
    public var chunksBeforeDedup: Int = 0
    public var chunksAfterExactDedup: Int = 0
    public var chunksAfterMinHashDedup: Int = 0
    public var chunksAfterQuality: Int = 0
    public var softRejected: QualityRejectionCounts = QualityRejectionCounts()
    public var hardRejected: QualityRejectionCounts = QualityRejectionCounts()

    public init() {}
}

public enum IngestEvent: Sendable {
    case stageStarted(IngestStage)
    case progress(IngestProgress)
    case sample(ChunkPreview)
    case runningCounts(RunningCounts)
    case stageFinished(IngestStage)
    case completed(IngestReport)
}

public struct IngestConfig: Sendable {
    public var userName: String
    public var minChunkChars: Int
    public var maxChunkChars: Int
    public var maxFileBytes: Int
    public var minHashThreshold: Double
    public var minHashNumHashes: Int
    public var minHashBands: Int
    public var shingleSize: Int
    public var maxNonASCIIRatio: Double
    public var maxRepetitionRatio: Double
    public var allowedLanguages: Set<String>
    public var iMessageMaxAgeDays: Int
    public var stripFrontmatter: Bool
    public var randomSeed: UInt64
    public var evalFraction: Double
    public var excludedDirNames: Set<String>
    public var supportedTextExtensions: Set<String>
    public var supportedJSONExtensions: Set<String>
    public var supportedCodeExtensions: Set<String>
    public var supportedEmailExtensions: Set<String>
    public var userEmails: Set<String>

    public init(
        userName: String = "User",
        minChunkChars: Int = 40,
        maxChunkChars: Int = 8_000,
        maxFileBytes: Int = 10_000_000,
        minHashThreshold: Double = 0.85,
        minHashNumHashes: Int = 128,
        minHashBands: Int = 32,
        shingleSize: Int = 8,
        maxNonASCIIRatio: Double = 0.30,
        maxRepetitionRatio: Double = 0.85,
        allowedLanguages: Set<String> = ["en"],
        iMessageMaxAgeDays: Int = 180,
        stripFrontmatter: Bool = true,
        randomSeed: UInt64 = 0xC0FFEE,
        evalFraction: Double = 0.10,
        excludedDirNames: Set<String> = [
            ".git", ".build", ".venv", "__pycache__",
            "node_modules", "DerivedData", ".swiftpm", ".idea", ".vscode"
        ],
        supportedTextExtensions: Set<String> = ["md", "markdown", "txt"],
        supportedJSONExtensions: Set<String> = ["json"],
        supportedCodeExtensions: Set<String> = ["py", "swift", "ts", "js", "rs", "go"],
        supportedEmailExtensions: Set<String> = ["eml", "mbox"],
        userEmails: Set<String> = []
    ) {
        self.userName = userName
        self.minChunkChars = minChunkChars
        self.maxChunkChars = maxChunkChars
        self.maxFileBytes = maxFileBytes
        self.minHashThreshold = minHashThreshold
        self.minHashNumHashes = minHashNumHashes
        self.minHashBands = minHashBands
        self.shingleSize = shingleSize
        self.maxNonASCIIRatio = maxNonASCIIRatio
        self.maxRepetitionRatio = maxRepetitionRatio
        self.allowedLanguages = allowedLanguages
        self.iMessageMaxAgeDays = iMessageMaxAgeDays
        self.stripFrontmatter = stripFrontmatter
        self.randomSeed = randomSeed
        self.evalFraction = evalFraction
        self.excludedDirNames = excludedDirNames
        self.supportedTextExtensions = supportedTextExtensions
        self.supportedJSONExtensions = supportedJSONExtensions
        self.supportedCodeExtensions = supportedCodeExtensions
        self.supportedEmailExtensions = supportedEmailExtensions
        self.userEmails = userEmails
    }
}
