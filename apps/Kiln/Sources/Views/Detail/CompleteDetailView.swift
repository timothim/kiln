import SwiftUI

/// Right pane for the `.complete` stage. Vertically stacks the before/after
/// sample preview and the Terminal hand-off card.
struct CompleteDetailView: View {
    let project: Project
    /// Audit C5: per-project Sample Preview model. Resolved by
    /// ``DetailView`` from ``AppModel.samplePreviewModel(for:)``. Nil
    /// during preview / SwiftUI canvas — render nothing in that case
    /// rather than the old hardcoded fake.
    var samplePreviewModel: SamplePreviewModel? = nil

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.thinMaterial)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: Kiln.Space.m) {
                    if let samplePreviewModel {
                        SamplePreviewPanel(model: samplePreviewModel)
                        Divider()
                            .padding(.horizontal, Kiln.Space.m)
                    }
                    ChatPanel(project: project)
                }
                .padding(.vertical, Kiln.Space.xs)
            }
        }
    }
}
