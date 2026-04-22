import SwiftUI

/// Shown in the right pane when no project is selected, or when the selected
/// project is still `.readyToDrop`. Invites, never states "No data".
struct DetailEmptyView: View {
    var headline: String = "Details will appear here."
    var context: String? = "Drop a folder to see what Kiln reads."

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.thinMaterial)
                .ignoresSafeArea()

            EmptyState(
                systemImage: "sparkles.rectangle.stack",
                headline: headline,
                context: context
            )
        }
    }
}
