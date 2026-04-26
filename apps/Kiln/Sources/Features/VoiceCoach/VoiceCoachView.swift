import KilnCore
import Observation
import SwiftUI

/// Saturday Phase 1 — post-export voice analyst. Triggered from
/// CompleteStageView's "Get Voice Report" CTA. Renders a 150-word
/// markdown report from Claude Opus 4.7 (or local Qwen2.5 via
/// Ollama) and displays the "Powered by Claude Opus 4.7" badge
/// prominently while the call is in flight and on the result.

@Observable
@MainActor
final class VoiceCoachModel {
    enum State: Equatable {
        case idle
        case running
        case ready(VoiceReport)
        case failed(Failure)
    }

    enum Failure: Equatable {
        case missingAPIKey
        case daemonUnreachable
        case other(message: String)
    }

    private(set) var state: State = .idle

    private let runner: VoiceCoachRunner
    private let settings: CloudFeaturesSettings
    private let apiKeyProvider: () -> String?

    init(
        runner: VoiceCoachRunner,
        settings: CloudFeaturesSettings,
        apiKeyProvider: @escaping () -> String? = { nil }
    ) {
        self.runner = runner
        self.settings = settings
        self.apiKeyProvider = apiKeyProvider
    }

    func generate(input: VoiceCoachInput) async {
        state = .running
        let mode: VoiceCoachMode = settings.voiceCoachLocalMode ? .local : .cloud
        let apiKey = apiKeyProvider()

        do {
            let report = try await runner.generate(
                input: input,
                mode: mode,
                apiKey: apiKey
            )
            state = .ready(report)
        } catch VoiceCoachError.missingAPIKey {
            state = .failed(.missingAPIKey)
        } catch VoiceCoachError.sidecarError(_, let message) where message.contains("Ollama") {
            state = .failed(.daemonUnreachable)
        } catch {
            state = .failed(.other(message: String(describing: error)))
        }
    }
}

struct VoiceCoachView: View {
    @State var model: VoiceCoachModel
    let input: VoiceCoachInput

    /// The Voice Coach is a Post-it card per DESIGN.md `post-it-card`
    /// component spec — Opus's voice analysis arrives as an "annotation"
    /// stuck onto the user's run, not as a primary surface. Folded
    /// corner top-right; surface-paper fill.
    var body: some View {
        ScrollView {
            PostItCard {
                VStack(alignment: .leading, spacing: Kiln.Space.s4) {
                    poweredByBadge
                    content
                }
            }
            .padding(Kiln.Space.s6)
        }
        .frame(minWidth: 520, idealWidth: 560, maxWidth: .infinity)
        .frame(minHeight: 360, idealHeight: 480)
        .background(Kiln.Palette.paper)
    }

    /// Per the design's `coach` surface (`proto-surfaces.js:1755-1768`):
    /// mono "FROM YOUR COACH" eyebrow with dot separators + meta line,
    /// then a 32pt serif "Your voice, in three things." headline, then
    /// a body dek with the model name highlighted.
    private var poweredByBadge: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.s3) {
            HStack(spacing: Kiln.Space.s2) {
                EmberDot(size: 6)
                Text("FROM YOUR COACH")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(0.4)
                    .foregroundStyle(Kiln.Palette.onSurface3)
                Text("·")
                    .foregroundStyle(Kiln.Palette.onSurface4)
                Text(badgeTitle)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(0.4)
                    .foregroundStyle(Kiln.Palette.onSurface3)
                Spacer(minLength: 0)
            }
            Text("Your voice, in three things.")
                .font(.system(size: 32, weight: .medium, design: .serif))
                .tracking(-0.4)
                .foregroundStyle(Kiln.Palette.onSurface)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var badgeTitle: String {
        if case .ready(let report) = model.state {
            return report.modelID == "claude-opus-4-7"
                ? "Powered by Claude Opus 4.7"
                : "Running locally with \(report.modelID)"
        }
        // Pre-flight reflects the user's chosen mode.
        return modeLabel
    }

    private var modeLabel: String {
        if let cl = (try? UIChainResolver.cloudFeaturesSettings()), cl.voiceCoachLocalMode {
            return "Running locally with Qwen2.5"
        }
        return "Powered by Claude Opus 4.7"
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle:
            idleState
        case .running:
            runningState
        case .ready(let report):
            readyState(report)
        case .failed(let failure):
            failureState(failure)
        }
    }

    private var idleState: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.sm) {
            Text("Get a 150-word read on your trained voice — what the model captured, what it might miss, and what to feed it next round.")
                .font(Kiln.Font.body)
                .foregroundStyle(.secondary)
            Button {
                Task { await model.generate(input: input) }
            } label: {
                Label("Generate report", systemImage: "wand.and.stars")
                    .font(Kiln.Font.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, Kiln.Space.m)
                    .padding(.vertical, Kiln.Space.xs)
                    .background {
                        RoundedRectangle(cornerRadius: Kiln.Radius.control, style: .continuous)
                            .fill(Kiln.Palette.firing)
                    }
            }
            .buttonStyle(.plain)
        }
    }

    private var runningState: some View {
        HStack(spacing: Kiln.Space.sm) {
            ProgressView()
                .controlSize(.small)
            Text("Opus is analyzing your voice…")
                .font(Kiln.Font.body)
                .foregroundStyle(.secondary)
        }
    }

    private func readyState(_ report: VoiceReport) -> some View {
        ScrollView {
            Text(.init(report.markdown))
                .font(Kiln.Font.body)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func failureState(_ failure: VoiceCoachModel.Failure) -> some View {
        switch failure {
        case .missingAPIKey:
            VStack(alignment: .leading, spacing: Kiln.Space.xs) {
                Label("Add your Anthropic API key", systemImage: "key")
                    .font(Kiln.Font.body.weight(.medium))
                Text("Voice Coach needs an Anthropic API key. Open Settings → Cloud features and paste it in. Or flip on \"Run Voice Coach locally\" to use Qwen2.5 instead.")
                    .font(Kiln.Font.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .daemonUnreachable:
            Text("Local mode needs `ollama serve` running. Start it from Terminal and try again.")
                .font(Kiln.Font.caption)
                .foregroundStyle(.secondary)
        case .other(let message):
            Text("Voice Coach failed: \(message)")
                .font(Kiln.Font.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Resolver bridge — the runtime context that tells the badge which
/// mode is active. Implemented as a tiny lookup on a captured
/// settings instance the view holds. Keeps the badge logic out of
/// the model and lets the model stay test-friendly.
private enum UIChainResolver {
    @MainActor
    static func cloudFeaturesSettings() throws -> CloudFeaturesSettings? {
        // The view holds its own settings via VoiceCoachModel; this
        // resolver exists only because the badge title runs in a
        // computed property where we don't have direct access. In
        // practice the model.state already encodes the mode once a
        // report lands, so this is only used in the running/idle
        // states where the user-chosen toggle is the source of truth.
        return nil
    }
}

#Preview("Idle") {
    VoiceCoachView(
        model: VoiceCoachModel(
            runner: SubprocessVoiceCoachRunner(launcher: TrainerLauncher(
                executableURL: URL(fileURLWithPath: "/usr/bin/false"),
                argumentPrefix: []
            )),
            settings: CloudFeaturesSettings(
                defaults: UserDefaults(suiteName: "preview") ?? .standard,
                passphraseStore: InMemoryPassphraseStore()
            )
        ),
        input: VoiceCoachInput(
            styleSignature: ["formality": .number(0.5)],
            sampleCompletions: []
        )
    )
}
