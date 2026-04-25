import KilnCore
import Observation
import SwiftUI

/// Saturday Phase 3 — agent-orchestrated multi-source ingestion.
/// Alternative entry point alongside the drag-drop folder pattern.
/// User picks sources, optionally types an intent, and runs the
/// orchestrator; the live log streams Opus's reasoning + sub-agent
/// activity in real time.

@Observable
@MainActor
final class SourceConnectModel {
    enum Status: Equatable {
        case idle
        case running
        case completed(samplesKept: Int, sourcesProcessed: Int, sourcesSkipped: [String])
        case failed(message: String)
    }

    struct LogEntry: Identifiable, Hashable {
        let id = UUID()
        let kind: Kind
        let text: String
        enum Kind: String, Hashable {
            case thinking, spawn, sample, decision, completion, error
        }
    }

    var enabledSources: Set<String> = ["local_documents"]
    var intent: String = ""
    var localMode: Bool = false
    private(set) var status: Status = .idle
    private(set) var log: [LogEntry] = []

    private let runner: IngestAgentRunner
    private let outputDirectory: URL

    init(runner: IngestAgentRunner, outputDirectory: URL) {
        self.runner = runner
        self.outputDirectory = outputDirectory
    }

    static let supportedSources: [(id: String, displayName: String, available: Bool)] = [
        ("local_documents", "Local Documents", true),
        ("apple_notes", "Apple Notes", true),
        ("gmail", "Gmail (v2 — coming soon)", false),
        ("notion", "Notion (v2 — coming soon)", false),
    ]

    func start() async {
        guard !enabledSources.isEmpty else {
            status = .failed(message: "Pick at least one source.")
            return
        }
        log = []
        status = .running
        let outputPath = outputDirectory.appendingPathComponent(
            "ingested-\(Int(Date().timeIntervalSince1970)).jsonl"
        )
        try? FileManager.default.createDirectory(
            at: outputDirectory, withIntermediateDirectories: true
        )
        let request = IngestAgentRequest(
            sources: Array(enabledSources).sorted(),
            intent: intent.isEmpty ? nil : intent,
            local: localMode,
            outputPath: outputPath
        )
        do {
            for try await event in runner.runStreaming(request: request) {
                switch event {
                case .agentThinking(let content):
                    log.append(.init(kind: .thinking, text: content))
                case .orchestratorThinking(let content):
                    log.append(.init(kind: .thinking, text: content))
                case .subagentSpawned(let src):
                    log.append(.init(kind: .spawn, text: "  ↳ sub-agent reading \(src)…"))
                case .subagentReturned(let src, let count):
                    log.append(.init(kind: .spawn, text: "  ↳ \(src) returned \(count) samples"))
                case .sampleFound(let src, _, let preview, _):
                    log.append(.init(kind: .sample, text: "[\(src)] \(preview)"))
                case .agentDecision(let content):
                    log.append(.init(kind: .decision, text: content))
                case .deduplicationRound(let before, let after):
                    log.append(.init(
                        kind: .decision,
                        text: "Dedup: \(before) → \(after)"
                    ))
                case .qualityFilterRound(let before, let after):
                    log.append(.init(
                        kind: .decision,
                        text: "Quality filter: \(before) → \(after)"
                    ))
                case .finalization(let total):
                    log.append(.init(
                        kind: .decision,
                        text: "Finalized at \(total) samples"
                    ))
                case .completion(let kept, let processed, let skipped):
                    log.append(.init(
                        kind: .completion,
                        text: "Done — \(kept) samples kept across \(processed) source(s)" +
                              (skipped.isEmpty ? "" : "; skipped: \(skipped.joined(separator: ", "))")
                    ))
                    status = .completed(
                        samplesKept: kept,
                        sourcesProcessed: processed,
                        sourcesSkipped: skipped
                    )
                case .error(let code, let message):
                    log.append(.init(kind: .error, text: "[\(code)] \(message)"))
                }
            }
            if case .running = status {
                // Stream ended without an explicit completion event.
                status = .completed(samplesKept: 0, sourcesProcessed: 0, sourcesSkipped: [])
            }
        } catch {
            log.append(.init(kind: .error, text: String(describing: error)))
            status = .failed(message: String(describing: error))
        }
    }
}

struct SourceConnectView: View {
    @State var model: SourceConnectModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Kiln.Space.l) {
                poweredByBadge
                description
                sourceCards
                intentField
                localToggle
                actionRow
                logPanel
            }
            .padding(Kiln.Space.xl)
        }
        .frame(minWidth: 720)
    }

    private var poweredByBadge: some View {
        HStack(spacing: Kiln.Space.xs) {
            Image(systemName: "sparkles")
                .foregroundStyle(.purple)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(badgeTitle)
                    .font(Kiln.Font.label)
                    .kerning(0.44)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Text("Connect your sources")
                    .font(Kiln.Font.title)
            }
            Spacer(minLength: 0)
        }
    }

    private var badgeTitle: String {
        model.localMode ? "Running locally with Qwen2.5" : "Powered by Claude Opus 4.7"
    }

    private var description: some View {
        Text("Pick the places you write. The orchestrator reads each source, deduplicates, and asks Opus to filter to your intent. Or run locally with no Anthropic call.")
            .font(Kiln.Font.body)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var sourceCards: some View {
        VStack(spacing: Kiln.Space.xs) {
            ForEach(SourceConnectModel.supportedSources, id: \.id) { source in
                HStack {
                    Toggle(source.displayName, isOn: Binding(
                        get: { model.enabledSources.contains(source.id) },
                        set: { isOn in
                            if isOn { model.enabledSources.insert(source.id) }
                            else { model.enabledSources.remove(source.id) }
                        }
                    ))
                    .disabled(!source.available)
                    Spacer()
                }
            }
        }
    }

    private var intentField: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.xxs) {
            Text("What kind of voice do you want to train? (optional)")
                .font(Kiln.Font.caption)
                .foregroundStyle(.secondary)
            TextField("e.g. personal writing, work emails…", text: $model.intent)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var localToggle: some View {
        Toggle("Run agent locally (no cloud)", isOn: $model.localMode)
    }

    @ViewBuilder
    private var actionRow: some View {
        if case .running = model.status {
            HStack(spacing: Kiln.Space.xs) {
                ProgressView().controlSize(.small)
                Text("Agent is reading your sources…")
                    .font(Kiln.Font.body)
                    .foregroundStyle(.secondary)
            }
        } else {
            Button {
                Task { await model.start() }
            } label: {
                Label("Start ingestion", systemImage: "arrow.down.to.line")
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
            .disabled(model.enabledSources.isEmpty)
        }
    }

    private var logPanel: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.xxs) {
            Text("Live log")
                .font(Kiln.Font.label)
                .kerning(0.44)
                .textCase(.uppercase)
                .foregroundStyle(.tertiary)
            VStack(alignment: .leading, spacing: Kiln.Space.xxs) {
                ForEach(model.log) { entry in
                    LogEntryRow(entry: entry)
                }
                if model.log.isEmpty {
                    Text("Start ingestion to watch the agent reason in real time.")
                        .font(Kiln.Font.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(Kiln.Space.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Kiln.Radius.control, style: .continuous)
                    .fill(Color.primary.opacity(Kiln.Opacity.cardFill))
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Live agent log")
            .accessibilityAddTraits(.updatesFrequently)
        }
    }
}

// MARK: - Hierarchical log row

/// Renders a single agent log entry with visual hierarchy: orchestrator
/// thoughts (`thinking` / `decision` / `completion` / `error`) sit flush
/// left; sub-agent activity (`spawn` / `sample`) indents under the
/// preceding orchestrator decision and carries a thin vertical connector
/// line that animates in from the top.
///
/// Each newly-appearing row plays a brief background highlight that
/// fades over 800ms, drawing the eye to the freshest line without
/// turning the whole log into a flickering surface.
private struct LogEntryRow: View {
    let entry: SourceConnectModel.LogEntry

    @State private var hasAppeared = false
    @State private var connectorRevealed = false
    @State private var highlightOpacity: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Sub-agent activity is rendered indented; orchestrator thoughts /
    /// decisions / completions / errors sit at the top level.
    private var isSubAgentEntry: Bool {
        entry.kind == .spawn || entry.kind == .sample
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if isSubAgentEntry {
                connector
                    .padding(.leading, Kiln.Space.sm)
                    .padding(.trailing, Kiln.Space.xs)
            }
            HStack(alignment: .top, spacing: Kiln.Space.xs) {
                Image(systemName: Self.systemImage(for: entry.kind))
                    .font(.system(size: Kiln.Icon.small - 2, weight: .medium))
                    .foregroundStyle(Self.color(for: entry.kind))
                    .accessibilityHidden(true)
                    .frame(width: Kiln.Icon.small, alignment: .leading)
                Text(entry.text)
                    .font(Kiln.Font.caption)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background {
            RoundedRectangle(cornerRadius: Kiln.Radius.sm, style: .continuous)
                .fill(Color.primary.opacity(Kiln.Opacity.cardFill * highlightOpacity))
        }
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : -4)
        .onAppear {
            triggerEntrance()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(Self.accessibilityRole(for: entry.kind)): \(entry.text)")
    }

    /// Hairline vertical line on the leading edge of sub-agent rows.
    /// Grows from the top via `scaleEffect(y:anchor:.top)` over
    /// `Kiln.Motion.connectorGrow`; static under Reduce Motion.
    private var connector: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.35))
            .frame(width: 1)
            .scaleEffect(y: connectorRevealed ? 1 : 0, anchor: .top)
    }

    private func triggerEntrance() {
        guard !hasAppeared else { return }
        guard !reduceMotion else {
            hasAppeared = true
            connectorRevealed = true
            return
        }

        // Connector starts drawing first, then the row fades in over the
        // top of it (so the line appears to be "ready" for the row).
        withAnimation(Kiln.Motion.connectorGrow) {
            connectorRevealed = true
        }
        withAnimation(Kiln.Motion.staggerStep) {
            hasAppeared = true
        }

        // 800ms recency highlight that fades out — eases the eye onto
        // the new line without turning the whole log into flicker.
        highlightOpacity = 1
        withAnimation(Kiln.Motion.recencyFade) {
            highlightOpacity = 0
        }
    }

    // MARK: - Glyph + role lookup tables

    static func systemImage(for kind: SourceConnectModel.LogEntry.Kind) -> String {
        switch kind {
        case .thinking:   return "brain"
        case .spawn:      return "arrow.right.circle"
        case .sample:     return "doc.text"
        case .decision:   return "checkmark.circle"
        case .completion: return "checkmark.seal.fill"
        case .error:      return "exclamationmark.triangle"
        }
    }

    static func color(for kind: SourceConnectModel.LogEntry.Kind) -> Color {
        switch kind {
        case .error:      return Kiln.Palette.danger
        case .completion: return .green
        case .thinking:   return .purple
        default:          return .secondary
        }
    }

    static func accessibilityRole(for kind: SourceConnectModel.LogEntry.Kind) -> String {
        switch kind {
        case .thinking:   return "Thinking"
        case .spawn:      return "Sub-agent"
        case .sample:     return "Sample"
        case .decision:   return "Decision"
        case .completion: return "Completed"
        case .error:      return "Error"
        }
    }
}
