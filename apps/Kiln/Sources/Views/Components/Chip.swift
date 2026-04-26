import SwiftUI

/// Pill chip per DESIGN.md `chip` / `chip-firing` component spec.
///
/// - `Chip(text)`: neutral chip — `surface-2` fill, `meta` mono text,
///   `r-pill` corners. Used for inert metadata (file counts, sources, etc.).
/// - `Chip(text, isFiring: true)`: firing variant — `firing-wash` background,
///   `firing` text, inline `EmberDot` to communicate "alive." Used on
///   training status ("Training", "iter 200/500"), the kiln-noor eyebrow,
///   the advisor pill.
///
/// The chip carries no interaction by default — wrap in a Button if needed.
struct Chip: View {
    let text: String
    var isFiring: Bool = false

    var body: some View {
        HStack(spacing: Kiln.Space.s2) {
            if isFiring {
                EmberDot()
            }
            Text(text)
                .font(Kiln.Font.meta)
                .foregroundStyle(isFiring ? Kiln.Palette.firing : Kiln.Palette.onSurface2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background {
            Capsule(style: .continuous)
                .fill(isFiring ? Kiln.Palette.firingWash : Kiln.Palette.surface2)
        }
        .overlay {
            // Hairline inside the pill so the edge reads in dark mode.
            Capsule(style: .continuous)
                .strokeBorder(Kiln.Palette.hairline2, lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isFiring ? "\(text), live" : text)
    }
}

#Preview("Chips — neutral and firing") {
    VStack(alignment: .leading, spacing: Kiln.Space.s3) {
        HStack(spacing: Kiln.Space.s2) {
            Chip(text: "1,247 files")
            Chip(text: "Apple Notes")
            Chip(text: "3,887 chunks")
        }
        HStack(spacing: Kiln.Space.s2) {
            Chip(text: "Training", isFiring: true)
            Chip(text: "iter 200/500", isFiring: true)
            Chip(text: "kiln-noor · iter 500", isFiring: true)
        }
    }
    .padding(Kiln.Space.s6)
    .background(Kiln.Palette.paper)
}
