import Foundation
import KilnCore
import Observation
import SwiftUI

/// Drives the TrainStageView. Mirrors PrepareModel's state-machine shape so
/// the two stages read identically from outside: `@Observable @MainActor`,
/// injected stream for tests, typed `Status`, cancel → cancelling → terminal.
@Observable
@MainActor
final class TrainModel {

    enum Status: Equatable {
        case idle
        case running
        case cancelling(lastIter: Int?)
        case completed(TrainingReport)
        case failed(DisplayError)
    }

    enum DisplayError: Equatable {
        case cancelled
        case outOfMemory(String)
        case dataInvalid(String)
        case modelNotFound(String)
        case subprocessFailed(String)
        case interrupted(String)
        case launchFailed(String)
        case decodingFailed(String)
        case other(String)

        var userFacingMessage: String {
            switch self {
            case .cancelled:
                return "You stopped training. Your adapter up to the last checkpoint was saved."
            case .outOfMemory(let hint):
                return "Ran out of memory. \(hint)"
            case .dataInvalid(let msg):
                return "That dataset could not be used. \(msg)"
            case .modelNotFound(let msg):
                return "Could not find the base model. \(msg)"
            case .subprocessFailed(let msg):
                return "The trainer stopped unexpectedly. \(msg)"
            case .interrupted(let msg):
                return "Training was interrupted. \(msg)"
            case .launchFailed(let msg):
                return "Could not start the trainer. \(msg)"
            case .decodingFailed(let msg):
                return "The trainer sent something Kiln could not read. \(msg)"
            case .other(let reason):
                return reason
            }
        }

        static func fromTraining(_ error: TrainingError) -> DisplayError {
            switch error {
            case .oom(let m): return .outOfMemory(m)
            case .dataInvalid(let m): return .dataInvalid(m)
            case .modelNotFound(let m): return .modelNotFound(m)
            case .adapterInvalid(let m): return .subprocessFailed(m)
            case .ggufFailed(let m): return .subprocessFailed(m)
            case .ollamaUnavailable(let m): return .subprocessFailed(m)
            case .subprocessFailed(let m): return .subprocessFailed(m)
            case .sigterm(let m): return .interrupted(m)
            case .internalError(let m): return .other(m)
            case .cancelled: return .cancelled
            case .launchFailed(let m): return .launchFailed(m)
            case .decodingFailed(_, let underlying): return .decodingFailed(underlying)
            case .unexpectedExit(let code, let tail):
                return .subprocessFailed("exit code \(code). \(tail.prefix(200))")
            }
        }
    }

    // Published state.
    var status: Status = .idle
    var currentProgress: TrainingProgress?
    var lossHistory: [LossSample] = []
    var lastCheckpoint: (url: URL, iter: Int)?
    var currentEta: TimeInterval?
    var isWarmingUp: Bool = true
    var totalIters: Int?
    var sidecarVersion: String?

    // Private state.
    private var task: Task<Void, Never>?
    private var request: TrainingRequest?
    private var startTime: Date?
    private var etaEstimator: EtaEstimator = EtaEstimator(hyperparameters: Hyperparameters())
    private var lastPublishedAt: TimeInterval = 0
    private let publishIntervalSeconds: TimeInterval = 0.016
    private let lossHistoryCap: Int = 200
    private let runner: TrainingRunner?

    /// Cheap sampling to bound sparkline cost: we keep at most one datum per
    /// N iters up until the cap. For a 400-iter run with a 200-sample cap
    /// that's 1:1; for longer runs it downsamples transparently.
    private var sampleStride: Int = 1

    init(runner: TrainingRunner? = nil) {
        self.runner = runner
    }

    func start(request: TrainingRequest) {
        guard case .idle = status else { return }
        guard let runner else {
            status = .failed(.other("no training runner configured"))
            return
        }
        prepareForStart(request: request)
        let stream = runner.runStreaming(request: request)
        task = Task { [weak self] in
            await self?.consume(stream: stream)
        }
    }

    /// Test seam — drives the model off an injected event stream.
    func testing_start(
        request: TrainingRequest,
        stream: AsyncThrowingStream<TrainingEvent, Error>
    ) {
        guard case .idle = status else { return }
        prepareForStart(request: request)
        task = Task { [weak self] in
            await self?.consume(stream: stream)
        }
    }

    func cancel() {
        guard case .running = status else { return }
        status = .cancelling(lastIter: currentProgress?.iter)
        task?.cancel()
    }

    func reset() {
        task?.cancel()
        task = nil
        status = .idle
        currentProgress = nil
        lossHistory = []
        lastCheckpoint = nil
        currentEta = nil
        isWarmingUp = true
        totalIters = nil
        sidecarVersion = nil
        request = nil
        startTime = nil
    }

    private func prepareForStart(request: TrainingRequest) {
        self.request = request
        self.startTime = Date()
        self.status = .running
        self.currentProgress = nil
        self.lossHistory = []
        self.lastCheckpoint = nil
        self.currentEta = nil
        self.isWarmingUp = true
        self.totalIters = request.itersOverride
        self.sidecarVersion = nil
        self.lastPublishedAt = 0
        self.etaEstimator = EtaEstimator(hyperparameters: request.hyperparameters)
        if let iters = request.itersOverride, iters > lossHistoryCap {
            self.sampleStride = max(1, iters / lossHistoryCap)
        } else {
            self.sampleStride = 1
        }
    }

    private func consume(stream: AsyncThrowingStream<TrainingEvent, Error>) async {
        do {
            for try await event in stream {
                apply(event)
                if case .completed = status { break }
                if case .failed = status { break }
            }
            // Stream finished cleanly without a terminal event — if the user
            // was cancelling, map to .cancelled.
            if case .cancelling = status {
                status = .failed(.cancelled)
            }
        } catch let error as TrainingError {
            if case .cancelling = status, error == .cancelled {
                status = .failed(.cancelled)
            } else {
                status = .failed(.fromTraining(error))
            }
        } catch is CancellationError {
            status = .failed(.cancelled)
        } catch {
            status = .failed(.other(error.localizedDescription))
        }
    }

    private func apply(_ event: TrainingEvent) {
        switch event {
        case .ready(let version, _):
            sidecarVersion = version

        case .progress(let progress):
            currentProgress = progress
            if progress.iter >= etaEstimator.warmupIters { isWarmingUp = false }

            // Sparkline history (sampled if the run is long).
            if progress.iter.isMultiple(of: max(1, sampleStride)) || progress.valLoss != nil {
                let sample = LossSample(
                    iter: progress.iter,
                    trainLoss: progress.loss,
                    valLoss: progress.valLoss
                )
                lossHistory.append(sample)
                if lossHistory.count > lossHistoryCap {
                    lossHistory.removeFirst(lossHistory.count - lossHistoryCap)
                }
            }

            // ETA: prefer sidecar-provided when present, fall back to local EMA.
            if let sidecarEta = progress.etaSec {
                currentEta = sidecarEta
            } else if let total = totalIters {
                currentEta = etaEstimator.update(
                    iter: progress.iter,
                    tokensPerSec: progress.tokensPerSec,
                    totalIters: total
                )
            }

        case .sample:
            // M6 renders Growing-Model samples; M5 forwards silently.
            break

        case .checkpoint(let path, let iter, _):
            lastCheckpoint = (url: path, iter: iter)

        case .done(let artifact, let interrupted):
            let now = Date()
            let wallClock = startTime.map { now.timeIntervalSince($0) } ?? 0
            let partial = interrupted
                && FileManager.default.fileExists(atPath: artifact.path)
            let reachedFirstCheckpoint = lastCheckpoint != nil

            if interrupted && !reachedFirstCheckpoint {
                status = .failed(.cancelled)
                return
            }
            let report = TrainingReport(
                adapterURL: artifact,
                itersCompleted: currentProgress?.iter ?? lastCheckpoint?.iter ?? 0,
                totalIters: totalIters,
                finalLoss: currentProgress?.loss,
                finalValLoss: lossHistory.compactMap(\.valLoss).last,
                wallClockSec: wallClock,
                interrupted: interrupted,
                partialCheckpoint: partial
            )
            status = .completed(report)

        case .error(let error):
            status = .failed(.fromTraining(error))
        }
    }
}

extension TrainModel.Status {
    static func == (lhs: TrainModel.Status, rhs: TrainModel.Status) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.running, .running): return true
        case (.cancelling(let a), .cancelling(let b)): return a == b
        case (.completed(let a), .completed(let b)): return a == b
        case (.failed(let a), .failed(let b)): return a == b
        default: return false
        }
    }
}

extension TrainModel {
    /// Rolling, smoothed ETA suitable for display. Returns `nil` while the
    /// sidecar is still warming up.
    var etaDisplay: String? {
        guard let eta = currentEta, eta.isFinite, eta >= 0 else { return nil }
        let seconds = Int(eta.rounded())
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        let remaining = seconds % 60
        if minutes < 60 { return String(format: "%dm %02ds", minutes, remaining) }
        let hours = minutes / 60
        let mm = minutes % 60
        return String(format: "%dh %02dm", hours, mm)
    }
}
