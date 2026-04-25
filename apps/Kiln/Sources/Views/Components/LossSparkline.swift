import SwiftUI
import KilnCore

/// Ambient line chart of train-loss with a dashed val-loss overlay. Uses
/// `SwiftUI.Canvas` so there is no charting dependency. Draws nothing if
/// fewer than two samples are available — one datapoint is not yet a trend.
///
/// Sunday animation pass:
///   - Catmull-Rom interpolation replaces linear segments so the line
///     reads as continuous progress rather than as a polyline.
///   - Faint gradient fill under the train-loss curve, fading from the
///     line color at the curve down to transparent at the baseline.
///   - The latest sample wears a small glowing dot whose alpha breathes
///     via `Kiln.Motion.statusPulse` (Reduce Motion → static dot).
struct LossSparkline: View {
    let samples: [LossSample]
    var height: CGFloat = 84
    var showsGrid: Bool = true
    /// `true` while training is actively producing new samples. The
    /// glowing latest-point dot only pulses while live; pass `false` on
    /// the completion screen to freeze the dot and free the TimelineView
    /// budget. Defaults to `true` so existing call sites get the lively
    /// behavior without opting in.
    var isLive: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            curveLayer
            // The latest-point indicator sits in its own TimelineView so
            // only the dot's alpha re-renders on each frame; the curve
            // beneath is a static Canvas. Static when training is over
            // (`isLive == false`) or under Reduce Motion.
            if !reduceMotion, isLive, samples.count >= 2 {
                latestDotAnimated
            } else if samples.count >= 2 {
                latestDotStatic
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("Training loss")
        .accessibilityValue(accessibilityValue)
    }

    // MARK: - Curve layer (static Canvas)

    private var curveLayer: some View {
        Canvas { context, size in
            guard samples.count >= 2 else { return }
            let geom = ChartGeometry(samples: samples, size: size)

            // Optional grid baseline at midpoint.
            if showsGrid {
                var grid = Path()
                let midY = geom.padding + geom.usableHeight / 2
                grid.move(to: CGPoint(x: geom.padding, y: midY))
                grid.addLine(to: CGPoint(x: size.width - geom.padding, y: midY))
                context.stroke(
                    grid,
                    with: .color(.secondary.opacity(0.10)),
                    lineWidth: 0.5
                )
            }

            // Train-loss line — Catmull-Rom interpolated.
            let trainPoints = samples.enumerated().map { i, s in
                geom.point(forIndex: i, value: s.trainLoss)
            }
            let trainCurve = catmullRomPath(through: trainPoints)

            // Gradient fill clipped under the curve. Closes the path
            // along the bottom to form a polygon, then masks with a
            // vertical gradient.
            var fill = trainCurve
            fill.addLine(to: CGPoint(x: trainPoints.last?.x ?? 0,
                                     y: size.height - geom.padding))
            fill.addLine(to: CGPoint(x: trainPoints.first?.x ?? 0,
                                     y: size.height - geom.padding))
            fill.closeSubpath()
            context.fill(
                fill,
                with: .linearGradient(
                    Gradient(colors: [
                        Color.primary.opacity(0.18),
                        Color.primary.opacity(0.0)
                    ]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: 0, y: size.height)
                )
            )

            context.stroke(
                trainCurve,
                with: .color(.primary.opacity(0.85)),
                style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round)
            )

            // Val-loss overlay — amber dashed line where val was computed.
            let valPoints = samples.enumerated().compactMap { (i, s) -> CGPoint? in
                guard let v = s.valLoss else { return nil }
                return geom.point(forIndex: i, value: v)
            }
            if valPoints.count >= 2 {
                let valCurve = catmullRomPath(through: valPoints)
                context.stroke(
                    valCurve,
                    with: .color(Kiln.Palette.firing),
                    style: StrokeStyle(
                        lineWidth: 1.25,
                        lineCap: .round,
                        lineJoin: .round,
                        dash: [3, 3]
                    )
                )
            }
        }
    }

    // MARK: - Latest-point glowing dot

    /// Reduce-Motion fallback. A 4-pt dot at the most recent train-loss
    /// point with a soft static glow.
    private var latestDotStatic: some View {
        GeometryReader { proxy in
            let geom = ChartGeometry(samples: samples, size: proxy.size)
            let pt = latestPoint(in: geom)
            Circle()
                .fill(Color.primary)
                .frame(width: 4, height: 4)
                .shadow(color: .primary.opacity(0.4), radius: 3)
                .position(pt)
        }
    }

    /// Pulsing version. TimelineView at 30 fps — the only animated
    /// element on the chart, so cost stays trivial.
    private var latestDotAnimated: some View {
        GeometryReader { proxy in
            let geom = ChartGeometry(samples: samples, size: proxy.size)
            let pt = latestPoint(in: geom)
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let phase = pulsePhase(at: context.date)
                Circle()
                    .fill(Color.primary)
                    .frame(width: 4, height: 4)
                    .shadow(
                        color: Color.primary.opacity(0.3 + 0.4 * phase),
                        radius: 2 + 4 * phase
                    )
                    .position(pt)
            }
        }
    }

    private func latestPoint(in geom: ChartGeometry) -> CGPoint {
        let lastIndex = samples.count - 1
        let lastValue = samples[lastIndex].trainLoss
        return geom.point(forIndex: lastIndex, value: lastValue)
    }

    /// 0...1 sin wave at 1.4s period (matches `Kiln.Motion.statusPulse`).
    private func pulsePhase(at date: Date) -> Double {
        let t = date.timeIntervalSinceReferenceDate
        let omega = 2.0 * .pi / 1.4
        return 0.5 + 0.5 * sin(t * omega)
    }

    // MARK: - Accessibility

    private var accessibilityValue: String {
        guard let last = samples.last else { return "No data yet" }
        let trainStr = String(format: "%.2f", last.trainLoss)
        if let valStr = last.valLoss.map({ String(format: "%.2f", $0) }) {
            return "Train loss \(trainStr). Validation loss \(valStr)."
        }
        return "Train loss \(trainStr)."
    }
}

// MARK: - Chart geometry

/// Reusable mapping from sample index + value into Canvas coordinates.
/// Centralised so curve, fill, and the floating dot share the same math.
private struct ChartGeometry {
    let padding: CGFloat = 6
    let usableWidth: CGFloat
    let usableHeight: CGFloat
    let minValue: Double
    let range: Double
    let count: Int

    init(samples: [LossSample], size: CGSize) {
        self.usableWidth = max(1, size.width - 12)
        self.usableHeight = max(1, size.height - 12)
        let trainValues = samples.map(\.trainLoss)
        let valValues = samples.compactMap(\.valLoss)
        let allValues = trainValues + valValues
        self.minValue = allValues.min() ?? 0
        let maxValue = allValues.max() ?? 1
        self.range = max(0.01, maxValue - minValue)
        self.count = samples.count
    }

    func point(forIndex i: Int, value: Double) -> CGPoint {
        let x = padding + usableWidth * CGFloat(i) / CGFloat(max(1, count - 1))
        let normalized = (value - minValue) / range
        let y = padding + usableHeight * (1 - CGFloat(normalized))
        return CGPoint(x: x, y: y)
    }
}

// MARK: - Catmull-Rom path

/// Smooth interpolation through the supplied points. Uses the centripetal
/// Catmull-Rom variant translated into cubic Bezier control points so the
/// SwiftUI `Path` API can render it. Falls back to a straight line for
/// fewer than two points.
private func catmullRomPath(through points: [CGPoint]) -> Path {
    var path = Path()
    guard let first = points.first else { return path }
    path.move(to: first)
    guard points.count >= 2 else { return path }

    // Pad endpoints by mirroring so every segment has neighbours.
    let extended: [CGPoint] = {
        var arr = points
        if let p0 = points.first {
            arr.insert(p0, at: 0)
        }
        if let pn = points.last {
            arr.append(pn)
        }
        return arr
    }()

    for i in 1..<(extended.count - 2) {
        let p0 = extended[i - 1]
        let p1 = extended[i]
        let p2 = extended[i + 1]
        let p3 = extended[i + 2]
        // Standard Catmull-Rom → Bezier conversion (uniform parametrization).
        let cp1 = CGPoint(
            x: p1.x + (p2.x - p0.x) / 6.0,
            y: p1.y + (p2.y - p0.y) / 6.0
        )
        let cp2 = CGPoint(
            x: p2.x - (p3.x - p1.x) / 6.0,
            y: p2.y - (p3.y - p1.y) / 6.0
        )
        path.addCurve(to: p2, control1: cp1, control2: cp2)
    }
    return path
}

#Preview("LossSparkline — happy") {
    let samples: [LossSample] = (0..<60).map { i in
        let x = Double(i)
        return LossSample(
            iter: i,
            trainLoss: 1.6 - 0.02 * x + 0.05 * sin(x / 3.0),
            valLoss: i % 10 == 0 ? 1.55 - 0.015 * x : nil
        )
    }
    return LossSparkline(samples: samples)
        .padding()
        .frame(width: 420)
}

#Preview("LossSparkline — early in training") {
    let samples: [LossSample] = (0..<8).map { i in
        LossSample(iter: i, trainLoss: 1.7 - 0.04 * Double(i), valLoss: nil)
    }
    return LossSparkline(samples: samples)
        .padding()
        .frame(width: 420)
}
