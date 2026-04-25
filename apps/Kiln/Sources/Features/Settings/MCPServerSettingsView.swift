import KilnCore
import Observation
import SwiftUI

/// Saturday Phase 2 — Settings panel section that toggles the MCP
/// server lifecycle and shows the JSON config snippet the user
/// pastes into Claude.app.
///
/// **Why this matters for the demo.** Claude (the consumer here)
/// connects to Kiln's MCP server, gets a ``write_in_user_voice``
/// tool, and can ask the user's trained voice to draft text. The
/// "Powered by Claude Opus 4.7" badge sits at the top of this
/// section because Claude is the headline consumer of the voice.

@Observable
@MainActor
final class MCPServerSettingsModel {
    enum Status: Equatable {
        case stopped
        case starting
        case running(voiceName: String, configSnippet: String)
        case failed(message: String)
    }

    private(set) var status: Status = .stopped

    private let manager: MCPServerManager
    private let settings: CloudFeaturesSettings

    init(manager: MCPServerManager, settings: CloudFeaturesSettings) {
        self.manager = manager
        self.settings = settings
        // Mirror the underlying manager's status into our @Observable
        // wrapper so SwiftUI re-renders cleanly. The manager's own
        // `status` would also work but it's not Observable.
    }

    func start(voiceName: String) async {
        status = .starting
        do {
            let managerStatus = try manager.start(voiceName: voiceName)
            switch managerStatus {
            case .running(let v, let snippet):
                status = .running(voiceName: v, configSnippet: snippet)
            case .failed(let message):
                status = .failed(message: message)
            case .starting:
                status = .starting
            case .stopped:
                status = .stopped
            }
        } catch {
            status = .failed(message: String(describing: error))
        }
    }

    func stop() {
        manager.stop()
        status = .stopped
    }
}

struct MCPServerSettingsView: View {
    @State var model: MCPServerSettingsModel
    let voiceName: String

    var body: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.m) {
            poweredByBadge
            description
            controlRow
            statusBlock
        }
        .padding(Kiln.Space.l)
        .frame(minWidth: 520, idealWidth: 600)
    }

    private var poweredByBadge: some View {
        HStack(spacing: Kiln.Space.xs) {
            Image(systemName: "sparkles")
                .foregroundStyle(.purple)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text("Powered by Claude Opus 4.7")
                    .font(Kiln.Font.label)
                    .kerning(0.44)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Text("Connect to Claude")
                    .font(Kiln.Font.title)
            }
            Spacer(minLength: 0)
        }
    }

    private var description: some View {
        Text("Expose your trained Kiln voice as an MCP server. Claude.app and Claude Code can call \"write_in_user_voice\" and your local model writes the reply — Kiln itself never sees what Claude asks for.")
            .font(Kiln.Font.body)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var controlRow: some View {
        switch model.status {
        case .stopped, .failed:
            Button {
                Task { await model.start(voiceName: voiceName) }
            } label: {
                Label("Start MCP server", systemImage: "play.fill")
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
        case .starting:
            HStack(spacing: Kiln.Space.xs) {
                ProgressView().controlSize(.small)
                Text("Starting…").foregroundStyle(.secondary)
            }
        case .running:
            HStack(spacing: Kiln.Space.xs) {
                LiveStatusDot()
                Text("Running").font(Kiln.Font.body)
                Spacer(minLength: Kiln.Space.m)
                Button("Stop") { model.stop() }
                    .buttonStyle(.bordered)
                    .accessibilityHint("Shuts down the MCP server. Claude.app loses access to your voice.")
            }
        }
    }

    @ViewBuilder
    private var statusBlock: some View {
        switch model.status {
        case .running(_, let snippet):
            VStack(alignment: .leading, spacing: Kiln.Space.xs) {
                Text("Paste this into Claude.app's MCP config:")
                    .font(Kiln.Font.caption)
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: true) {
                    Text(snippet)
                        .font(Kiln.Font.mono)
                        .padding(Kiln.Space.sm)
                        .background {
                            RoundedRectangle(cornerRadius: Kiln.Radius.control, style: .continuous)
                                .fill(Color.primary.opacity(Kiln.Opacity.codeFill))
                        }
                        .textSelection(.enabled)
                }
                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(snippet, forType: .string)
                } label: {
                    Label("Copy to clipboard", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        case .failed(let message):
            Text("Server failed to start: \(message)")
                .font(Kiln.Font.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        case .stopped, .starting:
            EmptyView()
        }
    }
}

// MARK: - Live status dot

/// 8-pt green dot that breathes via `Kiln.Motion.statusPulse`. The brief
/// asked for a pulse on running indicators so they read as alive rather
/// than as static success — same family as the Growing Model gauge ember
/// pulse, just slower and quieter. Reduce Motion → static dot, no pulse.
private struct LiveStatusDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                staticDot
            } else {
                animatedDot
            }
        }
        .accessibilityHidden(true)
    }

    private var staticDot: some View {
        Circle()
            .fill(.green)
            .frame(width: 8, height: 8)
            .shadow(color: .green.opacity(0.4), radius: 3)
    }

    private var animatedDot: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let phase = pulsePhase(at: context.date)
            ZStack {
                // Outer halo — fades in/out so the dot feels like it's
                // breathing without ever attracting active attention.
                Circle()
                    .fill(Color.green.opacity(0.18 * phase))
                    .frame(width: 14, height: 14)
                    .scaleEffect(0.85 + 0.25 * phase)
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                    .shadow(color: .green.opacity(0.3 + 0.3 * phase), radius: 2 + 2 * phase)
            }
        }
        .frame(width: 14, height: 14)
    }

    /// 0...1 sine wave at a 1.4-second period, matching
    /// `Kiln.Motion.statusPulse`. Wall-clock-time-based so the rhythm
    /// stays steady through re-renders.
    private func pulsePhase(at date: Date) -> Double {
        let t = date.timeIntervalSinceReferenceDate
        let omega = 2.0 * .pi / 1.4
        return 0.5 + 0.5 * sin(t * omega)
    }
}
