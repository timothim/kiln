import XCTest
import KilnCore
@testable import Kiln

@MainActor
final class VoicesModelTests: XCTestCase {

    // MARK: - refresh()

    func test_refresh_populates_voices_from_provider() async {
        let seed = [
            KilnVoices.Voice(
                id: UUID(),
                name: "drafts",
                ollamaTag: "kiln/drafts:latest",
                createdAt: Date(timeIntervalSince1970: 1_000)
            ),
            KilnVoices.Voice(
                id: UUID(),
                name: "formal",
                ollamaTag: "kiln/formal:latest",
                createdAt: Date(timeIntervalSince1970: 2_000)
            )
        ]
        let provider = InMemoryVoicesProvider(seed: seed)
        let model = VoicesModel(provider: provider)

        await model.refresh()

        XCTAssertEqual(model.voices.count, 2)
        XCTAssertEqual(Set(model.voices.map(\.name)), ["drafts", "formal"])
        XCTAssertNil(model.loadError)
        XCTAssertFalse(model.isLoading)
    }

    func test_refresh_captures_error_without_clobbering_voices() async {
        // Seed initial data.
        let ok = InMemoryVoicesProvider(seed: [
            KilnVoices.Voice(
                id: UUID(),
                name: "drafts",
                ollamaTag: "kiln/drafts:latest",
                createdAt: .distantPast
            )
        ])
        let model = VoicesModel(provider: ok)
        await model.refresh()
        XCTAssertEqual(model.voices.count, 1)

        // Swap in a throwing provider by creating a new model seeded after
        // the first refresh — VoicesModel holds its provider privately so
        // we validate the "stay usable with stale data" contract here by
        // exercising the throwing branch with a fresh model.
        let throwing = InMemoryVoicesProvider(throwsOnList: true)
        let throwingModel = VoicesModel(provider: throwing)

        // Seed some state first, then make it fail — but since the provider
        // throws unconditionally, the only way to establish "prior voices"
        // is to set them via a first refresh on a non-throwing instance.
        // Here, we validate the throw path alone: voices start empty, remain
        // empty, loadError is populated.
        await throwingModel.refresh()

        XCTAssertTrue(throwingModel.voices.isEmpty)
        XCTAssertNotNil(throwingModel.loadError)
        XCTAssertFalse(throwingModel.isLoading)
    }

    func test_refresh_preserves_previous_voices_on_transient_failure() async {
        // This test uses a custom provider that flips between success and
        // failure to prove the "don't clobber stale data" contract.
        final class FlakyProvider: VoicesProvider, @unchecked Sendable {
            let lock = NSLock()
            var shouldFail = false
            var seed: [KilnVoices.Voice]

            init(seed: [KilnVoices.Voice]) { self.seed = seed }

            func list() async throws -> [KilnVoices.Voice] {
                lock.lock(); defer { lock.unlock() }
                if shouldFail { throw VoicesProviderError.notImplemented }
                return seed
            }
            func activate(_: UUID) async throws {}
        }

        let provider = FlakyProvider(seed: [
            KilnVoices.Voice(
                id: UUID(),
                name: "drafts",
                ollamaTag: "kiln/drafts:latest",
                createdAt: Date()
            )
        ])
        let model = VoicesModel(provider: provider)
        await model.refresh()
        XCTAssertEqual(model.voices.count, 1)

        provider.lock.lock(); provider.shouldFail = true; provider.lock.unlock()
        await model.refresh()

        XCTAssertEqual(model.voices.count, 1, "stale voices must survive a transient provider failure")
        XCTAssertNotNil(model.loadError)
    }

    // MARK: - activate()

    func test_activate_sets_active_id_on_success() async {
        let voice = KilnVoices.Voice(
            id: UUID(),
            name: "drafts",
            ollamaTag: "kiln/drafts:latest",
            createdAt: Date()
        )
        let provider = InMemoryVoicesProvider(seed: [voice])
        let model = VoicesModel(provider: provider)
        await model.refresh()

        await model.activate(voice.id)

        XCTAssertEqual(model.activeID, voice.id)
        XCTAssertNil(model.loadError)
    }

    func test_activate_records_error_for_unknown_voice() async {
        let provider = InMemoryVoicesProvider(seed: [])
        let model = VoicesModel(provider: provider)
        await model.refresh()

        await model.activate(UUID())

        XCTAssertNil(model.activeID, "an unknown voice must not be marked active")
        XCTAssertNotNil(model.loadError)
    }

    // MARK: - activeVoice derivation

    func test_active_voice_resolves_from_active_id() async {
        let target = KilnVoices.Voice(
            id: UUID(),
            name: "drafts",
            ollamaTag: "kiln/drafts:latest",
            createdAt: Date()
        )
        let other = KilnVoices.Voice(
            id: UUID(),
            name: "formal",
            ollamaTag: "kiln/formal:latest",
            createdAt: Date()
        )
        let provider = InMemoryVoicesProvider(seed: [target, other])
        let model = VoicesModel(provider: provider)
        await model.refresh()
        await model.activate(target.id)

        XCTAssertEqual(model.activeVoice?.name, "drafts")
    }

    func test_active_voice_is_nil_when_voice_removed() async {
        let target = KilnVoices.Voice(
            id: UUID(),
            name: "drafts",
            ollamaTag: "kiln/drafts:latest",
            createdAt: Date()
        )
        let provider = InMemoryVoicesProvider(seed: [target])
        let model = VoicesModel(provider: provider)
        await model.refresh()
        await model.activate(target.id)
        XCTAssertEqual(model.activeID, target.id)

        // Swap to a provider that no longer lists `target`.
        let empty = InMemoryVoicesProvider(seed: [])
        let empty2 = VoicesModel(provider: empty)
        // Carry the activeID over to simulate the "voice was deleted out
        // from under us" path.
        await empty2.refresh()
        // Using the new model means activeID stays nil; what we actually
        // want to test is the same model reacting to its provider losing
        // the voice. Simulate by refreshing the original model against an
        // empty provider reference — but VoicesModel holds its provider
        // immutably, so we verify the "refresh drops stale activeID"
        // branch via a dedicated flaky provider.

        final class EmptyingProvider: VoicesProvider, @unchecked Sendable {
            var seed: [KilnVoices.Voice]
            init(seed: [KilnVoices.Voice]) { self.seed = seed }
            func list() async throws -> [KilnVoices.Voice] { seed }
            func activate(_: UUID) async throws {}
        }

        let emptying = EmptyingProvider(seed: [target])
        let model2 = VoicesModel(provider: emptying)
        await model2.refresh()
        await model2.activate(target.id)
        XCTAssertEqual(model2.activeID, target.id)

        emptying.seed = []
        await model2.refresh()
        XCTAssertNil(model2.activeID, "activeID must clear when the active voice disappears")
        XCTAssertNil(model2.activeVoice)
    }
}
