import SwiftUI

// MARK: - Local UI-layer types
//
// Mirrors LEAD's KilnCore `NativeImporters.Source` case-for-case. The UI also
// tracks `ImportPermissionState` and a simple `ImportProgress` — DATA can
// wire these to `NativeImporters.ImportProgress` in M8 once the real Messages
// / Notes / Mail / Obsidian adapters land.

enum ImportSource: String, CaseIterable, Identifiable {
    case messages
    case notes
    case mail
    case obsidian

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .messages: return "Messages"
        case .notes:    return "Notes"
        case .mail:     return "Mail"
        case .obsidian: return "Obsidian"
        }
    }

    var systemImage: String {
        switch self {
        case .messages: return "message.fill"
        case .notes:    return "note.text"
        case .mail:     return "envelope.fill"
        case .obsidian: return "square.grid.3x3.fill"
        }
    }

    /// Short one-liner shown under the button title. Longer permission copy
    /// lives in the per-source view so it can wrap generously.
    var subtitle: String {
        switch self {
        case .messages: return "iMessage and SMS history"
        case .notes:    return "Apple Notes, including locked pins"
        case .mail:     return "Mail.app mbox archives"
        case .obsidian: return "Obsidian vaults with wikilinks"
        }
    }
}

enum ImportPermissionState: Equatable {
    case notRequested
    case granted
    case denied(reason: String)
}

struct ImportProgress: Equatable {
    let itemsSeen: Int
    let itemsAccepted: Int

    static let zero = ImportProgress(itemsSeen: 0, itemsAccepted: 0)
}

// MARK: - Import Provider
//
// Thin protocol the buttons talk to. Real impl will live in KilnCore and wrap
// `NativeImporters.importFrom(_:progress:)`; for Phase 3 the previews and the
// per-source views compose against `MockImportProvider` which streams a
// deterministic progress curve.

protocol ImportProvider {
    @MainActor func requestPermission(for source: ImportSource) async -> ImportPermissionState
    @MainActor func runImport(for source: ImportSource, progress: @Sendable (ImportProgress) -> Void) async throws
}

// MARK: - Import Source Button
//
// Shared affordance used by MessagesImportView / NotesImportView / future
// Mail and Obsidian views. Handles the three-state flow:
//   1. ask permission (button label: "Grant access")
//   2. run import     (button label: "Import \(source.displayName)")
//   3. show a progress row while active
// Permission denial is sticky — the caller has to toggle it back via the
// `System Settings...` escape hatch if macOS revokes the entitlement.

struct ImportSourceButton: View {
    let source: ImportSource
    let provider: ImportProvider
    let onComplete: (ImportProgress) -> Void

    @State private var permission: ImportPermissionState = .notRequested
    @State private var isRunning = false
    @State private var progress: ImportProgress = .zero
    @State private var lastError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.xs) {
            titleRow
            if isRunning {
                progressRow
            } else if case let .denied(reason) = permission {
                denialRow(reason: reason)
            } else if let error = lastError {
                errorRow(message: error)
            } else {
                actionRow
            }
        }
        .padding(Kiln.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Kiln.Radius.card, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        }
        .animation(Kiln.Motion.standard, value: isRunning)
        .animation(Kiln.Motion.standard, value: permission)
    }

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: Kiln.Space.xs) {
            Image(systemName: source.systemImage)
                .font(.system(size: Kiln.Icon.small, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: Kiln.Icon.small)
            VStack(alignment: .leading, spacing: 0) {
                Text(source.displayName)
                    .font(Kiln.Font.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(source.subtitle)
                    .font(Kiln.Font.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var actionRow: some View {
        HStack(spacing: Kiln.Space.xs) {
            Spacer(minLength: 0)
            Button(actionLabel) {
                Task { await actionTapped() }
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
    }

    private var progressRow: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.xxs) {
            Text("Importing — \(progress.itemsAccepted) of \(progress.itemsSeen) items kept")
                .font(Kiln.Font.caption)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .animation(Kiln.Motion.standard, value: progress.itemsSeen)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(Kiln.Palette.firing)
                        .frame(width: barWidth(in: geo.size.width))
                        .animation(Kiln.Motion.standard, value: progress.itemsAccepted)
                }
            }
            .frame(height: Kiln.Space.xxs)
        }
    }

    private func denialRow(reason: String) -> some View {
        HStack(alignment: .top, spacing: Kiln.Space.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: Kiln.Icon.small))
                .foregroundStyle(Kiln.Palette.danger)
            VStack(alignment: .leading, spacing: Kiln.Space.xxs) {
                Text(reason)
                    .font(Kiln.Font.caption)
                    .foregroundStyle(.secondary)
                Button("Open System Settings...") {
                    openPrivacySettings()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
            Spacer(minLength: 0)
        }
    }

    private func errorRow(message: String) -> some View {
        HStack(spacing: Kiln.Space.xs) {
            Text(message)
                .font(Kiln.Font.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button("Retry") {
                lastError = nil
                Task { await actionTapped() }
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
    }

    private var actionLabel: String {
        switch permission {
        case .notRequested, .denied: return "Grant access"
        case .granted:                return "Import \(source.displayName)"
        }
    }

    private func barWidth(in total: CGFloat) -> CGFloat {
        let seen = max(1, progress.itemsSeen)
        let ratio = min(1.0, Double(progress.itemsAccepted) / Double(seen))
        return max(0, total * CGFloat(ratio))
    }

    @MainActor
    private func actionTapped() async {
        lastError = nil
        switch permission {
        case .notRequested, .denied:
            permission = await provider.requestPermission(for: source)
        case .granted:
            await runImport()
        }
    }

    @MainActor
    private func runImport() async {
        isRunning = true
        progress = .zero
        do {
            try await provider.runImport(for: source) { snapshot in
                Task { @MainActor in progress = snapshot }
            }
            isRunning = false
            onComplete(progress)
        } catch {
            isRunning = false
            lastError = "Import failed: \(error.localizedDescription)"
        }
    }

    private func openPrivacySettings() {
        // Deep-links into the per-source pane in System Settings. Exact anchors
        // are listed in .claude/skills/macos-data-sources/SKILL.md; Phase 3
        // uses the top-level Privacy pane as a safe default.
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Mock Import Provider

final class MockImportProvider: ImportProvider {
    enum Scenario {
        case granted
        case deniedOnce          // denies first request, grants on retry
        case alwaysDenied(reason: String)
        case failsMidImport(message: String)
    }

    var scenario: Scenario
    private var permissionAsked = 0

    init(scenario: Scenario = .granted) {
        self.scenario = scenario
    }

    @MainActor
    func requestPermission(for _: ImportSource) async -> ImportPermissionState {
        try? await Task.sleep(for: .milliseconds(400))
        permissionAsked += 1
        switch scenario {
        case .granted, .failsMidImport:
            return .granted
        case .deniedOnce:
            return permissionAsked == 1
                ? .denied(reason: "Full Disk Access is required. You can grant it in System Settings.")
                : .granted
        case let .alwaysDenied(reason):
            return .denied(reason: reason)
        }
    }

    @MainActor
    func runImport(for _: ImportSource, progress: @Sendable (ImportProgress) -> Void) async throws {
        let totalItems = 240
        for i in stride(from: 0, through: totalItems, by: 8) {
            try await Task.sleep(for: .milliseconds(60))
            if case let .failsMidImport(message) = scenario, i >= totalItems / 2 {
                throw MockImportError.midImportFailure(message)
            }
            let kept = Int(Double(i) * 0.78)
            progress(ImportProgress(itemsSeen: i, itemsAccepted: kept))
        }
    }

    enum MockImportError: LocalizedError {
        case midImportFailure(String)
        var errorDescription: String? {
            if case let .midImportFailure(m) = self { return m }
            return nil
        }
    }
}

// MARK: - Previews

#Preview("Messages — fresh (not requested)") {
    ImportSourceButton(
        source: .messages,
        provider: MockImportProvider(scenario: .granted),
        onComplete: { _ in }
    )
    .padding(Kiln.Space.l)
    .frame(width: 460)
}

#Preview("Notes — permission denied") {
    ImportSourceButton(
        source: .notes,
        provider: MockImportProvider(scenario: .alwaysDenied(
            reason: "Kiln needs Automation permission for Notes to read your locked notes."
        )),
        onComplete: { _ in }
    )
    .padding(Kiln.Space.l)
    .frame(width: 460)
}

#Preview("Mail — mid-import failure") {
    ImportSourceButton(
        source: .mail,
        provider: MockImportProvider(scenario: .failsMidImport(
            message: "Mailbox archive is corrupt at record 124."
        )),
        onComplete: { _ in }
    )
    .padding(Kiln.Space.l)
    .frame(width: 460)
}
