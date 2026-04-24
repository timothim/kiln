import Foundation

/// Swift-side glue for incremental LoRA training — the user drops
/// additional material after the first run and the existing adapter
/// continues from its last checkpoint. The actual training loop lives
/// in `packages/kiln_trainer/src/kiln_trainer/features/incremental.py`;
/// this module only exposes the request/reply shapes the Swift UI binds
/// against.
public enum IncrementalLearning {
    public static let isImplemented = false

    public struct Request: Sendable, Equatable {
        public let baseAdapterURL: URL
        public let additionalCorpusURL: URL
        public let extraEpochs: Int

        public init(baseAdapterURL: URL, additionalCorpusURL: URL, extraEpochs: Int) {
            self.baseAdapterURL = baseAdapterURL
            self.additionalCorpusURL = additionalCorpusURL
            self.extraEpochs = extraEpochs
        }
    }

    public struct Result: Sendable, Equatable {
        public let newAdapterURL: URL
        public let stepsAdded: Int
        public let finalLoss: Float
    }

    public enum LearnError: Error, Equatable {
        case notImplemented
    }

    public static func continueTraining(_: Request) async throws -> Result {
        throw LearnError.notImplemented
    }
}
