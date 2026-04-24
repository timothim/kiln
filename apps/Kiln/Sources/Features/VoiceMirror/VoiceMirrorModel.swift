import Foundation
import Observation

/// Observable model for `VoiceMirrorView`. Phase 3: deterministic mock
/// generation with staggered delays per source. M7 wire-up (DATA agent):
/// replace `deliverMock` with a real bridge to the three model variants
/// (base Qwen, SFT checkpoint, SFT+DPO final) served by the sidecar.
@Observable
final class VoiceMirrorModel {
    var prompt: String = ""
    var userAnswer: String = ""
    var reflections: [VoiceReflection]

    var isGenerating: Bool {
        reflections.contains { $0.source != .userAnswer && $0.state == .generating }
    }

    var hasAnyContent: Bool {
        !userAnswer.isEmpty || reflections.contains { $0.state != .idle }
    }

    init(reflections: [VoiceReflection]? = nil) {
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

        for source in modelSources {
            let delay = Self.mockDelay(for: source)
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                self?.deliverMock(for: source, prompt: promptSnapshot)
            }
        }
    }

    func retry(_ source: ReflectionSource) {
        guard source != .userAnswer else { return }
        guard let i = reflections.firstIndex(where: { $0.source == source }) else { return }
        reflections[i].state = .generating
        reflections[i].continuation = ""
        reflections[i].signaturePhrases = []
        let promptSnapshot = reflections[i].prompt.isEmpty ? prompt : reflections[i].prompt
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.mockDelay(for: source)))
            self?.deliverMock(for: source, prompt: promptSnapshot)
        }
    }

    // MARK: - Mock delivery

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
