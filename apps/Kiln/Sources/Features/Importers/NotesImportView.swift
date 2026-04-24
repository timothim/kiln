import SwiftUI

// MARK: - Notes Import View
//
// Stand-alone permission explainer + import flow for Apple Notes. Notes is
// reached via AppleScript automation — a different permission class than
// Messages' Full Disk Access — so the copy walks the user through a separate
// System Settings path.

struct NotesImportView: View {
    let provider: ImportProvider
    let onComplete: (ImportProgress) -> Void

    @State private var lastImport: ImportProgress?

    var body: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.m) {
            header
            explainer
            ImportSourceButton(
                source: .notes,
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
            Text("Import from Notes")
                .font(Kiln.Font.title)
            Text("Notes captures your thinking voice — the one you use when nobody else is reading.")
                .font(Kiln.Font.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var explainer: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.xs) {
            bulletRow(systemImage: "hand.tap",
                      title: "Automation permission",
                      body: "Kiln asks Notes to list your notes via AppleScript. Enable it in System Settings → Privacy & Security → Automation → Kiln → Notes.")
            bulletRow(systemImage: "lock.open",
                      title: "Locked notes stay locked",
                      body: "Kiln reads only unlocked notes. Locked notes are skipped entirely — even if you are signed in, Kiln will not prompt for your password.")
            bulletRow(systemImage: "tray.and.arrow.down",
                      title: "Folders you pick",
                      body: "Choose one or more folders after granting access. You can re-run the import later to pick up newly written notes; Kiln dedupes against what is already in the corpus.")
        }
        .padding(Kiln.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Kiln.Radius.card, style: .continuous)
                .fill(Color.primary.opacity(0.04))
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
            Text("Added \(result.itemsAccepted) notes to your corpus (\(result.itemsSeen) scanned).")
                .font(Kiln.Font.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .transition(.opacity)
    }
}

// MARK: - Previews

#Preview("Ready — grants on tap") {
    NotesImportView(
        provider: MockImportProvider(scenario: .granted),
        onComplete: { _ in }
    )
    .frame(width: 560, height: 520)
}

#Preview("Always denied — user must fix in settings") {
    NotesImportView(
        provider: MockImportProvider(scenario: .alwaysDenied(
            reason: "Automation permission for Notes was not granted."
        )),
        onComplete: { _ in }
    )
    .frame(width: 560, height: 520)
}
