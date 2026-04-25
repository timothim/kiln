import SwiftUI

/// Dims the in-progress view and shows a "Cancelling…" pill while the
/// pipeline winds down after PrepareModel.cancel().
struct CancellingOverlay<Underlying: View>: View {
    let underlying: Underlying

    var body: some View {
        ZStack {
            underlying
                .opacity(0.5)
                .allowsHitTesting(false)
            HStack(spacing: Kiln.Space.xs) {
                ProgressView()
                    .controlSize(.small)
                // DESIGN.md §components.cancelling-overlay: copy reassures —
                // the user's last chunk is already saved by the time we show this.
                Text("Cancelling — your last chunk is saved.")
                    .font(Kiln.Font.body)
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, Kiln.Space.m)
            .padding(.vertical, Kiln.Space.xs)
            .background(
                Capsule(style: .continuous)
                    .fill(.background.secondary)
            )
            .accessibilityAddTraits(.updatesFrequently)
            .accessibilityLabel("Cancelling — your last chunk is saved")
        }
    }
}
