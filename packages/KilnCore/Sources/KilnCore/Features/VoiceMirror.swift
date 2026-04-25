import Foundation

/// Real-time "mirror" that shows the user how the current adapter would
/// complete a prompt as it is trained. Implemented in M7 via
/// ``SubprocessSampleCompareRunner`` (see Sampling/SampleCompareRunner.swift).
/// The legacy ``VoiceMirror.reflect`` stub stays as dead code; the live
/// path is the side-by-side base/finetuned/blended sample-compare flow.
public enum VoiceMirror {
    public static let isImplemented = true

    public struct Reflection: Sendable, Equatable {
        public let prompt: String
        public let continuation: String
        public let adapterStep: Int

        public init(prompt: String, continuation: String, adapterStep: Int) {
            self.prompt = prompt
            self.continuation = continuation
            self.adapterStep = adapterStep
        }
    }

    public enum MirrorError: Error, Equatable {
        case notImplemented
    }

    public static func reflect(prompt _: String, adapterStep _: Int) async throws -> Reflection {
        throw MirrorError.notImplemented
    }
}
