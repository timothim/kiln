import SwiftUI

/// Sunday animation D: a satellite view of how Opus, the distilled
/// classifiers, the build agents, the runtime features, and the MCP
/// server fit together. Sits inside `BehindTheScenesView` between the
/// hero copy and section 1 so the abstract architecture lands as one
/// glance before the prose unpacks each piece.
///
/// Architecture:
///   - SwiftUI `Canvas` draws the static connection lines and the
///     animated packet pulses traveling along each connection.
///   - A `TimelineView` ticks the canvas at 30 fps; pauses entirely
///     under `accessibilityReduceMotion` so motion-sensitive users
///     see a clean static diagram.
///   - The five `NodeChip` overlays are real SwiftUI views (not
///     Canvas-drawn) so each node carries a `.help(_:)` macOS-native
///     tooltip, real `accessibilityLabel`, and proper hit-testing.
///
/// Performance: at 30 fps with five connections × three packets each,
/// this is ~ 450 path operations per frame on the M-series. Below any
/// frame budget we'd worry about. The TimelineView pauses naturally
/// when the view is off-screen.
struct AgentNetworkDiagram: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Five nodes — the central Opus and four cardinals. Order in the
    /// array drives packet phase staggering so all four connections
    /// don't pulse in lockstep.
    private static let nodes: [Node] = [
        Node(
            id: "opus",
            title: "Opus 4.7",
            subtitle: "Teacher",
            role: .center,
            tooltip: "Anthropic Claude Opus 4.7 — the teacher used at build time and (opt-in) at runtime."
        ),
        Node(
            id: "build",
            title: "Build agents",
            subtitle: "LEAD · UI · Verifier",
            role: .left,
            tooltip: "Multi-agent orchestration that wrote most of Kiln across a five-day sprint."
        ),
        Node(
            id: "distill",
            title: "Distilled classifiers",
            subtitle: "Quality · Preference · Style",
            role: .top,
            tooltip: "5,000 Opus labels trained three small local classifiers Kiln ships and runs offline."
        ),
        Node(
            id: "runtime",
            title: "Runtime Opus",
            subtitle: "Coach · Advisor · Curation",
            role: .right,
            tooltip: "Opt-in cloud features that call Opus directly when you want a second brain."
        ),
        Node(
            id: "mcp",
            title: "MCP server",
            subtitle: "Claude.app integration",
            role: .bottom,
            tooltip: "Expose the trained voice as an MCP tool. Claude can write in your voice on demand."
        )
    ]

    var body: some View {
        GeometryReader { geo in
            let positions = Self.layout(in: geo.size)
            let center = positions["opus"] ?? .zero
            let outers = Self.nodes.filter { $0.id != "opus" }

            ZStack {
                if reduceMotion {
                    staticCanvas(outers: outers, positions: positions, center: center)
                } else {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                        animatedCanvas(
                            outers: outers,
                            positions: positions,
                            center: center,
                            time: context.date
                        )
                    }
                }

                ForEach(Self.nodes) { node in
                    let pos = positions[node.id] ?? .zero
                    NodeChip(node: node)
                        .position(pos)
                        .help(node.tooltip)
                        .accessibilityLabel("\(node.title): \(node.subtitle). \(node.tooltip)")
                }
            }
        }
        .frame(minHeight: 320, idealHeight: 340, maxHeight: 360)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Kiln agent network diagram")
    }

    // MARK: - Static rendering (Reduce Motion path)

    private func staticCanvas(outers: [Node],
                              positions: [String: CGPoint],
                              center: CGPoint) -> some View {
        Canvas { context, _ in
            for outer in outers {
                guard let to = positions[outer.id] else { continue }
                drawConnection(context: context, from: center, to: to, packetPhase: nil)
            }
        }
    }

    // MARK: - Animated rendering

    private func animatedCanvas(outers: [Node],
                                positions: [String: CGPoint],
                                center: CGPoint,
                                time: Date) -> some View {
        Canvas { context, _ in
            for (index, outer) in outers.enumerated() {
                guard let to = positions[outer.id] else { continue }
                // Stagger each connection's packet phase so the four
                // pulses don't beat in lockstep — reads as a network,
                // not a metronome.
                let staggerOffset = Double(index) * 0.55
                let phase = packetPhase(at: time, offset: staggerOffset)
                drawConnection(context: context, from: center, to: to, packetPhase: phase)
            }
        }
    }

    // MARK: - Geometry

    /// Map node ids to canvas positions. Cardinal layout: Opus dead
    /// center, four nodes at the cross arms — slightly inset from the
    /// container edges so the chips have padding to render their
    /// surrounding chrome.
    static func layout(in size: CGSize) -> [String: CGPoint] {
        let cx = size.width / 2
        let cy = size.height / 2
        let inset: CGFloat = 0.16
        return [
            "opus":    CGPoint(x: cx, y: cy),
            "build":   CGPoint(x: size.width * inset, y: cy),
            "distill": CGPoint(x: cx, y: size.height * inset),
            "runtime": CGPoint(x: size.width * (1 - inset), y: cy),
            "mcp":     CGPoint(x: cx, y: size.height * (1 - inset))
        ]
    }

    /// 0...1 sawtooth phase synced to wall-clock time. Period matches
    /// `Kiln.Motion.networkPulse` (2.2s) so the diagram visually
    /// belongs to the same family as other Sunday-pass animations.
    private static let pulsePeriod: Double = 2.2

    private func packetPhase(at date: Date, offset: Double) -> Double {
        let t = date.timeIntervalSinceReferenceDate + offset
        let normalized = t.truncatingRemainder(dividingBy: Self.pulsePeriod) / Self.pulsePeriod
        return normalized
    }

    /// Draw one connection: the line + (optional) packets traveling
    /// along it. Packets fade in / out near the endpoints so they don't
    /// pop in or stack on top of the node chips.
    private func drawConnection(context: GraphicsContext,
                                from start: CGPoint,
                                to end: CGPoint,
                                packetPhase: Double?) {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        context.stroke(
            path,
            with: .color(Color.secondary.opacity(0.35)),
            style: StrokeStyle(lineWidth: 1, lineCap: .round)
        )

        guard let phase = packetPhase else { return }

        // Three packets per connection at 0.0 / 0.33 / 0.66 phase
        // offsets — gives the line a "data flow" rhythm.
        for k in 0..<3 {
            let t = (phase + Double(k) / 3.0).truncatingRemainder(dividingBy: 1.0)
            let pt = CGPoint(
                x: start.x + (end.x - start.x) * CGFloat(t),
                y: start.y + (end.y - start.y) * CGFloat(t)
            )
            // Fade in over first 10%, fade out over last 10%. Keeps
            // packets from popping in at the start point.
            let alpha: Double
            if t < 0.1 { alpha = t / 0.1 }
            else if t > 0.9 { alpha = (1.0 - t) / 0.1 }
            else { alpha = 1.0 }

            let packet = Path(ellipseIn: CGRect(
                x: pt.x - 2, y: pt.y - 2, width: 4, height: 4
            ))
            context.fill(
                packet,
                with: .color(Kiln.Palette.firing.opacity(0.6 * alpha))
            )
        }
    }
}

// MARK: - Node model

extension AgentNetworkDiagram {
    /// One labelled vertex of the diagram. `role` only documents what
    /// the node represents — layout positions are determined separately
    /// by `layout(in:)` so the model stays geometry-agnostic.
    struct Node: Identifiable, Hashable {
        let id: String
        let title: String
        let subtitle: String
        let role: Role
        let tooltip: String

        enum Role: Hashable { case center, top, right, bottom, left }
    }
}

// MARK: - Node chip

/// The visible token at each node position. Solid pill with a subtle
/// outer ring; the central Opus node wears a thin amber ring to mark
/// it as the conceptual hub. Hover lifts the chip slightly.
private struct NodeChip: View {
    let node: AgentNetworkDiagram.Node

    @State private var isHovered: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isCentral: Bool { node.role == .center }

    var body: some View {
        VStack(alignment: .center, spacing: 2) {
            Text(node.title)
                .font(Kiln.Font.body.weight(.semibold))
                .foregroundStyle(.primary)
            Text(node.subtitle)
                .font(Kiln.Font.label)
                .kerning(0.44)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Kiln.Space.sm)
        .padding(.vertical, Kiln.Space.xs)
        .background {
            RoundedRectangle(cornerRadius: Kiln.Radius.card, style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Kiln.Radius.card, style: .continuous)
                .strokeBorder(
                    isCentral
                        ? Kiln.Palette.firing.opacity(0.6)
                        : Color.primary.opacity(Kiln.Opacity.trackFill),
                    lineWidth: isCentral ? 1.5 : 1
                )
        }
        .scaleEffect(isHovered ? 1.04 : 1.0)
        .shadow(
            color: Color.black.opacity(isHovered ? 0.10 : 0.04),
            radius: isHovered ? 8 : 3,
            x: 0,
            y: isHovered ? 4 : 1
        )
        .onHover { hovering in
            guard !reduceMotion else {
                isHovered = hovering
                return
            }
            withAnimation(Kiln.Motion.microToggle) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Preview

#Preview("Agent network") {
    AgentNetworkDiagram()
        .padding(Kiln.Space.l)
        .frame(width: 720)
        .background(Color(NSColor.windowBackgroundColor))
}
