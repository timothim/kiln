import Foundation
import KilnCore

/// Builds an `AsyncThrowingStream<TrainingEvent, Error>` from a fixed array of
/// events. Used in the TrainModel state-machine tests so we never spin the
/// real sidecar.
enum TrainEventStream {
    static func from(events: [TrainingEvent]) -> AsyncThrowingStream<TrainingEvent, Error> {
        AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }

    static func failing(with error: Error) -> AsyncThrowingStream<TrainingEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: error)
        }
    }

    /// Stream that yields every event in `events` and then blocks forever.
    /// Useful for cancellation tests where we want the model to sit in
    /// `.running` until `cancel()` is called.
    static func openEnded(
        initial events: [TrainingEvent] = []
    ) -> AsyncThrowingStream<TrainingEvent, Error> {
        AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            // Intentionally never finish — consumer's cancellation must drive exit.
        }
    }
}
