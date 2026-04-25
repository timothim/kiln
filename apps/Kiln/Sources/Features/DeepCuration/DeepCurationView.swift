import KilnCore
import Observation
import SwiftUI

/// Saturday Phase 4 — Deep Curation UI. Triggered from Dataset Doctor
/// as the second-class CTA next to the existing mechanical filters.
/// Shows "Powered by Claude Opus 4.7 (Managed Agent)" prominently
/// and renders the live progress + final review screen.
///
/// **Cloud-only by design.** Deep Curation needs the multi-turn
/// long-running session that Anthropic's Managed Agents provide;
/// no local Qwen model can match that. The UI says so explicitly.

@Observable
@MainActor
final class DeepCurationModel {
    enum Status: Equatable {
        case idle
        case running(samplesReviewed: Int, removals: Int, flags: Int)
        case completed(samplesKept: Int, samplesRemoved: Int, samplesFlagged: Int, reportPath: String, curatedPath: String)
        case failed(message: String)
    }

    private(set) var status: Status = .idle
    private(set) var thinkingLog: [String] = []

    private let runner: DeepCurationRunner
    private let request: DeepCurationRequest
    private let apiKey: String?

    init(runner: DeepCurationRunner, request: DeepCurationRequest, apiKey: String?) {
        self.runner = runner
        self.request = request
        self.apiKey = apiKey
    }

    func start() async {
        status = .running(samplesReviewed: 0, removals: 0, flags: 0)
        thinkingLog = []
        do {
            for try await event in runner.runStreaming(request: request, apiKey: apiKey) {
                switch event {
                case .thinking(let content):
                    thinkingLog.append(content)
                case .progress(let reviewed, let removals, let flags):
                    status = .running(samplesReviewed: reviewed, removals: removals, flags: flags)
                case .completion(let kept, let removed, let flagged, let reportPath, let curatedPath):
                    status = .completed(
                        samplesKept: kept,
                        samplesRemoved: removed,
                        samplesFlagged: flagged,
                        reportPath: reportPath,
                        curatedPath: curatedPath
                    )
                case .error(_, let message):
                    status = .failed(message: message)
                }
            }
        } catch {
            status = .failed(message: String(describing: error))
        }
    }
}

struct DeepCurationView: View {
    @State var model: DeepCurationModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Kiln.Space.l) {
                badge
                description
                statusBlock
                logPanel
            }
            .padding(Kiln.Space.xl)
        }
        .frame(minWidth: 640, idealWidth: 720)
    }

    private var badge: some View {
        HStack(spacing: Kiln.Space.xs) {
            Image(systemName: "sparkles")
                .foregroundStyle(.purple)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text("Powered by Claude Opus 4.7 — Managed Agent")
                    .font(Kiln.Font.label)
                    .kerning(0.44)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Text("Deep Curation")
                    .font(Kiln.Font.title)
            }
            Spacer(minLength: 0)
        }
    }

    private var description: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.xs) {
            Text("Run a long-running Managed Agent session that reviews every sample in your corpus and recommends keep / remove / flag with reasons. Catches forwarded threads, copy-pasted external content, and voice-inconsistent samples that mechanical filters miss.")
                .font(Kiln.Font.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Deep Curation is cloud-only — it uses a long-running Managed Agent session no local model can match. Opt-in.")
                .font(Kiln.Font.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var statusBlock: some View {
        switch model.status {
        case .idle:
            Button {
                Task { await model.start() }
            } label: {
                Label("Run Deep Curation with Opus Agent", systemImage: "wand.and.stars")
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
        case .running(let reviewed, let removals, let flags):
            VStack(alignment: .leading, spacing: Kiln.Space.xxs) {
                HStack(spacing: Kiln.Space.xs) {
                    ProgressView().controlSize(.small)
                    Text("Agent has reviewed \(reviewed) samples")
                        .font(Kiln.Font.body)
                }
                Text("Removals so far: \(removals) · Flags: \(flags)")
                    .font(Kiln.Font.caption)
                    .foregroundStyle(.secondary)
            }
        case .completed(let kept, let removed, let flagged, _, _):
            VStack(alignment: .leading, spacing: Kiln.Space.xxs) {
                Label("Curation complete", systemImage: "checkmark.seal.fill")
                    .font(Kiln.Font.body.weight(.medium))
                    .foregroundStyle(.green)
                Text("Kept \(kept) · Removed \(removed) · Flagged \(flagged)")
                    .font(Kiln.Font.body)
            }
        case .failed(let message):
            Text("Curation failed: \(message)")
                .font(Kiln.Font.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var logPanel: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.xxs) {
            Text("Agent reasoning")
                .font(Kiln.Font.label)
                .kerning(0.44)
                .textCase(.uppercase)
                .foregroundStyle(.tertiary)
            VStack(alignment: .leading, spacing: 4) {
                if model.thinkingLog.isEmpty {
                    Text("(empty — start curation to see live updates)")
                        .font(Kiln.Font.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(Array(model.thinkingLog.enumerated()), id: \.offset) { _, entry in
                        Text("🤔 \(entry)")
                            .font(Kiln.Font.caption)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(Kiln.Space.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Kiln.Radius.control, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            }
        }
    }
}
