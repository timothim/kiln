import SwiftUI

/// Animated integer display for running counts. Uses SwiftUI's numericText
/// content transition so incrementing values roll up cleanly.
struct LiveCountTicker: View {
    let label: String
    let value: Int

    var body: some View {
        // 2pt: sub-typographic gap between a numeric display and its caption.
        // Layout tokens don't model kerning-scale spacing; leave as literal.
        VStack(alignment: .leading, spacing: 2) {
            Text(value, format: .number)
                .font(Kiln.Font.title)
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: false))
                .animation(Kiln.Motion.standard, value: value)
            Text(label)
                .font(Kiln.Font.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}
