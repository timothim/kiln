import Foundation
import KilnCore
import Observation
import SwiftUI

/// Drives the PrepareStageView. Owns the streaming ingest task, mirrors
/// pipeline events onto the MainActor with light throttling, and exposes
/// the whole thing as a simple state machine.
@Observable
@MainActor
final class PrepareModel {

    enum Status: Equatable {
        case idle
        case running
        case cancelling
        case completed(IngestReport)
        case failed(DisplayError)
    }

    enum DisplayError: Equatable {
        case cancelled
        case directoryNotFound
        case outputDirectoryNotWritable
        case parserFailed
        case noExamplesGenerated
        case other(String)

        var userFacingMessage: String {
            switch self {
            case .cancelled:
                return "You cancelled. Drop another folder when you are ready."
            case .directoryNotFound:
                return "That folder is not available. Make sure the drive is mounted and try again."
            case .outputDirectoryNotWritable:
                return "Kiln could not write to its scratch directory. Check disk permissions."
            case .parserFailed:
                return "Kiln could not read the contents of that folder."
            case .noExamplesGenerated:
                return "No usable content found. Try a folder with plain-text writing."
            case .other(let reason):
                return reason
            }
        }

        static func fromIngest(_ error: IngestError) -> DisplayError {
            switch error {
            case .directoryNotFound:
                return .directoryNotFound
            case .outputDirectoryNotWritable:
                return .outputDirectoryNotWritable
            case .parserFailed:
                return .parserFailed
            case .noExamplesGenerated:
                return .noExamplesGenerated
            }
        }
    }

    var status: Status = .idle
    var currentStage: IngestStage = .discovery
    var stageProgress: Double = 0
    var overallProgress: Double = 0
    var counts: RunningCounts = RunningCounts()
    var liveSamples: [ChunkPreview] = []

    private var task: Task<Void, Never>?
    private var lastPublishedAt: TimeInterval = 0
    private let publishIntervalSeconds: TimeInterval = 0.016
    private let pipeline: IngestPipeline

    private static let stageWeights: [IngestStage: Double] = [
        .discovery: 0.05,
        .parsing:   0.40,
        .dedup:     0.20,
        .quality:   0.25,
        .writing:   0.10
    ]

    init(pipeline: IngestPipeline = IngestPipeline()) {
        self.pipeline = pipeline
    }

    func start(folderURL: URL, outputDirectory: URL) {
        guard case .idle = status else { return }
        status = .running
        currentStage = .discovery
        stageProgress = 0
        overallProgress = 0
        counts = RunningCounts()
        liveSamples = []
        lastPublishedAt = 0

        let stream = pipeline.runStreaming(
            sourceDirectory: folderURL,
            outputDirectory: outputDirectory
        )
        task = Task { [weak self] in
            await self?.consume(stream: stream)
        }
    }

    func cancel() {
        guard case .running = status else { return }
        status = .cancelling
        task?.cancel()
    }

    func reset() {
        task?.cancel()
        task = nil
        status = .idle
        currentStage = .discovery
        stageProgress = 0
        overallProgress = 0
        counts = RunningCounts()
        liveSamples = []
    }

    /// Test seam — drives the model off an injected event stream.
    func testing_start(stream: AsyncThrowingStream<IngestEvent, Error>) {
        guard case .idle = status else { return }
        status = .running
        currentStage = .discovery
        stageProgress = 0
        overallProgress = 0
        counts = RunningCounts()
        liveSamples = []
        lastPublishedAt = 0
        task = Task { [weak self] in
            await self?.consume(stream: stream)
        }
    }

    private func consume(stream: AsyncThrowingStream<IngestEvent, Error>) async {
        do {
            for try await event in stream {
                apply(event)
            }
            if Task.isCancelled, case .cancelling = status {
                status = .failed(.cancelled)
            }
        } catch let error as IngestError {
            status = .failed(.fromIngest(error))
        } catch is CancellationError {
            status = .failed(.cancelled)
        } catch {
            status = .failed(.other(error.localizedDescription))
        }
    }

    private func apply(_ event: IngestEvent) {
        switch event {
        case .stageStarted(let stage):
            currentStage = stage
            stageProgress = 0
            recomputeOverall()
        case .progress(let p):
            let now = Date().timeIntervalSinceReferenceDate
            if now - lastPublishedAt >= publishIntervalSeconds || p.fraction >= 1.0 {
                stageProgress = p.fraction
                recomputeOverall()
                lastPublishedAt = now
            }
        case .sample(let preview):
            liveSamples.append(preview)
            if liveSamples.count > 3 {
                liveSamples.removeFirst(liveSamples.count - 3)
            }
        case .runningCounts(let c):
            let now = Date().timeIntervalSinceReferenceDate
            if now - lastPublishedAt >= publishIntervalSeconds {
                counts = c
                lastPublishedAt = now
            } else {
                counts = c
            }
        case .stageFinished(let stage):
            currentStage = stage
            stageProgress = 1.0
            recomputeOverall()
        case .completed(let report):
            status = .completed(report)
            stageProgress = 1.0
            overallProgress = 1.0
        }
    }

    private func recomputeOverall() {
        var finished: Double = 0
        for stage in IngestStage.allCases {
            let weight = Self.stageWeights[stage] ?? 0
            if stageOrder(stage) < stageOrder(currentStage) {
                finished += weight
            } else if stage == currentStage {
                finished += weight * min(1.0, max(0.0, stageProgress))
            }
        }
        overallProgress = min(1.0, finished)
    }

    private func stageOrder(_ stage: IngestStage) -> Int {
        switch stage {
        case .discovery: return 0
        case .parsing:   return 1
        case .dedup:     return 2
        case .quality:   return 3
        case .writing:   return 4
        }
    }
}

extension PrepareModel.Status {
    static func == (lhs: PrepareModel.Status, rhs: PrepareModel.Status) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.running, .running): return true
        case (.cancelling, .cancelling): return true
        case (.completed(let a), .completed(let b)): return a == b
        case (.failed(let a), .failed(let b)): return a == b
        default: return false
        }
    }
}
