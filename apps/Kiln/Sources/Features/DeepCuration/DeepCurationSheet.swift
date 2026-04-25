import KilnCore
import SwiftUI

/// Sheet wrapper that presents ``DeepCurationView`` from the Dataset
/// Doctor's "Run Deep Curation" CTA (Audit C3). Adds a Done button so
/// the user can close mid-review (the underlying ``DeepCurationModel``
/// state is preserved on AppModel until the sheet is dismissed).
struct DeepCurationSheet: View {
    @Bindable var model: DeepCurationModel
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            DeepCurationView(model: model)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", action: onClose)
                            .keyboardShortcut(.defaultAction)
                    }
                }
        }
        .frame(minWidth: 720, idealWidth: 820, minHeight: 600, idealHeight: 720)
    }
}
