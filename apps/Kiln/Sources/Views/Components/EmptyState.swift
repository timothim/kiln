import SwiftUI

/// Template for every blank pane. Icon, one-line headline, optional
/// one-sentence context, optional single CTA. Never used as "No data".
struct EmptyState: View {
    let systemImage: String
    let headline: String
    var context: String? = nil
    var cta: CTA? = nil

    struct CTA {
        let title: String
        let action: () -> Void
    }

    var body: some View {
        VStack(spacing: Kiln.Space.m) {
            Image(systemName: systemImage)
                .font(.system(size: Kiln.Icon.placeholder, weight: .light))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)

            Text(headline)
                .font(Kiln.Font.body)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            if let context {
                Text(context)
                    .font(Kiln.Font.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }

            if let cta {
                Button(cta.title, action: cta.action)
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .padding(.top, Kiln.Space.xs)
            }
        }
        .padding(Kiln.Space.xl)
        .frame(maxWidth: 380)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
