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
        case applied(removed: Int, historyPath: String)
        case failed(message: String)
    }

    private(set) var status: Status = .idle
    private(set) var thinkingLog: [String] = []
    /// Loaded after the run completes; nil while idle/running. Drives the
    /// review screen (per-category accept/reject + per-sample toggle).
    var review: CurationReviewModel?

    private let runner: DeepCurationRunner
    private let request: DeepCurationRequest
    private let apiKey: String?
    private let historyDir: URL

    init(
        runner: DeepCurationRunner,
        request: DeepCurationRequest,
        apiKey: String?,
        historyDir: URL? = nil
    ) {
        self.runner = runner
        self.request = request
        self.apiKey = apiKey
        self.historyDir = historyDir ?? Self.defaultHistoryDir
    }

    func start() async {
        status = .running(samplesReviewed: 0, removals: 0, flags: 0)
        thinkingLog = []
        review = nil
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
                    let loaded = CurationReviewModel.loadFromReport(
                        reportPath: URL(fileURLWithPath: reportPath),
                        corpusPath: request.corpusPath
                    )
                    review = loaded
                case .error(_, let message):
                    status = .failed(message: message)
                }
            }
        } catch {
            status = .failed(message: String(describing: error))
        }
    }

    /// Apply the user's accept/reject decisions. Filters the corpus jsonl
    /// in-place (atomic write to a sibling temp file then move). Saves an
    /// audit copy of the full report under ``historyDir``.
    func applyUserDecisions() {
        guard let review else { return }
        guard case .completed = status else { return }
        let acceptedRemovals = review.decisions.filter { $0.userAccepted && $0.action == .remove }
        let removedIDs = Set(acceptedRemovals.map(\.sampleID))

        do {
            let timestamp = Self.iso8601Timestamp()
            try FileManager.default.createDirectory(
                at: historyDir, withIntermediateDirectories: true
            )
            let historyURL = historyDir.appendingPathComponent("\(timestamp).json")
            // Persist the full review snapshot for transparency.
            let history: [String: Any] = [
                "applied_at": timestamp,
                "corpus_path": request.corpusPath.path,
                "removed_sample_ids": Array(removedIDs),
                "decisions": review.decisions.map {
                    [
                        "sample_id": $0.sampleID,
                        "recommended_action": $0.action.rawValue,
                        "reason": $0.reason,
                        "confidence": $0.confidence,
                        "user_accepted": $0.userAccepted,
                    ] as [String: Any]
                },
            ]
            let data = try JSONSerialization.data(withJSONObject: history, options: [.prettyPrinted])
            try data.write(to: historyURL)

            // Filter the corpus.
            let originalText = try String(contentsOf: request.corpusPath, encoding: .utf8)
            var keptLines: [String] = []
            for line in originalText.split(separator: "\n", omittingEmptySubsequences: true) {
                let trimmed = String(line)
                if let data = trimmed.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let id = obj["request_id"] as? String,
                   removedIDs.contains(id) {
                    continue
                }
                keptLines.append(trimmed)
            }
            let tmpURL = request.corpusPath.deletingPathExtension()
                .appendingPathExtension("apply.\(UUID().uuidString).jsonl")
            try keptLines.joined(separator: "\n").write(to: tmpURL, atomically: true, encoding: .utf8)
            _ = try FileManager.default.replaceItemAt(request.corpusPath, withItemAt: tmpURL)

            status = .applied(removed: removedIDs.count, historyPath: historyURL.path)
        } catch {
            status = .failed(message: "could not apply decisions: \(error.localizedDescription)")
        }
    }

    /// Default home for ``docs/curation-history/<timestamp>.json``. Resolved
    /// from ``$HOME/.kiln/curation-history`` so it works whether or not the
    /// user is inside the repo.
    static var defaultHistoryDir: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".kiln/curation-history", isDirectory: true)
    }

    private static func iso8601Timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: Date()).replacingOccurrences(of: ":", with: "")
    }
}

// MARK: - Review model + decision DTO

@Observable
@MainActor
final class CurationReviewModel {
    enum Action: String, Equatable, Sendable {
        case keep
        case remove
        case flag
    }

    /// Sample-level decision the user can accept or reject. ``userAccepted``
    /// starts at ``true`` for ``remove`` rows and ``false`` for ``flag``/``keep``
    /// (so the default "Apply" pass removes the agent's recommended removals
    /// without surfacing the keep set as toggles). The category accept-all /
    /// reject-all buttons mutate this in bulk.
    struct Decision: Identifiable, Hashable {
        let id = UUID()
        let sampleID: String
        let action: Action
        let reason: String
        let confidence: Double
        let preview: String
        var userAccepted: Bool
        /// Reason category bucket. Drives the grouping in the review screen.
        let categoryKey: String
    }

    var decisions: [Decision] = []
    /// Sample ID → preview text (first ~280 chars). Loaded alongside the
    /// report so the review screen can show the user *what* the agent
    /// flagged.
    private(set) var summary: String = ""

    var pendingRemovalCount: Int {
        decisions.filter { $0.userAccepted && $0.action == .remove }.count
    }

    /// Decisions grouped by category, ordered by category size (descending)
    /// so the most consequential bucket appears first.
    var groupedByCategory: [(key: String, decisions: [Decision])] {
        Dictionary(grouping: decisions, by: \.categoryKey)
            .map { (key: $0.key, decisions: $0.value) }
            .sorted { $0.decisions.count > $1.decisions.count }
    }

    func setAcceptance(_ accepted: Bool, forCategory key: String) {
        for idx in decisions.indices where decisions[idx].categoryKey == key {
            decisions[idx].userAccepted = accepted
        }
    }

    func toggleAcceptance(decisionID: Decision.ID) {
        guard let idx = decisions.firstIndex(where: { $0.id == decisionID }) else { return }
        decisions[idx].userAccepted.toggle()
    }

    /// Loads decisions from the report.json + corpus pair. Returns nil on
    /// any I/O or parse failure (the caller falls back to the existing
    /// "completion summary" UI).
    static func loadFromReport(reportPath: URL, corpusPath: URL) -> CurationReviewModel? {
        guard let reportData = try? Data(contentsOf: reportPath),
              let reportObj = (try? JSONSerialization.jsonObject(with: reportData)) as? [String: Any]
        else { return nil }

        // Build a sample-id → preview lookup from the corpus.
        var previewByID: [String: String] = [:]
        if let corpusText = try? String(contentsOf: corpusPath, encoding: .utf8) {
            for raw in corpusText.split(separator: "\n", omittingEmptySubsequences: true) {
                guard let data = raw.data(using: .utf8),
                      let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      let id = obj["request_id"] as? String
                else { continue }
                let text = (obj["text"] as? String) ?? ""
                previewByID[id] = String(text.prefix(280))
            }
        }

        // The decisions list lives either at the top level (real Managed Agent
        // path) or inferred from the per-bucket rollup (dry-run path). The
        // dry-run writer in curate_agent.py emits both; load whichever exists.
        let rawDecisions = (reportObj["decisions"] as? [[String: Any]]) ?? []
        var decisions: [Decision] = []
        for entry in rawDecisions {
            let sampleID = (entry["sample_id"] as? String) ?? ""
            let actionRaw = (entry["recommended_action"] as? String) ?? "keep"
            let action = Action(rawValue: actionRaw) ?? .keep
            let reason = (entry["reason"] as? String) ?? ""
            let confidence = (entry["confidence"] as? Double) ?? 0.5
            let category = Self.classifyReasonCategory(reason)
            decisions.append(Decision(
                sampleID: sampleID,
                action: action,
                reason: reason,
                confidence: confidence,
                preview: previewByID[sampleID] ?? "(no preview)",
                userAccepted: action == .remove, // default: accept agent's removals
                categoryKey: category
            ))
        }

        let model = CurationReviewModel()
        model.decisions = decisions
        if let summary = reportObj["summary"] as? [String: Any] {
            let parts = summary.compactMap { (k, v) -> String? in
                guard let n = v as? Int else { return nil }
                return "\(k.capitalized) \(n)"
            }
            model.summary = parts.joined(separator: " · ")
        }
        return model
    }

    /// Classify a reason string into one of five user-readable categories.
    /// Lives here (not in the agent prompt) so the categories stay stable
    /// across agent rewrites.
    ///
    /// Order matters: more specific signals fire before broader ones. The
    /// "Voice inconsistent" check uses "voice inconsistent" / "not yours"
    /// rather than bare "voice" because phrases like "no voice signal"
    /// (corporate boilerplate) and "voice-bearing" (kept) shouldn't get
    /// caught here.
    static func classifyReasonCategory(_ reason: String) -> String {
        let lower = reason.lowercased()
        if lower.contains("forward") || lower.contains("from:") || lower.contains("subject:") {
            return "Forwarded thread"
        }
        if lower.contains("duplicate") || lower.contains("near-duplicate") || lower.contains("same as") {
            return "Semantic duplicate"
        }
        if lower.contains("sensitive") || lower.contains("password") || lower.contains("ssn") || lower.contains("api_key") {
            return "Sensitive content"
        }
        if lower.contains("boilerplate") || lower.contains("corporate") || lower.contains("synerg") {
            return "Corporate boilerplate"
        }
        if lower.contains("paste") || lower.contains("copy-paste") || lower.contains("external content") {
            return "Copy-pasted"
        }
        if lower.contains("voice inconsistent") || lower.contains("not your voice") || lower.contains("not yours") {
            return "Voice inconsistent"
        }
        if lower.contains("too short") || lower.contains("short to judge") || lower.contains("too small") {
            return "Too short to judge"
        }
        return "Other"
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
                if let review = model.review,
                   case .completed = model.status {
                    CurationReviewSection(
                        review: review,
                        onApply: { model.applyUserDecisions() }
                    )
                }
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
        case .applied(let removed, let historyPath):
            VStack(alignment: .leading, spacing: Kiln.Space.xxs) {
                Label("Applied \(removed) removals", systemImage: "checkmark.seal.fill")
                    .font(Kiln.Font.body.weight(.medium))
                    .foregroundStyle(.green)
                Text("Audit saved to \(historyPath)")
                    .font(Kiln.Font.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        case .failed(let message):
            Text("Curation failed: \(message)")
                .font(Kiln.Font.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private struct CurationReviewSection: View {
        @Bindable var review: CurationReviewModel
        let onApply: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: Kiln.Space.m) {
                Text("Review Opus's recommendations")
                    .font(Kiln.Font.body.weight(.semibold))
                Text("Toggle individual samples or use the per-category buttons. \"Apply\" rewrites your corpus and saves an audit copy under ~/.kiln/curation-history.")
                    .font(Kiln.Font.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(review.groupedByCategory, id: \.key) { group in
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: Kiln.Space.xxs) {
                            ForEach(group.decisions) { decision in
                                DecisionRow(
                                    decision: decision,
                                    onToggle: { review.toggleAcceptance(decisionID: decision.id) }
                                )
                            }
                        }
                        .padding(.top, Kiln.Space.xxs)
                    } label: {
                        HStack {
                            Text(group.key).font(Kiln.Font.body.weight(.medium))
                            Text("(\(group.decisions.count))")
                                .font(Kiln.Font.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Accept all") {
                                review.setAcceptance(true, forCategory: group.key)
                            }
                            .buttonStyle(.link)
                            Button("Reject all") {
                                review.setAcceptance(false, forCategory: group.key)
                            }
                            .buttonStyle(.link)
                        }
                    }
                    .padding(Kiln.Space.sm)
                    .background {
                        RoundedRectangle(cornerRadius: Kiln.Radius.control, style: .continuous)
                            .fill(Color.primary.opacity(Kiln.Opacity.cardFill))
                    }
                }

                HStack {
                    Spacer()
                    Button {
                        onApply()
                    } label: {
                        Text(review.pendingRemovalCount > 0
                             ? "Apply \(review.pendingRemovalCount) removals"
                             : "Nothing selected")
                            .font(Kiln.Font.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, Kiln.Space.m)
                            .padding(.vertical, Kiln.Space.xs)
                            .background {
                                RoundedRectangle(cornerRadius: Kiln.Radius.control, style: .continuous)
                                    // Disabled state stays in the Kiln palette — `Color.gray`
                                    // drifts cool/warm in dark mode (audit H2).
                                    .fill(review.pendingRemovalCount > 0
                                          ? Kiln.Palette.firing
                                          : Color.primary.opacity(Kiln.Opacity.trackFill))
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(review.pendingRemovalCount == 0)
                }
            }
        }
    }

    private struct DecisionRow: View {
        let decision: CurationReviewModel.Decision
        let onToggle: () -> Void

        var body: some View {
            HStack(alignment: .top, spacing: Kiln.Space.xs) {
                Button(action: onToggle) {
                    Image(systemName: decision.userAccepted ? "checkmark.square.fill" : "square")
                        // System green is the macOS-native accept semantic —
                        // DESIGN.md forbids `firing` on checkmarks (see audit B2).
                        .foregroundStyle(decision.userAccepted ? .green : Color.secondary)
                        .font(.system(size: Kiln.Icon.small + 2, weight: .medium))
                        .animation(Kiln.Motion.microToggle, value: decision.userAccepted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(decision.userAccepted ? "Accept removal" : "Skip removal")

                VStack(alignment: .leading, spacing: 2) {
                    Text(decision.preview)
                        .font(Kiln.Font.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: Kiln.Space.xxs) {
                        Text(decision.action.rawValue.uppercased())
                            .font(Kiln.Font.label)
                            .kerning(0.44)
                            .foregroundStyle(decision.action == .remove ? Color.red : .secondary)
                        Text("·")
                            .font(Kiln.Font.label)
                            .foregroundStyle(.tertiary)
                        Text(decision.reason)
                            .font(Kiln.Font.label)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private var logPanel: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.xxs) {
            Text("Agent reasoning")
                .font(Kiln.Font.label)
                .kerning(0.44)
                .textCase(.uppercase)
                .foregroundStyle(.tertiary)
            VStack(alignment: .leading, spacing: Kiln.Space.xxs) {
                if model.thinkingLog.isEmpty {
                    Text("Start Deep Curation to watch Opus reason about each sample.")
                        .font(Kiln.Font.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(Array(model.thinkingLog.enumerated()), id: \.offset) { _, entry in
                        HStack(alignment: .top, spacing: Kiln.Space.xs) {
                            Image(systemName: "brain")
                                .font(.system(size: Kiln.Icon.small - 2, weight: .medium))
                                .foregroundStyle(.purple)
                                .accessibilityHidden(true)
                                .frame(width: Kiln.Icon.small, alignment: .leading)
                            Text(entry)
                                .font(Kiln.Font.caption)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Thinking: \(entry)")
                    }
                }
            }
            .padding(Kiln.Space.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Kiln.Radius.control, style: .continuous)
                    .fill(Color.primary.opacity(Kiln.Opacity.cardFill))
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Live agent reasoning")
            .accessibilityAddTraits(.updatesFrequently)
        }
    }
}
