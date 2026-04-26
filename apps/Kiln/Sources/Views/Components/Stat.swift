import SwiftUI

/// Small stat tile: quiet label above, confident value below. Used in the
/// training pane and the complete summary. Never bold the label — hierarchy
/// comes from color + type ramp, not weight.
struct Stat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Kiln.Font.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Text(value)
                .font(Kiln.Font.body)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .truncationMode(.middle)
        }
        .padding(.horizontal, Kiln.Space.sm)
        .padding(.vertical, Kiln.Space.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Kiln.Radius.card, style: .continuous)
                .fill(.regularMaterial)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}
