import Foundation
import KilnCore
import Observation

/// Driver for ``VoiceInspectorPanel`` that calls ``EmbedSearchRunner``
/// when a selection changes (M9.B wiring).
///
/// The panel itself stays a pure rendering layer that takes
/// ``InspectorSelection``, ``[NearestSample]``, and ``isLoading``. This
/// model owns the call into the sidecar plus the mapping from
/// ``EmbedSearchMatch`` (id + similarity + rank) onto ``NearestSample``
/// (id + source metadata + excerpt + similarity). The corpus directory
/// — which carries the text, source, and excerpt for every chunk — is
/// supplied by the caller via ``corpusProvider``.
///
/// ``selectSpan(...)`` cancels any in-flight search. Two clicks land
/// "back to back" → only the latest result reaches the panel.

@Observable
@MainActor
final class VoiceInspectorModel {
    private(set) var selection: InspectorSelection? = nil
    private(set) var nearestSamples: [NearestSample] = []
    private(set) var isLoading: Bool = false
    private(set) var lastError: String? = nil

    /// Opaque corpus row used by the model. The Voice Inspector panel's
    /// ``NearestSample`` is built from this plus the embed match. Kept as
    /// its own type (rather than the panel's) so this model stays
    /// independent of panel internals.
    struct CorpusRow: Sendable, Hashable {
        let id: String
        let text: String
        let source: CorpusSource
        let sourceDetail: String
        let excerpt: String
        let timestamp: Date?

        init(
            id: String,
            text: String,
            source: CorpusSource,
            sourceDetail: String,
            excerpt: String,
            timestamp: Date? = nil
        ) {
            self.id = id
            self.text = text
            self.source = source
            self.sourceDetail = sourceDetail
            self.excerpt = excerpt
            self.timestamp = timestamp
        }
    }

    private let runner: EmbedSearchRunner
    /// Returns the corpus to search. Re-queried per selection so callers
    /// can refresh dynamically (e.g. after a new ingest run lands).
    var corpusProvider: () -> [CorpusRow]
    /// How many neighbours to surface. Default 3 per the M9 plan.
    var topK: Int = 3
    /// Embedder mode. Production = ``"sentence-transformers"``; tests
    /// can pass ``"fake-hash"`` to keep CI offline.
    var embedderMode: String = "sentence-transformers"

    private var inFlight: Task<Void, Never>? = nil

    init(
        runner: EmbedSearchRunner,
        corpusProvider: @escaping () -> [CorpusRow] = { [] }
    ) {
        self.runner = runner
        self.corpusProvider = corpusProvider
    }

    /// Set a new selection and kick off a search. Idempotent: passing
    /// the same selection cancels any in-flight call to avoid a stale
    /// answer overwriting a fresh one.
    func selectSpan(_ selection: InspectorSelection?) {
        // Cancel any running search before starting a new one.
        inFlight?.cancel()
        inFlight = nil

        self.selection = selection
        nearestSamples = []
        lastError = nil

        guard let selection else {
            isLoading = false
            return
        }

        let span = selection.highlightedSpan
        let corpus = corpusProvider()
        guard !corpus.isEmpty else {
            isLoading = false
            return
        }

        isLoading = true
        let runner = self.runner
        let topK = self.topK
        let embedder = self.embedderMode
        // First-wins on duplicate ids: `uniqueKeysWithValues` traps,
        // and a malformed corpus shouldn't crash the app. Verifier T2
        // finding on PR #17.
        let lookup = Dictionary(corpus.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        inFlight = Task { @MainActor [weak self] in
            do {
                let rows = corpus.map {
                    EmbedSearchCorpusRow(requestID: $0.id, text: $0.text)
                }
                let matches = try await runner.search(
                    query: span,
                    corpus: rows,
                    topK: topK,
                    embedder: embedder
                )
                if Task.isCancelled { return }
                guard let self else { return }
                self.nearestSamples = matches.compactMap { match in
                    guard let row = lookup[match.requestID] else { return nil }
                    return NearestSample(
                        id: row.id,
                        source: row.source,
                        sourceDetail: row.sourceDetail,
                        excerpt: row.excerpt,
                        similarity: match.similarity,
                        timestamp: row.timestamp
                    )
                }
                self.isLoading = false
            } catch is CancellationError {
                // Selection changed while we were running — drop on the floor.
            } catch {
                guard let self else { return }
                if Task.isCancelled { return }
                self.lastError = String(describing: error)
                self.isLoading = false
            }
        }
    }

    /// Drop the current selection without running a new search. Wired
    /// into the panel's onDismiss callback.
    func dismiss() {
        inFlight?.cancel()
        inFlight = nil
        selection = nil
        nearestSamples = []
        isLoading = false
        lastError = nil
    }
}
