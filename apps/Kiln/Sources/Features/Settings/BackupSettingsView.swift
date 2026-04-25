import AppKit
import KilnCore
import Observation
import SwiftUI

/// Settings panel for the M9.A local encrypted-backup feature.
///
/// Two-line summary the user sees:
///   - Toggle: "Enable encrypted backups" (off by default per CLAUDE.md scope).
///   - Button: "Back up now" — prompts for a passphrase via NSAlert, runs the
///     backup, shows the bundle in Finder when it completes.
///
/// Cloud upload is intentionally not surfaced here — M9.A delivers local
/// backup only; the M9 plan has the cloud provider rationale documented as
/// a deferred follow-up.

/// Observable backing model for the panel. Keeps the actual filesystem
/// work behind ``backupNow(passphrase:)`` so the view can stay thin and
/// the model is unit-testable independently.
@Observable
@MainActor
final class BackupSettingsModel {
    enum Status: Equatable {
        case idle
        case running
        case succeeded(bundleURL: URL, lastBackupAt: String)
        case failed(message: String)
    }

    var enabled: Bool {
        didSet { defaults.set(enabled, forKey: BackupSettings.enabledKey) }
    }

    private(set) var status: Status = .idle
    private(set) var lastBackupISO8601: String?

    private let service: BackupService
    private let defaults: UserDefaults
    /// Where the backup data is sourced from for the "Back up now" button.
    /// Tests inject a temp dir; the production caller can hook this to the
    /// active project root once the project store is wired into Settings.
    var projectRootProvider: () -> URL?

    init(
        service: BackupService = DiskBackupService(),
        defaults: UserDefaults = .standard,
        projectRootProvider: @escaping () -> URL? = { nil }
    ) {
        self.service = service
        self.defaults = defaults
        self.projectRootProvider = projectRootProvider
        self.enabled = defaults.bool(forKey: BackupSettings.enabledKey)
        self.lastBackupISO8601 = defaults.string(forKey: BackupSettings.lastBackupISO8601Key)
    }

    /// Run a backup. Returns the bundle URL on success.
    func backupNow(passphrase: String, projectID: String) async {
        guard let projectRoot = projectRootProvider() else {
            status = .failed(message: "No project selected. Open a project first.")
            return
        }
        status = .running
        do {
            let url = try await service.backup(
                projectRoot: projectRoot,
                projectID: projectID,
                passphrase: passphrase,
                destinationDirectory: nil
            )
            let nowISO = ISO8601DateFormatter().string(from: Date())
            defaults.set(nowISO, forKey: BackupSettings.lastBackupISO8601Key)
            lastBackupISO8601 = nowISO
            status = .succeeded(bundleURL: url, lastBackupAt: nowISO)
        } catch BackupError.passphraseTooShort {
            status = .failed(message: "Passphrase must be at least \(BackupSettings.minPassphraseLength) characters.")
        } catch let err as BackupError {
            status = .failed(message: "Backup failed: \(String(describing: err))")
        } catch {
            status = .failed(message: "Backup failed: \(error.localizedDescription)")
        }
    }
}

struct BackupSettingsView: View {
    @State var model: BackupSettingsModel

    /// Width matches the rest of the macOS settings surface; below this and
    /// the passphrase NSAlert covers the whole panel.
    private static let panelWidth: CGFloat = 460

    var body: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.m) {
            header
            toggleRow
            actionRow
            statusRow
            footnote
        }
        .padding(Kiln.Space.l)
        .frame(width: Self.panelWidth)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.xxs) {
            Text("Backups")
                .font(Kiln.Font.title)
            Text("Encrypted local snapshots of your project. Off by default.")
                .font(Kiln.Font.body)
                .foregroundStyle(.secondary)
        }
    }

    private var toggleRow: some View {
        Toggle("Enable encrypted backups", isOn: $model.enabled)
            .toggleStyle(.switch)
            .accessibilityHint("Turns on encrypted local snapshots. Nothing leaves your machine.")
    }

    @ViewBuilder
    private var actionRow: some View {
        HStack(spacing: Kiln.Space.sm) {
            Button("Back up now") {
                Task { await runBackup() }
            }
            .disabled(!model.enabled || isRunning)
            .accessibilityHint("Encrypts the active project and writes a snapshot to disk.")
            if isRunning {
                ProgressView().controlSize(.small)
                    .accessibilityLabel("Backing up")
            }
        }
    }

    private var statusRow: some View {
        Group {
            switch model.status {
            case .idle:
                EmptyView()
            case .running:
                Text("Backing up — your work stays on this machine.")
                    .font(Kiln.Font.body)
                    .foregroundStyle(.secondary)
            case .succeeded(let url, let stamp):
                VStack(alignment: .leading, spacing: Kiln.Space.xxs) {
                    Text("Backed up \(formattedTimestamp(stamp))")
                        .font(Kiln.Font.body)
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    .controlSize(.small)
                    .accessibilityLabel("Show backup bundle in Finder")
                }
            case .failed(let message):
                Text(message)
                    .font(Kiln.Font.body)
                    .foregroundStyle(Kiln.Palette.danger)
            }
        }
    }

    @ViewBuilder
    private var footnote: some View {
        if let stamp = model.lastBackupISO8601 {
            Text("Last successful backup: \(formattedTimestamp(stamp))")
                .font(Kiln.Font.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("No backups yet — turn on encrypted backups above to start.")
                .font(Kiln.Font.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Format an ISO8601 timestamp as a relative-then-absolute string.
    /// "2 minutes ago" reads better in a settings pane than the raw stamp.
    private func formattedTimestamp(_ iso: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: iso) else { return iso }
        return date.formatted(.relative(presentation: .named))
    }

    private var isRunning: Bool {
        if case .running = model.status { return true }
        return false
    }

    /// Prompts the user for a passphrase via NSAlert, then runs the backup.
    /// Mirrors the Apple-native pattern used elsewhere in the app for
    /// blocking prompts; SwiftUI alerts can't host a SecureField cleanly.
    private func runBackup() async {
        guard let passphrase = await Self.promptForPassphrase() else { return }
        // Project ID is a placeholder until the project store is wired in;
        // the M9.A scope says "Settings UI surface" and the caller hooking
        // `projectRootProvider` is responsible for supplying the real id.
        await model.backupNow(passphrase: passphrase, projectID: "default")
    }

    @MainActor
    static func promptForPassphrase() async -> String? {
        let alert = NSAlert()
        alert.messageText = "Backup passphrase"
        alert.informativeText = "Pick a passphrase to encrypt this backup. You will need it to restore. There is no recovery — losing the passphrase means losing the backup."
        alert.addButton(withTitle: "Back Up")
        alert.addButton(withTitle: "Cancel")
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.placeholderString = "At least \(BackupSettings.minPassphraseLength) characters"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }
}

#Preview("Idle") {
    BackupSettingsView(
        model: BackupSettingsModel(
            service: DiskBackupService(),
            defaults: UserDefaults(suiteName: "preview-idle") ?? .standard
        )
    )
}
