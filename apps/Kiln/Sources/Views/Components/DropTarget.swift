import SwiftUI
import UniformTypeIdentifiers

/// Accepts a folder drop and forwards the URL to the supplied handler.
/// Filters out non-directory URLs so stray file drops don't trigger ingest.
struct DropTarget: ViewModifier {
    @Binding var isTargeted: Bool
    let onDrop: (URL) -> Void

    func body(content: Content) -> some View {
        content
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first(where: Self.isDirectory) else { return false }
                onDrop(url)
                return true
            } isTargeted: { targeted in
                isTargeted = targeted
            }
    }

    static func isDirectory(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        return values?.isDirectory == true
    }
}

extension View {
    func dropFolder(isTargeted: Binding<Bool>, onDrop: @escaping (URL) -> Void) -> some View {
        modifier(DropTarget(isTargeted: isTargeted, onDrop: onDrop))
    }
}
