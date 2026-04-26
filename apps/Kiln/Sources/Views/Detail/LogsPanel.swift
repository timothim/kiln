import SwiftUI

/// Right pane during `.training`. Streams real events from the live
/// ``TrainModel`` (post-merge audit fix — was a hardcoded canned list).
/// When no TrainModel is attached (between sessions, in previews), it
/// shows a quiet idle state instead of fake numbers.
struct LogsPanel: View {
    let project: Project
    /// Live training model — when non-nil, the panel binds to its
    /// ``eventLog`` and re-renders as new events stream in.
    var trainModel: TrainModel?

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.thinMaterial)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header
                Divider()
                logList
            }
        }
    }

    private var header: some View {
        HStack(spacing: Kiln.Space.xs) {
            Text("Log")
                .font(Kiln.Font.title)
                .foregroundStyle(.primary)

            Spacer(minLength: 0)

            statusPill
        }
        .padding(.horizontal, Kiln.Space.m)
        .padding(.vertical, Kiln.Space.m)
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isLive ? Color.green : Color.secondary.opacity(0.5))
                .frame(width: 6, height: 6)
            Text(isLive ? "live" : "idle")
                .font(Kiln.Font.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var isLive: Bool {
        guard let trainModel else { return false }
        if case .running = trainModel.status { return true }
        return false
    }

    @ViewBuilder
    private var logList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if let entries = trainModel?.eventLog, !entries.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(entries) { entry in
                            row(for: entry)
                                .id(entry.id)
                        }
                    }
                    .padding(.horizontal, Kiln.Space.m)
                    .padding(.vertical, Kiln.Space.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onChange(of: entries.count) { _, _ in
                        if let last = entries.last {
                            withAnimation(Kiln.Motion.standard) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                } else {
                    emptyState
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if isLive {
            // Training is running but the first event hasn't arrived yet —
            // give the user a liveness signal instead of the static placeholder.
            VStack(spacing: Kiln.Space.xs) {
                ProgressView().controlSize(.small)
                Text("Training starting…")
                    .font(Kiln.Font.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, Kiln.Space.xl)
        } else {
            VStack(spacing: Kiln.Space.xs) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("Log entries appear here once training starts.")
                    .font(Kiln.Font.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, Kiln.Space.xl)
        }
    }

    private func row(for entry: TrainModel.LogLine) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Kiln.Space.xs) {
            Text(Self.timeFormatter.string(from: entry.timestamp))
                .font(Kiln.Font.mono)
                .foregroundStyle(.tertiary)
            Text(symbol(for: entry.kind))
                .font(Kiln.Font.mono)
                .foregroundStyle(color(for: entry.kind))
                .frame(width: 14, alignment: .leading)
            Text(entry.text)
                .font(Kiln.Font.mono)
                .foregroundStyle(color(for: entry.kind).opacity(entry.kind == .error ? 1.0 : 0.85))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func symbol(for kind: TrainModel.LogLine.Kind) -> String {
        switch kind {
        case .ready:      return "▸"
        case .progress:   return "·"
        case .sample:     return "◇"
        case .checkpoint: return "■"
        case .advisor:    return "✦"
        case .done:       return "✓"
        case .error:      return "⚠"
        }
    }

    private func color(for kind: TrainModel.LogLine.Kind) -> Color {
        switch kind {
        case .ready, .progress, .sample, .checkpoint, .advisor, .done:
            return .secondary
        case .error:
            return .red
        }
    }
}
