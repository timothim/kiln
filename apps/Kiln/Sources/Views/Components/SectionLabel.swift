import SwiftUI

/// Small-caps eyebrow used above grouped content — "Selected", "Include",
/// "Your recipient runs", "Top contributing terms". Three feature views
/// shipped private copies of this struct (Voice Inspector, Style Signature,
/// Kiln Share); collapsed into one canonical component so a token edit only
/// happens in one place.
///
/// Mapping to DESIGN.md:
///   - typography: `label` (11pt semibold + 0.04em tracking)
///   - color: `.tertiary` (resolves through SwiftUI semantic layer)
///   - case: uppercase via `textCase(.uppercase)`
///
/// Renders flat — no padding, no background — so the call site keeps the
/// layout discipline it already has. Carries an `.accessibilityHeading(.h3)`
/// trait so VoiceOver users can navigate sections with the rotor.
struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Kiln.Font.label)
            .kerning(0.44)
            .foregroundStyle(.tertiary)
            .textCase(.uppercase)
            .accessibilityAddTraits(.isHeader)
    }
}

#Preview("SectionLabel — light") {
    VStack(alignment: .leading, spacing: Kiln.Space.m) {
        SectionLabel(text: "Selected")
        Text("Sample content under the eyebrow.")
            .font(Kiln.Font.body)
            .foregroundStyle(.primary)
        SectionLabel(text: "Top contributing terms")
        Text("More sample content.")
            .font(Kiln.Font.body)
            .foregroundStyle(.primary)
    }
    .padding(Kiln.Space.l)
    .frame(width: 360, alignment: .leading)
}
