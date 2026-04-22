import SwiftUI

/// A drop zone for folders. The parent view supplies the `onDrop` handler.
///
/// Visual language: amber glow on hover, fades to nothing when the next stage
/// takes over. No text unless the user is hovering something droppable.
struct DropZone: View {
    /// Called with the URL of the dropped folder. The caller is responsible for
    /// validating the URL (existence, sandbox access, is-directory).
    let onDrop: (URL) -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.regularMaterial)
            .overlay {
                Text("Drop a folder. Meet yourself.")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: isHovered ? 2 : 0)
            }
            .animation(.smooth(duration: 0.35), value: isHovered)
    }
}
