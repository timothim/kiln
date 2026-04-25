import Foundation
import KilnCore
import Observation

/// Drives the `VoiceSelectorView` in the sidebar. Thin @Observable wrapper
/// around a `VoicesProvider`, publishing on the main actor so SwiftUI reads
/// stay cheap. Refresh is explicit — the sidebar triggers it on appear and
/// after training completes; there's no polling today.
@Observable
@MainActor
final class VoicesModel {
    private(set) var voices: [KilnVoices.Voice] = []
    private(set) var activeID: UUID?
    private(set) var loadError: String?
    private(set) var isLoading: Bool = false

    private let provider: any VoicesProvider

    init(provider: any VoicesProvider) {
        self.provider = provider
    }

    /// Convenience for the production wiring path — walks through
    /// `DiskVoicesProvider` against the default storage location.
    convenience init() {
        self.init(provider: DiskVoicesProvider())
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let next = try await provider.list()
            voices = next
            // If the previously-active voice was deleted out from under us,
            // clear the active marker so the selector reverts to "No voice".
            if let id = activeID, !next.contains(where: { $0.id == id }) {
                activeID = nil
            }
            loadError = nil
        } catch {
            loadError = error.localizedDescription
            // Don't clobber previously-loaded voices on a transient failure —
            // the selector stays usable with stale data.
        }
    }

    func activate(_ id: UUID) async {
        do {
            try await provider.activate(id)
            activeID = id
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Resolves the currently-active voice, if any. Used by the selector to
    /// render the "active" dot.
    var activeVoice: KilnVoices.Voice? {
        guard let id = activeID else { return nil }
        return voices.first { $0.id == id }
    }
}
