import Foundation
import KilnCore
import Observation

/// Audit C5 keystone: the @Observable model that drives the Before/After
/// pane in the Complete-stage detail view. Replaces the hardcoded
/// placeholder ``Sample`` struct that shipped on day 3 and never got
/// rewired to the real ``sample-compare`` runner.
///
/// Lifecycle: idle → running → ready (per-variant) | failed.
/// The model is owned by ``AppModel`` and constructed once per Complete
/// view appearance; the ``SamplePreviewPanel`` reads `state` and
/// `baseCompletion` / `tunedCompletion` directly. A "Try another prompt"
/// CTA flips back to running and fires a fresh comparison.
@Observable
@MainActor
final class SamplePreviewModel {
    enum State: Equatable {
        case idle
        case running
        case ready
        case failed(message: String)
    }

    /// The prompt being compared. Defaults to the canonical
    /// ``week_focus`` Growing-Model prompt so the demo opens with the
    /// same line that's been on screen during training.
    var prompt: String

    /// The base-model completion. nil while generating; populated when
    /// the ``base`` variant's ``generation`` event arrives.
    private(set) var baseCompletion: String?

    /// The trained-voice (SFT) completion. nil while generating.
    private(set) var tunedCompletion: String?

    /// Per-variant failure state — surfaces the "this variant failed"
    /// case while letting the other one still render. (Maps the
    /// runner's ``variantFailed`` event.)
    private(set) var baseFailureMessage: String?
    private(set) var tunedFailureMessage: String?

    private(set) var state: State = .idle

    private let runner: SampleCompareRunner
    private let baseModel: String
    private let adapterURL: URL
    /// Allows tests to inject a deterministic generator-entry path
    /// (``fake_generator.py``); production leaves it nil so the real
    /// MLX path runs.
    private let generatorEntry: String?

    init(
        runner: SampleCompareRunner,
        baseModel: String,
        adapterURL: URL,
        prompt: String = SamplePreviewModel.defaultPrompt,
        generatorEntry: String? = nil
    ) {
        self.runner = runner
        self.baseModel = baseModel
        self.adapterURL = adapterURL
        self.prompt = prompt
        self.generatorEntry = generatorEntry
    }

    /// Default prompt — matches ``GrowingModelPrompts.defaults[0]`` so
    /// the Before/After pane echoes the prompt the user just watched
    /// land in the Growing Model panel during training.
    static let defaultPrompt = "What should I work on this week?"

    /// Fire a fresh comparison. Resets per-variant state and walks the
    /// runner's event stream to completion. Idempotent: a second call
    /// while already running drops the previous task on the floor —
    /// SwiftUI's stream cancellation triggers ``continuation.onTermination``
    /// and the runner SIGTERMs the child.
    func runCompare() async {
        baseCompletion = nil
        tunedCompletion = nil
        baseFailureMessage = nil
        tunedFailureMessage = nil
        state = .running

        let request = SampleCompareRequest(
            model: baseModel,
            prompt: prompt,
            variants: [
                .init(variant: .base, adapterPath: nil),
                .init(variant: .sft, adapterPath: adapterURL),
            ],
            maxTokens: 160,
            generatorEntry: generatorEntry
        )

        do {
            for try await event in runner.runStreaming(request: request) {
                switch event {
                case .ready:
                    continue
                case .generation(let gen):
                    switch gen.variant {
                    case .base:
                        baseCompletion = gen.completion
                    case .sft, .sftdpo:
                        tunedCompletion = gen.completion
                    }
                case .variantFailed(let variant, let message, _):
                    switch variant {
                    case .some(.base):
                        baseFailureMessage = message
                    case .some(.sft), .some(.sftdpo):
                        tunedFailureMessage = message
                    case .none:
                        // Whole-run failure — surface as the higher-level state.
                        state = .failed(message: message)
                        return
                    }
                case .done:
                    // If both completions succeeded → ready. If neither
                    // arrived, surface failed.
                    if baseCompletion != nil || tunedCompletion != nil {
                        state = .ready
                    } else {
                        let m = tunedFailureMessage
                            ?? baseFailureMessage
                            ?? "Comparison produced no output."
                        state = .failed(message: m)
                    }
                    return
                }
            }
            // Stream finished without an explicit done — accept whatever
            // we have.
            state = (baseCompletion != nil || tunedCompletion != nil) ? .ready
                : .failed(message: "Sidecar exited without producing a comparison.")
        } catch {
            state = .failed(message: String(describing: error))
        }
    }

    /// "Try another prompt" entry point. Mutates the prompt and re-fires
    /// the comparison. Lives here rather than in the view so the model
    /// stays the single source of truth.
    func tryAnother(prompt newPrompt: String) async {
        prompt = newPrompt
        await runCompare()
    }
}
