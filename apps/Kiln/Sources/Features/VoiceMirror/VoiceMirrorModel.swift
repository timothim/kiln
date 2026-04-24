import Foundation
import KilnCore
import Observation

/// Observable model for `VoiceMirrorView`. Two paths coexist:
///
/// 1. **Production** — an injected ``SampleCompareRunner`` + adapter paths
///    drive the three comparison columns from a single ``sample-compare``
///    subprocess; the sidecar emits one ``generation`` event per variant
///    and we route them into the matching reflection card.
/// 2. **Preview / DEBUG** — if no runner is supplied the model falls back to
///    the original deterministic mock so Xcode previews still render.
@Observable
@MainActor
final class VoiceMirrorModel {
    var prompt: String = ""
    var userAnswer: String = ""
    var reflections: [VoiceReflection]

    /// Base model id (must match the one used for training / export).
    var baseModel: String
    /// Adapter file shipped with the SFT-only checkpoint.
    var sftAdapterURL: URL?
    /// Adapter file shipped with the full SFT + DPO run.
    var sftDpoAdapterURL: URL?

    var isGenerating: Bool {
        reflections.contains { $0.source != .userAnswer && $0.state == .generating }
    }

    var hasAnyContent: Bool {
        !userAnswer.isEmpty || reflections.contains { $0.state != .idle }
    }

    private let runner: SampleCompareRunner?
    private var streamTask: Task<Void, Never>?

    init(
        runner: SampleCompareRunner? = nil,
        baseModel: String = "mlx-community/Qwen2.5-3B-Instruct-4bit",
        sftAdapterURL: URL? = nil,
        sftDpoAdapterURL: URL? = nil,
        reflections: [VoiceReflection]? = nil
    ) {
        self.runner = runner
        self.baseModel = baseModel
        self.sftAdapterURL = sftAdapterURL
        self.sftDpoAdapterURL = sftDpoAdapterURL
        self.reflections = reflections ?? Self.defaultReflections()
    }

    func generate() {
        let promptSnapshot = prompt
        let modelSources: [ReflectionSource] = [.baseQwen, .sftOnly, .sftPlusDpo]

        for i in reflections.indices where modelSources.contains(reflections[i].source) {
            reflections[i].prompt = promptSnapshot
            reflections[i].state = .generating
            reflections[i].continuation = ""
            reflections[i].signaturePhrases = []
        }

        if let runner {
            runRealGeneration(runner: runner, prompt: promptSnapshot)
        } else {
            runMockGeneration(prompt: promptSnapshot)
        }
    }

    func retry(_ source: ReflectionSource) {
        guard source != .userAnswer else { return }
        guard let i = reflections.firstIndex(where: { $0.source == source }) else { return }
        reflections[i].state = .generating
        reflections[i].continuation = ""
        reflections[i].signaturePhrases = []
        let promptSnapshot = reflections[i].prompt.isEmpty ? prompt : reflections[i].prompt

        if let runner {
            // Kick off a fresh sample-compare but only list the single variant
            // being retried — avoids redoing the ones that already succeeded.
            let variants: [SampleCompareRequest.VariantSpec]
            switch source {
            case .baseQwen: variants = [.init(variant: .base, adapterPath: nil)]
            case .sftOnly:  variants = [.init(variant: .sft, adapterPath: sftAdapterURL)]
            case .sftPlusDpo: variants = [.init(variant: .sftdpo, adapterPath: sftDpoAdapterURL)]
            case .userAnswer: return
            }
            let request = SampleCompareRequest(
                model: baseModel,
                prompt: promptSnapshot,
                variants: variants
            )
            streamTask?.cancel()
            streamTask = Task { [weak self] in
                await self?.consume(runner.runStreaming(request: request))
            }
        } else {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(Self.mockDelay(for: source)))
                self?.deliverMock(for: source, prompt: promptSnapshot)
            }
        }
    }

    func cancel() {
        streamTask?.cancel()
        streamTask = nil
        for i in reflections.indices where reflections[i].state == .generating {
            reflections[i].state = .failed(message: "Cancelled before the model finished.")
        }
    }

    // MARK: - Real subprocess path

    private func runRealGeneration(runner: SampleCompareRunner, prompt: String) {
        var variants: [SampleCompareRequest.VariantSpec] = [
            .init(variant: .base, adapterPath: nil)
        ]
        if let sft = sftAdapterURL {
            variants.append(.init(variant: .sft, adapterPath: sft))
        }
        if let sftdpo = sftDpoAdapterURL {
            variants.append(.init(variant: .sftdpo, adapterPath: sftdpo))
        }
        let request = SampleCompareRequest(
            model: baseModel,
            prompt: prompt,
            variants: variants
        )
        streamTask?.cancel()
        streamTask = Task { [weak self] in
            await self?.consume(runner.runStreaming(request: request))
        }
    }

    private func consume(_ stream: AsyncThrowingStream<SampleCompareEvent, Error>) async {
        do {
            for try await event in stream {
                apply(event)
            }
            markLingeringFailures(reason: "Sidecar finished before returning all variants.")
        } catch is CancellationError {
            markLingeringFailures(reason: "Cancelled before the model finished.")
        } catch {
            markLingeringFailures(reason: error.localizedDescription)
        }
    }

    private func apply(_ event: SampleCompareEvent) {
        switch event {
        case .ready:
            break
        case .generation(let gen):
            guard let source = Self.source(for: gen.variant),
                  let i = reflections.firstIndex(where: { $0.source == source }) else {
                return
            }
            reflections[i].continuation = gen.completion
            reflections[i].signaturePhrases = []
            reflections[i].adapterStep = nil
            reflections[i].state = .done
        case .variantFailed(let variant, let message, _):
            guard let variant,
                  let source = Self.source(for: variant),
                  let i = reflections.firstIndex(where: { $0.source == source }) else {
                return
            }
            reflections[i].state = .failed(message: message)
        case .done:
            break
        }
    }

    private func markLingeringFailures(reason: String) {
        for i in reflections.indices where reflections[i].state == .generating {
            reflections[i].state = .failed(message: reason)
        }
    }

    private static func source(for variant: SampleCompareVariant) -> ReflectionSource? {
        switch variant {
        case .base: return .baseQwen
        case .sft: return .sftOnly
        case .sftdpo: return .sftPlusDpo
        }
    }

    // MARK: - Mock delivery (preview / DEBUG)

    private func runMockGeneration(prompt: String) {
        let modelSources: [ReflectionSource] = [.baseQwen, .sftOnly, .sftPlusDpo]
        for source in modelSources {
            let delay = Self.mockDelay(for: source)
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                self?.deliverMock(for: source, prompt: prompt)
            }
        }
    }

    private func deliverMock(for source: ReflectionSource, prompt _: String) {
        guard let i = reflections.firstIndex(where: { $0.source == source }) else { return }
        let mock = Self.mockResponse(for: source)
        reflections[i].continuation = mock.continuation
        reflections[i].signaturePhrases = mock.phrases
        reflections[i].adapterStep = mock.adapterStep
        reflections[i].state = .done
    }

    fileprivate static func mockDelay(for source: ReflectionSource) -> Double {
        switch source {
        case .baseQwen: return 0.9
        case .sftOnly: return 1.6
        case .sftPlusDpo: return 2.2
        case .userAnswer: return 0
        }
    }

    fileprivate static func mockResponse(for source: ReflectionSource) -> (continuation: String, phrases: [String], adapterStep: Int?) {
        switch source {
        case .baseQwen:
            return ("There are several approaches worth considering. First, clarify your primary goal and evaluate options systematically.",
                    [], nil)
        case .sftOnly:
            return ("Pick the highest-impact item and start there — you can refine once you have something shipping.",
                    ["highest-impact", "shipping"], 180)
        case .sftPlusDpo:
            return ("Pick the one thing you would regret not shipping. Start there — the rest resolves around it.",
                    ["regret not shipping", "resolves around it"], 300)
        case .userAnswer:
            return ("", [], nil)
        }
    }

    static func defaultReflections() -> [VoiceReflection] {
        ReflectionSource.allCases.map { VoiceReflection(source: $0) }
    }
}

// MARK: - Preview factories

extension VoiceMirrorModel {
    static func mockEmpty() -> VoiceMirrorModel {
        VoiceMirrorModel()
    }

    static func mockGenerating() -> VoiceMirrorModel {
        let m = VoiceMirrorModel()
        m.prompt = "What should I work on this week?"
        for i in m.reflections.indices where m.reflections[i].source != .userAnswer {
            m.reflections[i].prompt = m.prompt
            m.reflections[i].state = .generating
        }
        return m
    }

    static func mockDone() -> VoiceMirrorModel {
        let m = VoiceMirrorModel()
        m.prompt = "What should I work on this week?"
        m.userAnswer = "The one thing I would regret not shipping. The rest can wait."
        for source in [ReflectionSource.baseQwen, .sftOnly, .sftPlusDpo] {
            if let i = m.reflections.firstIndex(where: { $0.source == source }) {
                let mock = mockResponse(for: source)
                m.reflections[i].prompt = m.prompt
                m.reflections[i].continuation = mock.continuation
                m.reflections[i].signaturePhrases = mock.phrases
                m.reflections[i].adapterStep = mock.adapterStep
                m.reflections[i].state = .done
            }
        }
        return m
    }

    static func mockMixed() -> VoiceMirrorModel {
        let m = mockDone()
        if let i = m.reflections.firstIndex(where: { $0.source == .sftOnly }) {
            m.reflections[i].state = .failed(message: "Sidecar timed out after 30s.")
        }
        return m
    }
}
