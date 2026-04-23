import SwiftUI
import KilnCore

/// Shown when PrepareModel.status is .failed. Humanized copy plus a retry
/// button that resets back to the drop zone.
struct IngestErrorView: View {
    let project: Project
    let error: PrepareModel.DisplayError
    let onReset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.m) {
            StageHeader(
                title: project.name,
                subtitle: nil,
                stage: project.stage
            )
            VStack(alignment: .leading, spacing: Kiln.Space.s) {
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
            .padding(Kiln.Space.m)
            .frame(maxWidth: 520, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Kiln.Radius.card, style: .continuous)
                    .fill(Kiln.Palette.accentWash)
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
        .padding(Kiln.Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var headline: String {
        switch error {
        case .cancelled: return "Cancelled"
        case .noExamplesGenerated: return "Nothing to learn from"
        case .directoryNotFound: return "Folder unavailable"
        case .outputDirectoryNotWritable: return "Cannot write scratch files"
        case .parserFailed: return "Could not read the folder"
        case .other: return "Something went wrong"
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
        default: return Kiln.Palette.accent
        }
    }
}
