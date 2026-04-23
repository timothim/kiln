import Foundation
import KilnCore

/// Builds an `AsyncThrowingStream<IngestEvent, Error>` from a fixed array of
/// events. Used in the PrepareModel state-machine tests to avoid running the
/// real pipeline.
enum PreparedEventStream {
    static func from(events: [IngestEvent]) -> AsyncThrowingStream<IngestEvent, Error> {
        AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }

    static func failing(with error: Error) -> AsyncThrowingStream<IngestEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: error)
        }
    }
}
