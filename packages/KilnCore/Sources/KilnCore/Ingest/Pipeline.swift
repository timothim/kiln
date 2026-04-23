import Foundation
import OSLog

public struct IngestPipeline: Sendable {
    public let config: IngestConfig
    public let parsers: [CorpusParser]
    private let log = Logger(subsystem: "dev.kiln.core", category: "ingest")

    public init(
        config: IngestConfig = IngestConfig(),
        parsers: [CorpusParser] = ParserRegistry.defaultParsers
    ) {
        self.config = config
        self.parsers = parsers
    }

    public func run(
        sourceDirectory: URL,
        outputDirectory: URL
    ) async throws -> IngestReport {
        var finalReport = IngestReport()
        for try await event in runStreaming(sourceDirectory: sourceDirectory,
                                            outputDirectory: outputDirectory) {
            if case .completed(let r) = event { finalReport = r }
        }
        return finalReport
    }

    public func runStreaming(
        sourceDirectory: URL,
        outputDirectory: URL,
        sampleEvery: Int = 50
    ) -> AsyncThrowingStream<IngestEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.execute(
                        sourceDirectory: sourceDirectory,
                        outputDirectory: outputDirectory,
                        sampleEvery: sampleEvery,
                        continuation: continuation
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func execute(
        sourceDirectory: URL,
        outputDirectory: URL,
        sampleEvery: Int,
        continuation: AsyncThrowingStream<IngestEvent, Error>.Continuation
    ) async throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: sourceDirectory.path, isDirectory: &isDir), isDir.boolValue else {
            throw IngestError.directoryNotFound(sourceDirectory)
        }
        try fm.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        try Self.verifyWritable(outputDirectory)

        var report = IngestReport()
        var counts = RunningCounts()
        var keptSinceLastSample = 0

        // Discovery
        continuation.yield(.stageStarted(.discovery))
        let discovered = try FileDiscovery.walk(
            sourceDirectory,
            excludedDirNames: config.excludedDirNames,
            maxFileBytes: config.maxFileBytes
        )
        report.filesDiscovered = discovered.count
        counts.filesDiscovered = discovered.count
        continuation.yield(.runningCounts(counts))
        continuation.yield(.stageFinished(.discovery))

        // Parsing
        continuation.yield(.stageStarted(.parsing))
        let registry = ParserRegistry(parsers: parsers)
        var chunks: [Chunk] = []
        var lastProgressEmit = Date(timeIntervalSince1970: 0)
        for (idx, file) in discovered.enumerated() {
            try Task.checkCancellation()
            guard let parser = registry.parser(for: file.url) else {
                report.filesSkipped.append(SkippedFile(path: file.url.path, reason: .unsupportedExtension))
                counts.filesSkipped += 1
                continue
            }
            do {
                let produced = try parser.parse(url: file.url, config: config)
                if produced.isEmpty {
                    report.filesSkipped.append(SkippedFile(path: file.url.path, reason: .emptyAfterParse))
                    counts.filesSkipped += 1
                    continue
                }
                report.filesParsed += 1
                counts.filesParsed += 1
                chunks.append(contentsOf: produced)
            } catch {
                log.error("parse failed for \(file.url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                report.filesSkipped.append(SkippedFile(path: file.url.path, reason: .parserFailure))
                counts.filesSkipped += 1
            }

            let shouldEmit = (idx + 1) % 10 == 0
                || Date().timeIntervalSince(lastProgressEmit) >= 0.25
                || idx == discovered.count - 1
            if shouldEmit {
                continuation.yield(.progress(IngestProgress(stage: .parsing, done: idx + 1, total: discovered.count)))
                continuation.yield(.runningCounts(counts))
                lastProgressEmit = Date()
            }
        }
        report.chunksBeforeDedup = chunks.count
        counts.chunksBeforeDedup = chunks.count
        continuation.yield(.runningCounts(counts))
        continuation.yield(.stageFinished(.parsing))

        // Dedup — two sub-stages share a single monotonic denominator
        // (chunks.count * 2) so the progress fraction never steps backward
        // at the exact-dedup / MinHash boundary.
        continuation.yield(.stageStarted(.dedup))
        let dedupTotal = chunks.count * 2
        var exact = ExactDedup()
        var afterExact: [Chunk] = []
        afterExact.reserveCapacity(chunks.count)
        for (idx, chunk) in chunks.enumerated() {
            if idx % 500 == 0 {
                try Task.checkCancellation()
                continuation.yield(.progress(IngestProgress(stage: .dedup, done: idx, total: dedupTotal)))
            }
            if exact.add(chunk.assistantText) {
                afterExact.append(chunk)
            }
        }
        report.chunksAfterExactDedup = afterExact.count
        counts.chunksAfterExactDedup = afterExact.count
        continuation.yield(.runningCounts(counts))

        var lsh = MinHashLSH(
            threshold: config.minHashThreshold,
            numHashes: config.minHashNumHashes,
            bands: config.minHashBands,
            shingleSize: config.shingleSize,
            seed: config.randomSeed
        )
        var afterNear: [Chunk] = []
        afterNear.reserveCapacity(afterExact.count)
        for (idx, chunk) in afterExact.enumerated() {
            if idx % 500 == 0 {
                try Task.checkCancellation()
                continuation.yield(.progress(IngestProgress(stage: .dedup, done: chunks.count + idx, total: dedupTotal)))
            }
            if lsh.add(chunk.assistantText) {
                afterNear.append(chunk)
            }
        }
        report.chunksAfterMinHashDedup = afterNear.count
        counts.chunksAfterMinHashDedup = afterNear.count
        continuation.yield(.runningCounts(counts))
        continuation.yield(.stageFinished(.dedup))

        // Quality
        continuation.yield(.stageStarted(.quality))
        var kept: [Chunk] = []
        kept.reserveCapacity(afterNear.count)
        for (idx, chunk) in afterNear.enumerated() {
            try Task.checkCancellation()
            let (verdict, _) = QualityFilter.evaluate(chunk.assistantText, config: config)
            switch verdict {
            case .accepted:
                kept.append(chunk)
                keptSinceLastSample += 1
                if keptSinceLastSample >= sampleEvery {
                    continuation.yield(.sample(ChunkPreview.from(chunk)))
                    keptSinceLastSample = 0
                }
            case .softRejected(let reason):
                Self.recordRejection(reason, into: &report.qualityBreakdown.softRejected)
                Self.recordRejection(reason, into: &counts.softRejected)
                report.softRejectedCount += 1
            case .hardRejected(let reason):
                Self.recordRejection(reason, into: &report.qualityBreakdown.hardRejected)
                Self.recordRejection(reason, into: &counts.hardRejected)
                report.hardRejectedCount += 1
            }
            counts.chunksAfterQuality = kept.count

            if (idx + 1) % 500 == 0 || idx == afterNear.count - 1 {
                continuation.yield(.progress(IngestProgress(stage: .quality, done: idx + 1, total: afterNear.count)))
                continuation.yield(.runningCounts(counts))
            }
        }
        report.chunksAfterQuality = kept.count
        continuation.yield(.runningCounts(counts))
        continuation.yield(.stageFinished(.quality))

        if kept.isEmpty {
            throw IngestError.noExamplesGenerated
        }

        // Writing
        continuation.yield(.stageStarted(.writing))
        let examples = kept.map { ChatMLBuilder.build(chunk: $0, userName: config.userName) }
        let split = DatasetSplit.split(examples, evalFraction: config.evalFraction, seed: config.randomSeed)
        report.trainCount = split.train.count
        report.evalCount = split.eval.count

        let trainURL = outputDirectory.appendingPathComponent("train.jsonl")
        let evalURL = outputDirectory.appendingPathComponent("eval.jsonl")
        let reportURL = outputDirectory.appendingPathComponent("report.json")

        try JSONLWriter.write(split.train, to: trainURL)
        try JSONLWriter.write(split.eval, to: evalURL)

        report.outputPaths = OutputPaths(
            trainJSONL: trainURL.path,
            evalJSONL: evalURL.path,
            reportJSON: reportURL.path
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let reportData = try encoder.encode(report)
        try reportData.write(to: reportURL)

        continuation.yield(.stageFinished(.writing))
        continuation.yield(.completed(report))
    }

    private static func verifyWritable(_ dir: URL) throws {
        let probe = dir.appendingPathComponent(".kiln-writable-probe-\(UUID().uuidString)")
        do {
            try Data().write(to: probe)
            try FileManager.default.removeItem(at: probe)
        } catch {
            throw IngestError.outputDirectoryNotWritable(dir)
        }
    }

    private static func recordRejection(_ reason: SkipReason, into counts: inout QualityRejectionCounts) {
        switch reason {
        case .tooShort:
            counts.tooShort += 1
        case .wrongLanguage:
            counts.wrongLanguage += 1
        case .tooRepetitive:
            counts.tooRepetitive += 1
        case .tooMuchNonASCII:
            counts.tooMuchNonASCII += 1
        case .unsupportedExtension, .tooLarge, .unreadable, .parserFailure,
             .emptyAfterParse, .exactDuplicate, .nearDuplicate:
            break
        }
    }
}
