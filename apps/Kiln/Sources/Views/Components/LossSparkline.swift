import SwiftUI
import KilnCore

/// Ambient line chart of train-loss with a dashed val-loss overlay. Uses
/// `SwiftUI.Canvas` so there is no charting dependency. Draws nothing if
/// fewer than two samples are available — one datapoint is not yet a trend.
struct LossSparkline: View {
    let samples: [LossSample]
    var height: CGFloat = 84
    var showsGrid: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Canvas { context, size in
            guard samples.count >= 2 else { return }

            let trainValues = samples.map(\.trainLoss)
            let valValues = samples.compactMap(\.valLoss)
            let allValues = trainValues + valValues

            guard let minValue = allValues.min(), let maxValue = allValues.max() else { return }
            let padding: CGFloat = 6
            let usableWidth = max(1, size.width - padding * 2)
            let usableHeight = max(1, size.height - padding * 2)
            let range = max(0.01, maxValue - minValue)

            func pointForIndex(_ i: Int, value: Double) -> CGPoint {
                let x = padding + usableWidth * CGFloat(i) / CGFloat(max(1, samples.count - 1))
                let normalized = (value - minValue) / range
                let y = padding + usableHeight * (1 - CGFloat(normalized))
                return CGPoint(x: x, y: y)
            }

            if showsGrid {
                var grid = Path()
                let midY = padding + usableHeight / 2
                grid.move(to: CGPoint(x: padding, y: midY))
                grid.addLine(to: CGPoint(x: size.width - padding, y: midY))
                context.stroke(grid, with: .color(.secondary.opacity(0.10)), lineWidth: 0.5)
            }

            // Train-loss line — 1px, primary.
            var trainPath = Path()
            for (i, sample) in samples.enumerated() {
                let pt = pointForIndex(i, value: sample.trainLoss)
                if i == 0 { trainPath.move(to: pt) } else { trainPath.addLine(to: pt) }
            }
            context.stroke(
                trainPath,
                with: .color(.primary.opacity(0.85)),
                style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round)
            )

            // Val-loss overlay — amber dashed line across the points where val was computed.
            let valPoints = samples.enumerated().compactMap { (i, s) -> CGPoint? in
                guard let v = s.valLoss else { return nil }
                return pointForIndex(i, value: v)
            }
            if valPoints.count >= 2 {
                var valPath = Path()
                for (i, pt) in valPoints.enumerated() {
                    if i == 0 { valPath.move(to: pt) } else { valPath.addLine(to: pt) }
                }
                context.stroke(
                    valPath,
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
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("Training loss")
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        guard let last = samples.last else { return "No data yet" }
        let trainStr = String(format: "%.2f", last.trainLoss)
        if let valStr = last.valLoss.map({ String(format: "%.2f", $0) }) {
            return "Train loss \(trainStr). Validation loss \(valStr)."
        }
        return "Train loss \(trainStr)."
    }
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
