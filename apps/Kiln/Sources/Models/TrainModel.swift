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

    /// Three fixed Growing-Model prompt cards. Seeded in prepareForStart,
    /// updated as `.sample` events arrive, cleared by reset. Always length 3
    /// while training; empty at rest.
    var growingModelSamples: [PromptSample] = []

    /// Captured from request.hyperparameters at start — used by the panel
    /// header to render "Step N · Epoch E of T".
    var totalEpochs: Int = 1

    /// PR #23 Training Advisor observations. Each entry is a one-line
    /// Opus (or local-Qwen) take on the run's state at a checkpoint
    /// boundary. The TrainingAdvisorPanel renders the most-recent 8.
    var advisorObservations: [AdvisorObservation] = []

    struct AdvisorObservation: Identifiable, Hashable {
        let id = UUID()
        let iter: Int
        let content: String
        let modelID: String
        let arrivedAt: Date
    }

    /// Audit post-merge: rolling event log streamed into ``LogsPanel``.
    /// Replaces the old hardcoded canned content. Capped so a long run
    /// doesn't grow the array unbounded (keeps latest 200).
    var eventLog: [LogLine] = []
    private let eventLogCap: Int = 200

    struct LogLine: Identifiable, Hashable {
        let id = UUID()
        let timestamp: Date
        let kind: Kind
        let text: String

        enum Kind: Hashable {
            case ready
            case progress
            case sample
            case checkpoint
            case advisor
            case done
            case error
        }
    }

    private func appendLog(_ kind: LogLine.Kind, _ text: String) {
        eventLog.append(LogLine(timestamp: Date(), kind: kind, text: text))
        if eventLog.count > eventLogCap {
            eventLog.removeFirst(eventLog.count - eventLogCap)
        }
    }

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

    /// Stable promptID → index into growingModelSamples. Matches the three
    /// entries in GrowingModelPrompts.defaults — authoritative for what the
    /// sidecar emits on the wire.
    private static let promptIndex: [String: Int] = [
        "week_focus": 0,
        "birthday_msg": 1,
        "perfect_sunday": 2
    ]

    init(runner: TrainingRunner? = nil) {
        self.runner = runner
    }

    func start(request: TrainingRequest, voiceSplit: VoiceSplit? = nil) {
        guard case .idle = status else { return }
        guard let runner else {
            status = .failed(.other("no training runner configured"))
            return
        }
        let threaded = request.withVoiceSplit(voiceSplit ?? request.voiceSplit)
        prepareForStart(request: threaded)
        let stream = runner.runStreaming(request: threaded)
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
        growingModelSamples = []
        totalEpochs = 1
        advisorObservations = []
        eventLog = []
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
        self.totalEpochs = max(1, request.hyperparameters.epochs)
        self.growingModelSamples = GrowingModelPrompts.defaults.map { prompt in
            PromptSample(prompt: prompt.text)
        }
        self.advisorObservations = []
        self.eventLog = []
        appendLog(.ready, "spawning trainer · \(request.model)")
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
        case .ready(let version, let mlx):
            sidecarVersion = version
            appendLog(.ready, "sidecar ready · mlx \(mlx)")

        case .progress(let progress):
            currentProgress = progress
            // Audit post-merge: ``isWarmingUp`` previously waited for
            // ``etaEstimator.warmupIters`` (20). On a short run (10
            // iters) it never flipped and the UI read "Warming up.
            // Loss numbers appear shortly." for the entire training
            // session. The ETA estimator still has its own 20-iter
            // warmup for stable EMA — that's a separate concern. The
            // UI's "warming up" copy means "no data yet" → flip on
            // first progress event.
            if isWarmingUp { isWarmingUp = false }

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
            // Log every Nth iter or any val-loss line so the LogsPanel
            // doesn't get spammed on a long run but the demo viewer
            // still sees rapid updates.
            let logStride = max(1, sampleStride)
            if progress.iter.isMultiple(of: logStride) || progress.valLoss != nil {
                let lossStr = String(format: "%.3f", progress.loss)
                var line = "iter \(progress.iter)  loss \(lossStr)"
                if let tps = progress.tokensPerSec {
                    line += "  · \(Int(tps)) tok/s"
                }
                if let val = progress.valLoss {
                    line += "  · val \(String(format: "%.3f", val))"
                }
                appendLog(.progress, line)
            }

        case .sample(let sample):
            guard let idx = Self.promptIndex[sample.promptID],
                  idx < growingModelSamples.count else {
                // Unknown promptID: silently skip. The three stable IDs in
                // GrowingModelPrompts.defaults are authoritative; anything
                // else is forward-compat noise or a test-harness probe.
                break
            }
            let existing = growingModelSamples[idx]
            growingModelSamples[idx] = PromptSample(
                id: existing.id,
                prompt: existing.prompt,
                currentResponse: sample.completion,
                isUpdating: false,
                stylizationScore: stylizationProxy(iter: sample.iter)
            )
            // First 60 chars of the new completion — gives the viewer
            // a glimpse of the voice settling in without quoting full
            // paragraphs into the log stream.
            let preview = sample.completion
                .replacingOccurrences(of: "\n", with: " ")
                .prefix(60)
            appendLog(.sample, "sample · iter \(sample.iter) · \(sample.promptID): \(preview)…")

        case .checkpoint(let path, let iter, _):
            lastCheckpoint = (url: path, iter: iter)
            appendLog(.checkpoint, "checkpoint saved · iter \(iter)")

        case .advisorObservation(let iter, let content, let modelID):
            advisorObservations.append(AdvisorObservation(
                iter: iter,
                content: content,
                modelID: modelID,
                arrivedAt: Date()
            ))
            appendLog(.advisor, "advisor (\(modelID)) iter \(iter): \(content)")

        case .done(let artifact, let interrupted):
            let now = Date()
            let wallClock = startTime.map { now.timeIntervalSince($0) } ?? 0
            let partial = interrupted
                && FileManager.default.fileExists(atPath: artifact.path)
            let reachedFirstCheckpoint = lastCheckpoint != nil

            if interrupted && !reachedFirstCheckpoint {
                appendLog(.error, "cancelled before first checkpoint")
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
            appendLog(
                .done,
                "done · \(report.itersCompleted) iters · \(Self.formatDuration(wallClock))"
            )
            status = .completed(report)

        case .error(let error):
            appendLog(.error, "error · \(String(describing: error))")
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

    /// Current 1-indexed epoch, derived from the latest progress iter and
    /// the captured totalIters/totalEpochs. Falls back to 1 when the sidecar
    /// has not reported a total iter count yet.
    var currentEpoch: Int {
        guard let iter = currentProgress?.iter,
              let total = totalIters, total > 0,
              totalEpochs > 0 else { return 1 }
        let itersPerEpoch = max(1, total / totalEpochs)
        return min(totalEpochs, 1 + max(0, iter - 1) / itersPerEpoch)
    }

    /// State for GrowingModelPanelView. Empty until at least one sample has
    /// a response; inProgress while training; completed when training ends.
    var growingModelState: GrowingModelState {
        switch status {
        case .completed:
            return .completed
        case .idle, .failed:
            return .empty
        case .running, .cancelling:
            return growingModelSamples.contains { $0.currentResponse != nil } ? .inProgress : .empty
        }
    }

    /// Pragmatic proxy for per-prompt stylization — the real metric isn't
    /// wired yet, so we map training progress (0–100%) to the gauge so the
    /// panel shows movement in sync with the global progress capsule.
    fileprivate func stylizationProxy(iter: Int) -> Double {
        let total = totalIters ?? max(iter, 1)
        guard total > 0 else { return 0 }
        let ratio = Double(min(iter, total)) / Double(total)
        return max(0, min(100, ratio * 100))
    }

    /// Format a duration the same way the Complete stage does, so the
    /// log line and the stat tile read the same number on done.
    static func formatDuration(_ seconds: Double) -> String {
        if seconds < 60 { return String(format: "%.1fs", seconds) }
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return "\(m)m \(s)s"
    }
}
