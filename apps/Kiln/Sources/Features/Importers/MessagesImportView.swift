import SwiftUI

// MARK: - Messages Import View
//
// Stand-alone permission explainer + import flow for Messages (chat.db). This
// is the "what and why" screen the drop-folder pipeline doesn't need — the
// drop zone speaks for itself, but asking for Full Disk Access does not.
//
// The microcopy is deliberately concrete: naming the actual file (chat.db)
// and naming the System Settings path ("Privacy & Security → Full Disk
// Access") earns more trust than a vague "we need permission."

struct MessagesImportView: View {
    let provider: ImportProvider
    let onComplete: (ImportProgress) -> Void

    @State private var lastImport: ImportProgress?

    var body: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.m) {
            header
            explainer
            ImportSourceButton(
                source: .messages,
                provider: provider,
                onComplete: { result in
                    lastImport = result
                    onComplete(result)
                }
            )
            if let last = lastImport {
                summaryRow(last)
            }
        }
        .padding(Kiln.Space.l)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.xxs) {
            Text("Import from Messages")
                .font(Kiln.Font.title)
            Text("Your iMessage and SMS history is a strong signal for how you actually write.")
                .font(Kiln.Font.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var explainer: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.xs) {
            bulletRow(systemImage: "lock.shield",
                      title: "Full Disk Access",
                      body: "Kiln reads ~/Library/Messages/chat.db directly. Enable the permission in System Settings → Privacy & Security → Full Disk Access and restart Kiln.")
            bulletRow(systemImage: "person.2",
                      title: "Only your outgoing messages",
                      body: "Kiln ignores messages sent by other people. Only your replies are used to shape the voice.")
            bulletRow(systemImage: "externaldrive",
                      title: "Nothing leaves your Mac",
                      body: "Messages are parsed locally, deduped, filtered for quality, and added to the training corpus. Kiln does not sync to iCloud or make any network requests during import.")
        }
        .padding(Kiln.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Kiln.Radius.card, style: .continuous)
                .fill(Color.primary.opacity(Kiln.Opacity.cardFill))
        }
    }

    private func bulletRow(systemImage: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: Kiln.Space.xs) {
            Image(systemName: systemImage)
                .font(.system(size: Kiln.Icon.small, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: Kiln.Icon.small, alignment: .center)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: Kiln.Space.xxs) {
                Text(title)
                    .font(Kiln.Font.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(body)
                    .font(Kiln.Font.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private func summaryRow(_ result: ImportProgress) -> some View {
        HStack(spacing: Kiln.Space.xs) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: Kiln.Icon.small))
                .foregroundStyle(Kiln.Palette.firing)
            Text("Added \(result.itemsAccepted) messages to your corpus (\(result.itemsSeen) scanned).")
                .font(Kiln.Font.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .transition(.opacity)
    }
}

// MARK: - Previews

#Preview("Ready — grants on tap") {
    MessagesImportView(
        provider: MockImportProvider(scenario: .granted),
        onComplete: { _ in }
    )
    .frame(width: 560, height: 520)
}

#Preview("First tap denies, retry grants") {
    MessagesImportView(
        provider: MockImportProvider(scenario: .deniedOnce),
        onComplete: { _ in }
    )
    .frame(width: 560, height: 520)
}
