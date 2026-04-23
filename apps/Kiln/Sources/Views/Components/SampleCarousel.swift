import SwiftUI
import KilnCore

/// Crossfades the most-recently-seen ChunkPreview as new samples arrive.
/// Only the newest sample is shown at a time; PrepareModel keeps the full rolling window.
struct SampleCarousel: View {
    let samples: [ChunkPreview]

    var body: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.xs) {
            Text("Recent sample")
                .font(Kiln.Font.caption)
                .foregroundStyle(.tertiary)
            ZStack {
                if let latest = samples.last {
                    SampleCard(preview: latest)
                        .id(latest.id)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .trailing)),
                            removal: .opacity.combined(with: .move(edge: .leading))
                        ))
                } else {
                    EmptySampleCard()
                }
            }
            .animation(Kiln.Motion.standard, value: samples.last?.id)
        }
    }
}

private struct SampleCard: View {
    let preview: ChunkPreview

    var body: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.xxs) {
            HStack(spacing: Kiln.Space.xxs) {
                Image(systemName: iconName(for: preview.kind))
                    .font(Kiln.Font.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(sourceLabel)
                    .font(Kiln.Font.mono)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Text(preview.assistantSnippet)
                .font(Kiln.Font.body)
                .foregroundStyle(.primary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Kiln.Space.m)
        .background(
            RoundedRectangle(cornerRadius: Kiln.Radius.card, style: .continuous)
                .fill(Kiln.Palette.firingWash)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sample from \(sourceLabel). \(preview.assistantSnippet)")
    }

    private var sourceLabel: String {
        (preview.sourcePath as NSString).lastPathComponent
    }

    private func iconName(for kind: ChunkKind) -> String {
        switch kind {
        case .text: return "doc.text"
        case .chat: return "bubble.left.and.bubble.right"
        case .code: return "curlybraces"
        }
    }
}

private struct EmptySampleCard: View {
    var body: some View {
        HStack {
            Text("Reading your folder.")
                .font(Kiln.Font.body)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(Kiln.Space.m)
        .background(
            RoundedRectangle(cornerRadius: Kiln.Radius.card, style: .continuous)
                .fill(Kiln.Palette.firingWash)
        )
    }
}
