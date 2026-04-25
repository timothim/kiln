import KilnCore
import SwiftUI

/// Sheet wrapper that presents the existing ``VoiceCoachView`` from
/// the Complete-stage "Get Voice Report" button (Audit C2). Adds a
/// "Done" button and auto-fires ``model.generate(input:)`` on first
/// appearance — without this the panel would sit in ``.idle`` until
/// the user dug for a "Run" button that doesn't exist.
struct VoiceCoachSheet: View {
    @Bindable var model: VoiceCoachModel
    let input: VoiceCoachInput
    let onClose: () -> Void

    @State private var hasKickedOff = false

    var body: some View {
        NavigationStack {
            VoiceCoachView(model: model, input: input)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", action: onClose)
                            .keyboardShortcut(.defaultAction)
                    }
                }
        }
        .task {
            // Fire once per sheet instance. SwiftUI re-runs .task when
            // `.id` changes; the model is reference-typed so the same
            // instance survives close/reopen, but the model is freshly
            // constructed by ``AppModel.openVoiceCoach`` each time so
            // a re-open kicks off a fresh report.
            if !hasKickedOff, case .idle = model.state {
                hasKickedOff = true
                await model.generate(input: input)
            }
        }
    }
}
