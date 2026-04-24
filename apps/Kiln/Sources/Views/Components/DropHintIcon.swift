import SwiftUI

/// Amber-washed folder glyph used inside the launch drop zone.
/// Branded, deliberately not a dashed-rectangle "NSOpenPanel" look.
struct DropHintIcon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Kiln.Radius.card, style: .continuous)
                .fill(Kiln.Palette.firingWash)
                .frame(width: 92, height: 92)

            Image(systemName: "folder.badge.plus")
                .font(.system(size: Kiln.Icon.hero, weight: .regular))
                .foregroundStyle(Kiln.Palette.firing)
                .symbolRenderingMode(.hierarchical)
        }
        .accessibilityHidden(true)
    }
}
