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
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: sourceDirectory.path, isDirectory: &isDir), isDir.boolValue else {
            throw IngestError.directoryNotFound(sourceDirectory)
        }
        try fm.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        try Self.verifyWritable(outputDirectory)

        var report = IngestReport()

        let discovered = try FileDiscovery.walk(
            sourceDirectory,
            excludedDirNames: config.excludedDirNames,
            maxFileBytes: config.maxFileBytes
        )
        report.filesDiscovered = discovered.count

        let registry = ParserRegistry(parsers: parsers)
        var chunks: [Chunk] = []
        for file in discovered {
            guard let parser = registry.parser(for: file.url) else {
                report.filesSkipped.append(SkippedFile(path: file.url.path, reason: .unsupportedExtension))
                continue
            }
            do {
                let produced = try parser.parse(url: file.url, config: config)
                if produced.isEmpty {
                    report.filesSkipped.append(SkippedFile(path: file.url.path, reason: .emptyAfterParse))
                    continue
                }
                report.filesParsed += 1
                chunks.append(contentsOf: produced)
            } catch {
                log.error("parse failed for \(file.url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                report.filesSkipped.append(SkippedFile(path: file.url.path, reason: .parserFailure))
            }
        }
        report.chunksBeforeDedup = chunks.count

        var exact = ExactDedup()
        let afterExact = chunks.filter { exact.add($0.assistantText) }
        report.chunksAfterExactDedup = afterExact.count

        var lsh = MinHashLSH(
            threshold: config.minHashThreshold,
            numHashes: config.minHashNumHashes,
            bands: config.minHashBands,
            shingleSize: config.shingleSize,
            seed: config.randomSeed
        )
        let afterNear = afterExact.filter { lsh.add($0.assistantText) }
        report.chunksAfterMinHashDedup = afterNear.count

        var kept: [Chunk] = []
        kept.reserveCapacity(afterNear.count)
        for chunk in afterNear {
            let (verdict, _) = QualityFilter.evaluate(chunk.assistantText, config: config)
            switch verdict {
            case .accepted:
                kept.append(chunk)
            case .softRejected(let reason):
                Self.recordRejection(reason, into: &report.qualityBreakdown.softRejected)
                report.softRejectedCount += 1
            case .hardRejected(let reason):
                Self.recordRejection(reason, into: &report.qualityBreakdown.hardRejected)
                report.hardRejectedCount += 1
            }
        }
        report.chunksAfterQuality = kept.count

        if kept.isEmpty {
            throw IngestError.noExamplesGenerated
        }

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

        return report
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
