import SwiftUI

/// Audit C5: the Before/After card for the Complete detail pane. Real
/// data, not the M3 placeholder. Reads ``SamplePreviewModel`` for the
/// prompt + per-variant completions and per-variant failure state.
///
/// The model is non-optional because every Complete-stage view we mount
/// owns one. Tests construct the model directly with a stub runner; the
/// view never has to handle the "no model" case.
struct SamplePreviewPanel: View {
    @Bindable var model: SamplePreviewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.m) {
            header
            promptRow
            sampleRow(
                label: "Base",
                text: model.baseCompletion,
                failure: model.baseFailureMessage,
                tint: .secondary
            )
            sampleRow(
                label: "Kiln",
                text: model.tunedCompletion,
                failure: model.tunedFailureMessage,
                tint: .primary
            )
            footer
        }
        .padding(Kiln.Space.m)
        .task {
            // Fire once when the panel first appears in the .complete
            // stage. SwiftUI re-runs `.task` only when the model
            // identity changes.
            if case .idle = model.state {
                await model.runCompare()
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Sample")
                .font(Kiln.Font.title)
            Spacer()
            if case .running = model.state {
                ProgressView().controlSize(.small)
            }
        }
    }

    private var promptRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: Kiln.Space.xs) {
            Text("You asked")
                .font(Kiln.Font.caption)
                .foregroundStyle(.tertiary)
            Text(model.prompt)
                .font(Kiln.Font.body)
                .foregroundStyle(.primary)
                .lineLimit(2)
        }
    }

    private func sampleRow(
        label: String,
        text: String?,
        failure: String?,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: Kiln.Space.xxs) {
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 6, height: 6)
                Text(label)
                    .font(Kiln.Font.caption)
                    .foregroundStyle(.secondary)
            }
            if let text {
                Text(text)
                    .font(Kiln.Font.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let failure {
                Text(failure)
                    .font(Kiln.Font.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else if case .running = model.state {
                placeholderBars
            } else if case .failed(let message) = model.state {
                Text(message)
                    .font(Kiln.Font.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Generating…")
                    .font(Kiln.Font.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Kiln.Space.xs)
        .background {
            RoundedRectangle(cornerRadius: Kiln.Radius.control, style: .continuous)
                .fill(Color.primary.opacity(Kiln.Opacity.cardFill))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            text.map { "\(label) response: \($0)" }
                ?? failure.map { "\(label) failed: \($0)" }
                ?? "\(label) response loading"
        )
    }

    /// Skeleton lines while we wait for the sidecar's tokens to arrive.
    /// Three small bars at decreasing opacity reads as "loading" without
    /// needing a text label that fights with the rest of the row.
    private var placeholderBars: some View {
        VStack(alignment: .leading, spacing: 4) {
            placeholderBar(width: 220, opacity: 0.18)
            placeholderBar(width: 180, opacity: 0.13)
            placeholderBar(width: 140, opacity: 0.09)
        }
    }

    private func placeholderBar(width: CGFloat, opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Color.primary.opacity(opacity))
            .frame(width: width, height: 9)
    }

    private var footer: some View {
        HStack(spacing: Kiln.Space.sm) {
            switch model.state {
            case .ready, .failed:
                Button {
                    Task { await model.runCompare() }
                } label: {
                    Label("Re-run", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
            case .running, .idle:
                EmptyView()
            }
            Spacer()
        }
    }
}
