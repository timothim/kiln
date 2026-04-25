import Foundation
import KilnCore
import Observation
import SwiftUI

/// Saturday final push — settings model for the "Cloud features"
/// section. Holds the user's Anthropic API key (in Keychain), the
/// per-feature toggles (Voice Coach, Training Advisor, MCP server,
/// agent-driven ingestion), and the global "run locally" preference
/// that controls whether each feature uses Opus 4.7 or its local
/// fallback.
///
/// All cloud features default OFF. Nothing reaches Anthropic until
/// the user explicitly flips a toggle and supplies an API key. This
/// matches CLAUDE.md scope ("local-first, opt-in for cloud").

public enum CloudFeaturesSettingsKeys {
    public static let voiceCoachEnabled = "dev.kiln.cloud.voiceCoach.enabled"
    public static let voiceCoachLocalMode = "dev.kiln.cloud.voiceCoach.localMode"
    public static let trainingAdvisorEnabled = "dev.kiln.cloud.trainingAdvisor.enabled"
    public static let mcpServerEnabled = "dev.kiln.cloud.mcpServer.enabled"
    public static let mcpServerPort = "dev.kiln.cloud.mcpServer.port"
    public static let agentIngestionEnabled = "dev.kiln.cloud.agentIngestion.enabled"
    /// Keychain account for the Anthropic API key. Reusing the
    /// existing ``KeychainPassphraseStore`` infrastructure (see
    /// ``BackupSettings``) means we don't need a new wrapper.
    public static let keychainAccount = "anthropic-api-key"
    public static let keychainService = "dev.kiln.cloud-features"
}

@Observable
@MainActor
final class CloudFeaturesSettings {
    var voiceCoachEnabled: Bool {
        didSet { defaults.set(voiceCoachEnabled, forKey: CloudFeaturesSettingsKeys.voiceCoachEnabled) }
    }
    var voiceCoachLocalMode: Bool {
        didSet { defaults.set(voiceCoachLocalMode, forKey: CloudFeaturesSettingsKeys.voiceCoachLocalMode) }
    }
    var trainingAdvisorEnabled: Bool {
        didSet { defaults.set(trainingAdvisorEnabled, forKey: CloudFeaturesSettingsKeys.trainingAdvisorEnabled) }
    }
    var mcpServerEnabled: Bool {
        didSet { defaults.set(mcpServerEnabled, forKey: CloudFeaturesSettingsKeys.mcpServerEnabled) }
    }
    var mcpServerPort: Int {
        didSet { defaults.set(mcpServerPort, forKey: CloudFeaturesSettingsKeys.mcpServerPort) }
    }
    var agentIngestionEnabled: Bool {
        didSet { defaults.set(agentIngestionEnabled, forKey: CloudFeaturesSettingsKeys.agentIngestionEnabled) }
    }

    private(set) var apiKeyConfigured: Bool

    private let defaults: UserDefaults
    private let passphraseStore: PassphraseStore
    /// Service-scoped Keychain so the API key doesn't collide with
    /// the M9.A backup passphrase entries.
    private let keychainAccount: String

    public init(
        defaults: UserDefaults = .standard,
        passphraseStore: PassphraseStore = KeychainPassphraseStore(
            service: CloudFeaturesSettingsKeys.keychainService
        ),
        keychainAccount: String = CloudFeaturesSettingsKeys.keychainAccount
    ) {
        self.defaults = defaults
        self.passphraseStore = passphraseStore
        self.keychainAccount = keychainAccount
        self.voiceCoachEnabled = defaults.bool(forKey: CloudFeaturesSettingsKeys.voiceCoachEnabled)
        self.voiceCoachLocalMode = defaults.bool(forKey: CloudFeaturesSettingsKeys.voiceCoachLocalMode)
        self.trainingAdvisorEnabled = defaults.bool(forKey: CloudFeaturesSettingsKeys.trainingAdvisorEnabled)
        self.mcpServerEnabled = defaults.bool(forKey: CloudFeaturesSettingsKeys.mcpServerEnabled)
        let storedPort = defaults.integer(forKey: CloudFeaturesSettingsKeys.mcpServerPort)
        self.mcpServerPort = storedPort == 0 ? 7474 : max(1024, storedPort)
        self.agentIngestionEnabled = defaults.bool(forKey: CloudFeaturesSettingsKeys.agentIngestionEnabled)
        // Probe the keychain once at init; updated lazily as the user
        // types into / clears the field.
        let probed: Bool
        do {
            probed = try passphraseStore.getPassphrase(account: keychainAccount) != nil
        } catch {
            probed = false
        }
        self.apiKeyConfigured = probed
    }

    /// Save (or replace) the user's Anthropic API key in Keychain.
    /// Empty input is treated as a clear.
    public func setAPIKey(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try passphraseStore.deletePassphrase(account: keychainAccount)
            apiKeyConfigured = false
            return
        }
        try passphraseStore.setPassphrase(trimmed, account: keychainAccount)
        apiKeyConfigured = true
    }

    public func loadAPIKey() throws -> String? {
        try passphraseStore.getPassphrase(account: keychainAccount)
    }
}

/// SwiftUI panel for the Cloud features section. Sits inside the app's
/// Settings root alongside ``BackupSettingsView``.
struct CloudFeaturesSettingsView: View {
    @State var settings: CloudFeaturesSettings
    @State private var apiKeyInput: String = ""
    @State private var apiKeyStatus: APIKeyStatus = .unknown
    @State private var keyVisible: Bool = false

    enum APIKeyStatus: Equatable {
        case unknown
        case saved
        case cleared
        case error(String)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Kiln.Space.l) {
                header
                Divider().opacity(0.4)
                apiKeyRow
                Divider().opacity(0.4)
                featuresSection
                Spacer(minLength: 0)
                disclosure
            }
            .padding(Kiln.Space.l)
        }
        .frame(width: 480)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.xxs) {
            Text("Cloud features")
                .font(Kiln.Font.title)
            Text("Opt in to features that send a small slice of your project to Anthropic. Off by default.")
                .font(Kiln.Font.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var apiKeyRow: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.xs) {
            Text("Anthropic API key")
                .font(Kiln.Font.body.weight(.medium))
            Text("Stored in macOS Keychain. Never leaves this Mac except for direct API calls you trigger.")
                .font(Kiln.Font.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: Kiln.Space.xs) {
                Group {
                    if keyVisible {
                        TextField("sk-ant-…", text: $apiKeyInput)
                    } else {
                        SecureField("sk-ant-…", text: $apiKeyInput)
                    }
                }
                .textFieldStyle(.roundedBorder)
                Button(keyVisible ? "Hide" : "Show") { keyVisible.toggle() }
                    .controlSize(.small)
                Button("Save") { Task { saveAPIKey() } }
                    .controlSize(.small)
                    .disabled(apiKeyInput.isEmpty)
            }
            statusLine
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch apiKeyStatus {
        case .unknown:
            if settings.apiKeyConfigured {
                Text("API key on file in Keychain.").font(Kiln.Font.caption).foregroundStyle(.secondary)
            } else {
                Text("No API key configured.").font(Kiln.Font.caption).foregroundStyle(.tertiary)
            }
        case .saved:
            Label("Saved.", systemImage: "checkmark").font(Kiln.Font.caption).foregroundStyle(.green)
        case .cleared:
            Text("Key cleared.").font(Kiln.Font.caption).foregroundStyle(.secondary)
        case .error(let message):
            Text(message).font(Kiln.Font.caption).foregroundStyle(.red)
        }
    }

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.xs) {
            Text("Cloud features")
                .font(Kiln.Font.body.weight(.medium))
            Toggle("Voice Coach (post-export voice analysis)", isOn: $settings.voiceCoachEnabled)
            Toggle("Run Voice Coach locally (Qwen2.5 via Ollama)", isOn: $settings.voiceCoachLocalMode)
                .padding(.leading, Kiln.Space.m)
                .disabled(!settings.voiceCoachEnabled)
            Toggle("Training Advisor (Opus watches your training)", isOn: $settings.trainingAdvisorEnabled)
            Toggle("Expose voice as MCP server (connect to Claude.app)", isOn: $settings.mcpServerEnabled)
            Toggle("Agent-driven ingestion (Opus orchestrates source readers)", isOn: $settings.agentIngestionEnabled)
        }
    }

    private var disclosure: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.xxs) {
            Text("Local-first promise")
                .font(Kiln.Font.label)
                .kerning(0.44)
                .textCase(.uppercase)
                .foregroundStyle(.tertiary)
            Text("Every cloud feature here is opt-in. Your project never reaches Anthropic until you flip a toggle and run that feature.")
                .font(Kiln.Font.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func saveAPIKey() {
        do {
            try settings.setAPIKey(apiKeyInput)
            apiKeyStatus = apiKeyInput.isEmpty ? .cleared : .saved
            apiKeyInput = ""
        } catch {
            apiKeyStatus = .error("Could not save: \(error.localizedDescription)")
        }
    }
}

#Preview {
    CloudFeaturesSettingsView(
        settings: CloudFeaturesSettings(
            defaults: UserDefaults(suiteName: "preview") ?? .standard,
            passphraseStore: InMemoryPassphraseStore()
        )
    )
}
