import AppKit
import SwiftUI

// MARK: - Local UI-layer types
//
// Mirrors LEAD's KilnCore `KilnShare.Bundle { bundleURL, sizeBytes, sha256 }`.
// The UI adds `ShareIncludeOptions` — DATA can render the real manifest from
// those flags when wiring up `KilnShare.export` in M10.

struct ShareIncludeOptions: Equatable {
    var signatureCard: Bool
    var sourceManifest: Bool
    var readme: Bool

    static let recommended = ShareIncludeOptions(
        signatureCard: true,
        sourceManifest: false,   // off by default — users are unlikely to want the corpus manifest in a share
        readme: true
    )
}

struct ShareBundleSummary: Equatable {
    let filename: String
    let bundleURL: URL            // for "Reveal in Finder" from the success block
    let sizeBytes: Int
    let sha256Prefix: String      // first 12 chars, pretty-formatted
}

// MARK: - Share Export Sheet
//
// Modal for packaging a voice as a shareable `.kiln` bundle. Presented via
// `.sheet(isPresented:)` from the voice detail screen. Kept intentionally
// dense — the user already decided to export; this is a confirmation +
// options screen, not a second decision point.

struct ShareExportSheet: View {
    let voiceName: String
    let voiceTag: String
    let onExport: (ShareIncludeOptions) async -> ShareBundleSummary?
    let onCancel: () -> Void

    @State private var options: ShareIncludeOptions = .recommended
    @State private var isExporting = false
    @State private var result: ShareBundleSummary?
    @State private var copyFeedback: CopyFeedback?

    static let sheetWidth: CGFloat = 480

    var body: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.m) {
            header
            Divider()
            if let result {
                successBlock(result)
            } else {
                voiceBlock
                includeBlock
            }
            Spacer(minLength: 0)
            Divider()
            footer
        }
        .padding(Kiln.Space.l)
        .frame(width: Self.sheetWidth, alignment: .topLeading)
        .animation(Kiln.Motion.standard, value: result)
        .animation(Kiln.Motion.standard, value: isExporting)
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.xxs) {
            Text("Share your voice")
                .font(Kiln.Font.title)
            Text("Package the fused adapter and metadata as a single `.kiln` file. Anyone with Kiln can import it.")
                .font(Kiln.Font.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var voiceBlock: some View {
        HStack(alignment: .center, spacing: Kiln.Space.m) {
            VStack(alignment: .leading, spacing: Kiln.Space.xxs) {
                Text(voiceName)
                    .font(Kiln.Font.body.weight(.semibold))
                Text(voiceTag)
                    .font(Kiln.Font.mono)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(Kiln.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Kiln.Radius.card, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        }
    }

    private var includeBlock: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.xs) {
            SectionLabel(text: "Include")
            VStack(alignment: .leading, spacing: Kiln.Space.xxs) {
                requiredRow(title: "Fused adapter", detail: "LoRA weights merged into the base model.")
                requiredRow(title: "Modelfile",     detail: "Ollama recipe for serving the voice.")
                Toggle(isOn: $options.signatureCard) {
                    toggleLabel(title: "Signature card",
                                detail: "PNG of the style summary.")
                }
                .toggleStyle(.switch)
                .accessibilityLabel("Include signature card")
                .accessibilityHint("Adds a PNG render of the style summary to the bundle.")
                Toggle(isOn: $options.readme) {
                    toggleLabel(title: "README",
                                detail: "Plain-text import instructions.")
                }
                .toggleStyle(.switch)
                .accessibilityLabel("Include README")
                .accessibilityHint("Adds plain-text import instructions to the bundle.")
                Toggle(isOn: $options.sourceManifest) {
                    toggleLabel(title: "Source manifest",
                                detail: "SHA-256 list of corpus chunks that trained this voice. No text content is included.")
                }
                .toggleStyle(.switch)
                .accessibilityLabel("Include source manifest")
                .accessibilityHint("Adds a list of SHA-256 hashes for the training chunks. No original text leaves the device.")
            }
        }
    }

    private func successBlock(_ result: ShareBundleSummary) -> some View {
        VStack(alignment: .leading, spacing: Kiln.Space.m) {
            HStack(spacing: Kiln.Space.xs) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: Kiln.Icon.small + 2))
                    // System green is the macOS-native success semantic — DESIGN.md
                    // forbids `firing` on success ticks, and this checkmark is the
                    // demo's last-beat success state. Adapts to dark mode.
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                // The single permitted exclamation mark in the entire app —
                // DESIGN.md §Typography sanctions it on this exact screen.
                Text("Exported \(result.filename)!")
                    .font(Kiln.Font.body.weight(.semibold))
                Spacer(minLength: 0)
                Button {
                    revealInFinder(result.bundleURL)
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                        .font(Kiln.Font.label)
                        .kerning(0.44)
                        .textCase(.uppercase)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .accessibilityLabel("Reveal bundle in Finder")
            }
            VStack(alignment: .leading, spacing: Kiln.Space.xxs) {
                detailRow(label: "Size",   value: Self.formatBytes(result.sizeBytes))
                detailRow(label: "SHA-256", value: "\(result.sha256Prefix)…")
            }
            .padding(Kiln.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Kiln.Radius.card, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            }
            importInstructionsBlock(filename: result.filename)
        }
    }

    private func importInstructionsBlock(filename: String) -> some View {
        VStack(alignment: .leading, spacing: Kiln.Space.xs) {
            HStack {
                SectionLabel(text: "Your recipient runs")
                Spacer(minLength: 0)
                Button {
                    copyToPasteboard(Self.importCommand(filename: filename))
                } label: {
                    Label(copyFeedback == .copied ? "Copied" : "Copy",
                          systemImage: copyFeedback == .copied ? "checkmark" : "doc.on.doc")
                        .font(Kiln.Font.label)
                        .kerning(0.44)
                        .textCase(.uppercase)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .accessibilityLabel("Copy import command")
            }
            Text(Self.importCommand(filename: filename))
                .font(Kiln.Font.mono)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                // Bumped padding and opacity over the rest of the sheet — this
                // command is the literal next step the recipient runs, and the
                // demo needs it readable from a 4K screen recording.
                .padding(Kiln.Space.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: Kiln.Radius.sm, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                }
        }
    }

    // MARK: Footer / actions

    private var footer: some View {
        HStack(spacing: Kiln.Space.xs) {
            Spacer(minLength: 0)
            if result == nil {
                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .keyboardShortcut(.cancelAction)

                Button {
                    Task { await exportTapped() }
                } label: {
                    if isExporting {
                        Label("Exporting…", systemImage: "square.and.arrow.up")
                            .padding(.horizontal, Kiln.Space.xs)
                    } else {
                        Label("Export", systemImage: "square.and.arrow.up")
                            .padding(.horizontal, Kiln.Space.xs)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .controlSize(.regular)
                .disabled(isExporting)
                .keyboardShortcut(.defaultAction)
            } else {
                Button("Done") { onCancel() }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .controlSize(.regular)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: Helpers

    private func requiredRow(title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: Kiln.Space.xs) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: Kiln.Icon.small))
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(Kiln.Font.body)
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(Kiln.Font.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Text("Required")
                .font(Kiln.Font.label)
                .kerning(0.44)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
        }
    }

    private func toggleLabel(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(Kiln.Font.body)
                .foregroundStyle(.primary)
            Text(detail)
                .font(Kiln.Font.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(Kiln.Font.label)
                .kerning(0.44)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            Spacer(minLength: 0)
            Text(value)
                .font(Kiln.Font.mono)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    @MainActor
    private func exportTapped() async {
        isExporting = true
        let summary = await onExport(options)
        isExporting = false
        if let summary {
            result = summary
        }
    }

    private func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        copyFeedback = .copied
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            copyFeedback = nil
        }
    }

    private func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private static func importCommand(filename: String) -> String {
        "kiln import ~/Downloads/\(filename)"
    }

    private static func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.includesUnit = true
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private enum CopyFeedback: Equatable { case copied }
}

// MARK: - Shared section label

private struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Kiln.Font.label)
            .kerning(0.44)
            .foregroundStyle(.tertiary)
            .textCase(.uppercase)
    }
}

// MARK: - Previews

#Preview("Default — configurable") {
    ShareExportSheet(
        voiceName: "Tim — drafts",
        voiceTag: "kiln/tim-drafts:latest",
        onExport: { _ in
            try? await Task.sleep(for: .seconds(1))
            return ShareBundleSummary(
                filename: "tim-drafts.kiln",
                bundleURL: URL(fileURLWithPath: NSHomeDirectory())
                    .appendingPathComponent("Downloads/tim-drafts.kiln"),
                sizeBytes: 38 * 1024 * 1024,
                sha256Prefix: "a1f3c29be504"
            )
        },
        onCancel: {}
    )
    .frame(height: 560)
}

#Preview("Export returns nil — user cancelled save panel") {
    ShareExportSheet(
        voiceName: "Tim — drafts",
        voiceTag: "kiln/tim-drafts:latest",
        onExport: { _ in nil },
        onCancel: {}
    )
    .frame(height: 560)
}
