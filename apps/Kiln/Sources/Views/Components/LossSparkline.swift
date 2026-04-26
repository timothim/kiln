import SwiftUI
import KilnCore

/// Loss sparkline per the Claude Design package `sparkline` component:
/// 1.5px stroke in `firing`, no fill, the last point is a 4px filled
/// circle pulsing on `t-ember` cadence.
///
/// Uses `SwiftUI.Canvas` for the curve + a separate `TimelineView`-driven
/// overlay for the pulsing dot, so the canvas redraws only when samples
/// change while the dot ticks at 30fps. Catmull-Rom interpolation gives
/// a continuous trace rather than a polyline.
struct LossSparkline: View {
    let samples: [LossSample]
    var height: CGFloat = 84
    var showsGrid: Bool = true
    /// `true` while training is producing new samples. The glowing dot
    /// only pulses while live; pass `false` on the completion screen to
    /// freeze the dot.
    var isLive: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            curveLayer
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

    // MARK: - Curve layer (static Canvas — only redraws on sample changes)

    private var curveLayer: some View {
        Canvas { context, size in
            guard samples.count >= 2 else { return }
            let geom = ChartGeometry(samples: samples, size: size)

            if showsGrid {
                var grid = Path()
                let midY = geom.padding + geom.usableHeight / 2
                grid.move(to: CGPoint(x: geom.padding, y: midY))
                grid.addLine(to: CGPoint(x: size.width - geom.padding, y: midY))
                context.stroke(
                    grid,
                    with: .color(Kiln.Palette.hairline2),
                    lineWidth: 0.5
                )
            }

            // Train-loss line — Catmull-Rom interpolated, 1.5px firing stroke.
            // Per design package: clean line, no fill underneath.
            let trainPoints = samples.enumerated().map { i, s in
                geom.point(forIndex: i, value: s.trainLoss)
            }
            let trainCurve = catmullRomPath(through: trainPoints)
            context.stroke(
                trainCurve,
                with: .color(Kiln.Palette.firing),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            )

            // Val-loss overlay — `firing-2` dashed where val was computed.
            let valPoints = samples.enumerated().compactMap { (i, s) -> CGPoint? in
                guard let v = s.valLoss else { return nil }
                return geom.point(forIndex: i, value: v)
            }
            if valPoints.count >= 2 {
                let valCurve = catmullRomPath(through: valPoints)
                context.stroke(
                    valCurve,
                    with: .color(Kiln.Palette.firing2),
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

    /// Reduce-Motion fallback — 4pt firing dot at the latest point with
    /// a soft static glow. No animation, no TimelineView.
    private var latestDotStatic: some View {
        GeometryReader { proxy in
            let geom = ChartGeometry(samples: samples, size: proxy.size)
            let pt = latestPoint(in: geom)
            Circle()
                .fill(Kiln.Palette.firing)
                .frame(width: 4, height: 4)
                .shadow(color: Kiln.Palette.firing.opacity(0.4), radius: 3)
                .position(pt)
        }
    }

    /// Pulsing version. TimelineView at 30fps; only the dot's shadow
    /// re-renders per frame, the curve underneath is static.
    private var latestDotAnimated: some View {
        GeometryReader { proxy in
            let geom = ChartGeometry(samples: samples, size: proxy.size)
            let pt = latestPoint(in: geom)
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let phase = pulsePhase(at: context.date)
                Circle()
                    .fill(Kiln.Palette.firing)
                    .frame(width: 4, height: 4)
                    .shadow(
                        color: Kiln.Palette.firing.opacity(0.3 + 0.4 * phase),
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

    /// 0…1 sin wave at 1.8s period — matches `t-ember` so the loss-curve
    /// dot pulses in sync with every other "alive" indicator on screen.
    private func pulsePhase(at date: Date) -> Double {
        let t = date.timeIntervalSinceReferenceDate
        let omega = 2.0 * .pi / 1.8
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

/// Smooth interpolation through the supplied points. Uses centripetal
/// Catmull-Rom translated into cubic Bezier control points so the
/// SwiftUI `Path` API can render it. Falls back to a straight line for
/// fewer than two points.
private func catmullRomPath(through points: [CGPoint]) -> Path {
    var path = Path()
    guard let first = points.first else { return path }
    path.move(to: first)
    guard points.count >= 2 else { return path }

    let extended: [CGPoint] = {
        var arr = points
        if let p0 = points.first { arr.insert(p0, at: 0) }
        if let pn = points.last { arr.append(pn) }
        return arr
    }()

    for i in 1..<(extended.count - 2) {
        let p0 = extended[i - 1]
        let p1 = extended[i]
        let p2 = extended[i + 1]
        let p3 = extended[i + 2]
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
        .background(Kiln.Palette.paper)
}
