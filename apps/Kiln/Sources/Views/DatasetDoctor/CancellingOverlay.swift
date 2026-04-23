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
                Text("Cancelling.")
                    .font(Kiln.Font.body)
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, Kiln.Space.s)
            .padding(.vertical, Kiln.Space.xs)
            .background(
                Capsule(style: .continuous)
                    .fill(.background.secondary)
            )
            .accessibilityAddTraits(.updatesFrequently)
            .accessibilityLabel("Cancelling")
        }
    }
}
