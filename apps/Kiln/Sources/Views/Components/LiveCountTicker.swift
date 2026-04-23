import SwiftUI

/// Animated integer display for running counts. Uses SwiftUI's numericText
/// content transition so incrementing values roll up cleanly.
struct LiveCountTicker: View {
    let label: String
    let value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value, format: .number)
                .font(Kiln.Font.title)
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: false))
                .animation(.smooth(duration: 0.35), value: value)
            Text(label)
                .font(Kiln.Font.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}
