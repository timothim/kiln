import SwiftUI

/// Right pane for the `.complete` stage. Vertically stacks the before/after
/// sample preview and the Terminal hand-off card.
struct CompleteDetailView: View {
    let project: Project

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.thinMaterial)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: Kiln.Space.m) {
                    SamplePreviewPanel()
                    Divider()
                        .padding(.horizontal, Kiln.Space.m)
                    ChatPanel(project: project)
                }
                .padding(.vertical, Kiln.Space.xs)
            }
        }
    }
}
