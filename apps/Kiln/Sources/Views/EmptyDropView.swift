import SwiftUI

/// Full-window launch view. The drop surface per the Claude Design package
/// (`drop` Tier S). Three states (`empty`, `targeted`, `received`) — `empty`
/// is the launch state shipped here; `received` is handled by `AppModel.ingest`
/// which moves the project into the prepare stage.
///
/// Visual recipe (from `kiln-ui/KilnDesign.zip` `drop` surface):
///   - 480×280 dashed firing-bordered zone, centered serif "Drop a folder of your writing."
///   - Subtle ember pulse on the corner glyph (the firing dot top-right)
///   - Targeted: border becomes solid, fill becomes `firing-wash`,
///     surface scales 1.04 on Kindled
struct EmptyDropView: View {
    let model: AppModel

    @State private var isTargeted = false

    var body: some View {
        VStack {
            Spacer()
            dropZone
            Spacer()
            keyboardHint
                .padding(.bottom, Kiln.Space.s8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Kiln.Palette.paper.ignoresSafeArea())
    }

    private var dropZone: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: Kiln.Space.s4) {
                Spacer(minLength: 0)
                Text("Drop a folder of your writing.")
                    .font(Kiln.Font.display)
                    .foregroundStyle(Kiln.Palette.onSurface)
                    .multilineTextAlignment(.center)
                Text("Notes, messages, journal — anything in your voice.")
                    .font(Kiln.Font.body)
                    .foregroundStyle(Kiln.Palette.onSurface2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(Kiln.Space.s7)
            .frame(width: 480, height: 280)
            .background {
                RoundedRectangle(cornerRadius: Kiln.Radius.r5, style: .continuous)
                    .fill(isTargeted
                          ? Kiln.Palette.firingWash
                          : Kiln.Palette.surface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Kiln.Radius.r5, style: .continuous)
                    .strokeBorder(
                        Kiln.Palette.firing,
                        style: StrokeStyle(
                            lineWidth: isTargeted ? 1.5 : 1.5,
                            dash: isTargeted ? [] : [6, 4]
                        )
                    )
            }
            // Corner glyph — subtle ember pulse top-right per design spec.
            EmberDot(size: 7)
                .padding(Kiln.Space.s4)

            .scaleEffect(isTargeted ? 1.04 : 1.0)
            .animation(Kiln.Motion.kind, value: isTargeted)
        }
        .scaleEffect(isTargeted ? 1.04 : 1.0)
        .animation(Kiln.Motion.kind, value: isTargeted)
        .dropFolder(isTargeted: $isTargeted) { url in
            withAnimation(Kiln.Motion.kind) {
                model.ingest(folderURL: url)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Drop a folder of your writing")
        .accessibilityHint("Drag a folder onto this zone, or press Command N to start blank")
        .accessibilityAddTraits(.isButton)
    }

    private var keyboardHint: some View {
        HStack(spacing: Kiln.Space.s2) {
            Text("or press")
            Text("⌘N")
                .font(Kiln.Font.eyebrow)
                .kerning(0.4)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background {
                    RoundedRectangle(cornerRadius: Kiln.Radius.r1, style: .continuous)
                        .fill(Kiln.Palette.surface2)
                }
            Text("to start blank")
        }
        .font(Kiln.Font.caption)
        .foregroundStyle(Kiln.Palette.onSurface3)
    }
}

#Preview("Drop zone — empty") {
    EmptyDropView(model: AppModel())
        .frame(width: 900, height: 560)
}
