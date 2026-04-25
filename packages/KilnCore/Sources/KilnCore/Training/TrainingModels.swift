import Foundation

/// Per-3B-Instruct defaults. 1.5B / 7B alternates live in the Python sidecar's
/// `hyperparams.py`; M5 hardcodes 3B per the day-4 brief.
public struct Hyperparameters: Sendable, Hashable {
    public var rank: Int
    public var alpha: Int
    public var loraLayers: Int
    public var epochs: Int
    public var batchSize: Int
    public var learningRate: Double
    public var maxSeqLength: Int
    public var saveEvery: Int
    public var valBatches: Int

    public init(
        rank: Int = 16,
        alpha: Int = 32,
        loraLayers: Int = 16,
        epochs: Int = 2,
        batchSize: Int = 2,
        learningRate: Double = 1e-4,
        maxSeqLength: Int = 2_048,
        saveEvery: Int = 50,
        valBatches: Int = 25
    ) {
        self.rank = rank
        self.alpha = alpha
        self.loraLayers = loraLayers
        self.epochs = epochs
        self.batchSize = batchSize
        self.learningRate = learningRate
        self.maxSeqLength = maxSeqLength
        self.saveEvery = saveEvery
        self.valBatches = valBatches
    }
}

public struct TrainingRequest: Sendable, Hashable {
    public let datasetURL: URL
    public let runDir: URL
    public let model: String
    public let seed: UInt64
    public let hyperparameters: Hyperparameters
    public let itersOverride: Int?
    /// Test seam — when non-nil, passed through as `--trainer-module`.
    public let trainerModule: String?
    /// Test seam — when non-nil, passed through as `--trainer-entry`.
    public let trainerEntry: String?
    /// Pre-training persona configuration. M8 carries this for UI continuity;
    /// the Python sidecar ignores it. M9+ will teach the trainer to honor
    /// persona slicing — at that point the runner's arg-builder emits a flag.
    public let voiceSplit: VoiceSplit?
    /// PR #23 — when true the sidecar runs the post-checkpoint Training
    /// Advisor (Opus 4.7 cloud or local Qwen via Ollama). Off by default.
    public let enableAdvisor: Bool
    /// Either ``"cloud"`` (Opus 4.7) or ``"local"`` (Qwen via Ollama).
    /// Ignored when ``enableAdvisor`` is false.
    public let advisorMode: String

    public init(
        datasetURL: URL,
        runDir: URL,
        model: String = "mlx-community/Qwen2.5-3B-Instruct-4bit",
        seed: UInt64 = 42,
        hyperparameters: Hyperparameters = Hyperparameters(),
        itersOverride: Int? = nil,
        trainerModule: String? = nil,
        trainerEntry: String? = nil,
        voiceSplit: VoiceSplit? = nil,
        enableAdvisor: Bool = false,
        advisorMode: String = "cloud"
    ) {
        self.datasetURL = datasetURL
        self.runDir = runDir
        self.model = model
        self.seed = seed
        self.hyperparameters = hyperparameters
        self.itersOverride = itersOverride
        self.trainerModule = trainerModule
        self.trainerEntry = trainerEntry
        self.voiceSplit = voiceSplit
        self.enableAdvisor = enableAdvisor
        self.advisorMode = advisorMode
    }

    public func withVoiceSplit(_ split: VoiceSplit?) -> TrainingRequest {
        TrainingRequest(
            datasetURL: datasetURL,
            runDir: runDir,
            model: model,
            seed: seed,
            hyperparameters: hyperparameters,
            itersOverride: itersOverride,
            trainerModule: trainerModule,
            trainerEntry: trainerEntry,
            voiceSplit: split,
            enableAdvisor: enableAdvisor,
            advisorMode: advisorMode
        )
    }
}

/// Single progress row emitted by the sidecar — direct mirror of
/// `events.progress(...)` in `packages/kiln_trainer/src/kiln_trainer/events.py`.
public struct TrainingProgress: Sendable, Hashable {
    public let iter: Int
    public let loss: Double
    public let tokensPerSec: Double?
    public let etaSec: Double?
    public let valLoss: Double?
    public let learningRate: Double?

    public init(
        iter: Int,
        loss: Double,
        tokensPerSec: Double? = nil,
        etaSec: Double? = nil,
        valLoss: Double? = nil,
        learningRate: Double? = nil
    ) {
        self.iter = iter
        self.loss = loss
        self.tokensPerSec = tokensPerSec
        self.etaSec = etaSec
        self.valLoss = valLoss
        self.learningRate = learningRate
    }
}

/// Single point in the loss sparkline. Val points are sparse.
public struct LossSample: Sendable, Hashable {
    public let iter: Int
    public let trainLoss: Double
    public let valLoss: Double?

    public init(iter: Int, trainLoss: Double, valLoss: Double? = nil) {
        self.iter = iter
        self.trainLoss = trainLoss
        self.valLoss = valLoss
    }
}

/// Training-time sample (Growing Model preview — M6 renders; M5 forwards).
public struct TrainingSample: Sendable, Hashable {
    public let iter: Int
    public let promptID: String
    public let completion: String
    public let tokensPerSec: Double?

    public init(iter: Int, promptID: String, completion: String, tokensPerSec: Double? = nil) {
        self.iter = iter
        self.promptID = promptID
        self.completion = completion
        self.tokensPerSec = tokensPerSec
    }
}

/// Final synthesis of a training run. Built by `TrainModel` from the
/// accumulated progress events plus the terminal `done` event — the sidecar
/// itself only emits `{stage, artifact, interrupted}` on `done`, so the richer
/// summary shape is a Swift-side concept.
public struct TrainingReport: Sendable, Hashable {
    public let adapterURL: URL
    public let itersCompleted: Int
    public let totalIters: Int?
    public let finalLoss: Double?
    public let finalValLoss: Double?
    public let wallClockSec: Double
    public let interrupted: Bool
    public let partialCheckpoint: Bool

    public init(
        adapterURL: URL,
        itersCompleted: Int,
        totalIters: Int?,
        finalLoss: Double?,
        finalValLoss: Double?,
        wallClockSec: Double,
        interrupted: Bool,
        partialCheckpoint: Bool
    ) {
        self.adapterURL = adapterURL
        self.itersCompleted = itersCompleted
        self.totalIters = totalIters
        self.finalLoss = finalLoss
        self.finalValLoss = finalValLoss
        self.wallClockSec = wallClockSec
        self.interrupted = interrupted
        self.partialCheckpoint = partialCheckpoint
    }
}

/// 1-to-1 with `EVENT_TYPES` in the Python sidecar. The discriminator on the
/// wire is the field named `"event"` (not `"type"`).
public enum TrainingEvent: Sendable, Hashable {
    case ready(version: String, mlx: String)
    case progress(TrainingProgress)
    case sample(TrainingSample)
    case checkpoint(path: URL, iter: Int, best: Bool?)
    case advisorObservation(iter: Int, content: String, modelID: String)
    case done(artifact: URL, interrupted: Bool)
    case error(TrainingError)
}

extension TrainingEvent: Decodable {
    private enum Discriminator: String, CodingKey { case event }

    private enum ReadyKeys: String, CodingKey { case version, mlx }
    private enum ProgressKeys: String, CodingKey {
        case iter, loss
        case tokensPerSec = "tokens_per_s"
        case etaSec = "eta_s"
        case valLoss = "val_loss"
        case learningRate = "learning_rate"
    }
    private enum SampleKeys: String, CodingKey {
        case iter
        case promptID = "prompt_id"
        case completion
        case tokensPerSec = "tokens_per_s"
    }
    private enum CheckpointKeys: String, CodingKey { case path, iter, best }
    private enum AdvisorKeys: String, CodingKey { case iter, content, model }
    private enum DoneKeys: String, CodingKey { case artifact, interrupted }
    private enum ErrorKeys: String, CodingKey { case code, message, recoverable }

    public init(from decoder: Decoder) throws {
        let disc = try decoder.container(keyedBy: Discriminator.self)
        let tag = try disc.decode(String.self, forKey: .event)
        switch tag {
        case "ready":
            let c = try decoder.container(keyedBy: ReadyKeys.self)
            let version = try c.decode(String.self, forKey: .version)
            let mlx = (try? c.decode(String.self, forKey: .mlx)) ?? "n/a"
            self = .ready(version: version, mlx: mlx)

        case "progress":
            let c = try decoder.container(keyedBy: ProgressKeys.self)
            self = .progress(TrainingProgress(
                iter: try c.decode(Int.self, forKey: .iter),
                loss: try c.decode(Double.self, forKey: .loss),
                tokensPerSec: try c.decodeIfPresent(Double.self, forKey: .tokensPerSec),
                etaSec: try c.decodeIfPresent(Double.self, forKey: .etaSec),
                valLoss: try c.decodeIfPresent(Double.self, forKey: .valLoss),
                learningRate: try c.decodeIfPresent(Double.self, forKey: .learningRate)
            ))

        case "sample":
            let c = try decoder.container(keyedBy: SampleKeys.self)
            self = .sample(TrainingSample(
                iter: try c.decode(Int.self, forKey: .iter),
                promptID: try c.decode(String.self, forKey: .promptID),
                completion: try c.decode(String.self, forKey: .completion),
                tokensPerSec: try c.decodeIfPresent(Double.self, forKey: .tokensPerSec)
            ))

        case "checkpoint":
            let c = try decoder.container(keyedBy: CheckpointKeys.self)
            let path = try c.decode(String.self, forKey: .path)
            self = .checkpoint(
                path: URL(fileURLWithPath: path),
                iter: try c.decode(Int.self, forKey: .iter),
                best: try c.decodeIfPresent(Bool.self, forKey: .best)
            )

        case "advisor_observation":
            let c = try decoder.container(keyedBy: AdvisorKeys.self)
            self = .advisorObservation(
                iter: try c.decode(Int.self, forKey: .iter),
                content: try c.decode(String.self, forKey: .content),
                modelID: try c.decode(String.self, forKey: .model)
            )

        case "done":
            let c = try decoder.container(keyedBy: DoneKeys.self)
            let artifact = try c.decode(String.self, forKey: .artifact)
            let interrupted = (try c.decodeIfPresent(Bool.self, forKey: .interrupted)) ?? false
            self = .done(artifact: URL(fileURLWithPath: artifact), interrupted: interrupted)

        case "error":
            let c = try decoder.container(keyedBy: ErrorKeys.self)
            let code = try c.decode(String.self, forKey: .code)
            let message = try c.decode(String.self, forKey: .message)
            let recoverable = (try c.decodeIfPresent(Bool.self, forKey: .recoverable)) ?? false
            self = .error(TrainingError.fromCode(code, message: message, recoverable: recoverable))

        default:
            throw DecodingError.dataCorruptedError(
                forKey: .event,
                in: disc,
                debugDescription: "unknown event type: \(tag)"
            )
        }
    }
}
