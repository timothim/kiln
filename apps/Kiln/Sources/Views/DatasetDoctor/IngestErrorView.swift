import SwiftUI
import KilnCore

/// Shown when PrepareModel.status is .failed. Humanized copy plus a retry
/// button that resets back to the drop zone.
struct IngestErrorView: View {
    let project: Project
    let error: PrepareModel.DisplayError
    let onReset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.l) {
            StageHeader(
                title: project.name,
                subtitle: nil,
                stage: project.stage
            )
            VStack(alignment: .leading, spacing: Kiln.Space.m) {
                HStack(spacing: Kiln.Space.xs) {
                    Image(systemName: iconName)
                        .font(.title2)
                        .foregroundStyle(iconColor)
                        .accessibilityHidden(true)
                    Text(headline)
                        .font(Kiln.Font.title)
                        .foregroundStyle(.primary)
                }
                Text(error.userFacingMessage)
                    .font(Kiln.Font.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Kiln.Space.l)
            .frame(maxWidth: 520, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Kiln.Radius.card, style: .continuous)
                    .fill(Kiln.Palette.surfaceSunken)
            )

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button(action: onReset) {
                    Text("Try another folder")
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityLabel("Try another folder")
            }
        }
        .padding(Kiln.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Headlines name the recovery, not the failure (DESIGN.md §Typography).
    /// The body text in `error.userFacingMessage` carries the explanation;
    /// the headline is the verb-first instruction.
    private var headline: String {
        switch error {
        case .cancelled: return "Cancelled — your work is safe"
        case .noExamplesGenerated: return "Add more text to your folder"
        case .directoryNotFound: return "Re-select your folder"
        case .outputDirectoryNotWritable: return "Free up some disk space"
        case .parserFailed: return "Try a different folder"
        case .other: return "Try another folder"
        }
    }

    private var iconName: String {
        switch error {
        case .cancelled: return "xmark.circle"
        case .noExamplesGenerated: return "tray"
        case .directoryNotFound: return "externaldrive.badge.xmark"
        case .outputDirectoryNotWritable: return "lock.slash"
        case .parserFailed, .other: return "exclamationmark.triangle"
        }
    }

    private var iconColor: Color {
        switch error {
        case .cancelled: return .secondary
        default: return Kiln.Palette.danger
        }
    }
}
