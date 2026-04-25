import XCTest
import KilnCore
@testable import Kiln

/// Audit C1 regression: the four Settings panel models must be reachable
/// from ``AppModel`` without crashing or hitting external services.
/// Pre-fix, these models existed but had no AppModel-level entry point;
/// this test guards the wiring against future regression.
@MainActor
final class SettingsWiringTests: XCTestCase {

    func test_cloudSettings_is_constructable() {
        let app = AppModel()
        // Reading the toggles should not crash even when no defaults are set.
        XCTAssertNotNil(app.cloudSettings)
        // Default state is off for every cloud feature.
        XCTAssertFalse(app.cloudSettings.voiceCoachEnabled)
        XCTAssertFalse(app.cloudSettings.trainingAdvisorEnabled)
        XCTAssertFalse(app.cloudSettings.mcpServerEnabled)
        XCTAssertFalse(app.cloudSettings.agentIngestionEnabled)
    }

    func test_backupSettingsModel_is_constructable() {
        let app = AppModel()
        XCTAssertNotNil(app.backupSettingsModel)
        // Default-off; user has to opt in.
        XCTAssertFalse(app.backupSettingsModel.enabled)
    }

    func test_mcpServerSettingsModel_is_constructable_and_default_voice_resolves() {
        let app = AppModel()
        XCTAssertNotNil(app.mcpServerSettingsModel)
        let voice = app.defaultMCPVoiceName
        XCTAssertTrue(voice.hasPrefix("kiln-"), "expected kiln-<slug>, got \(voice)")
        XCTAssertFalse(voice.contains(" "), "voice name must be slug-safe")
        // Status starts stopped — opening the Settings window must not
        // auto-spawn the server.
        if case .stopped = app.mcpServerSettingsModel.status {
            // expected
        } else {
            XCTFail("MCP server should start in .stopped, got \(app.mcpServerSettingsModel.status)")
        }
    }

    func test_settings_models_are_stable_across_repeated_access() {
        // The Settings window can be closed and re-opened. Each access
        // of cloudSettings/backupSettingsModel/mcpServerSettingsModel
        // must return the same instance so user state survives.
        let app = AppModel()
        XCTAssertTrue(app.cloudSettings === app.cloudSettings)
        XCTAssertTrue(app.backupSettingsModel === app.backupSettingsModel)
        XCTAssertTrue(app.mcpServerSettingsModel === app.mcpServerSettingsModel)
        XCTAssertTrue(app.mcpServerManager === app.mcpServerManager)
    }

    func test_defaultMCPVoiceName_uses_project_slug_when_a_project_is_selected() {
        let app = AppModel()
        var project = Project(name: "My Voice 2026", stage: .complete)
        project.folderName = "My Voice 2026"
        app.projects = [project]
        app.selectedProjectID = project.id
        // Project.slug is the kebab-case of the name; the MCP voice name
        // is "kiln-<slug>". Test against that contract.
        XCTAssertEqual(app.defaultMCPVoiceName, "kiln-\(project.slug)")
    }

    func test_settings_panels_are_constructable_via_the_root_view() {
        // The actual SettingsRoot view is private. We exercise the
        // public-facing views directly with the same models the App
        // hands them; this catches initializer drift.
        let app = AppModel()
        _ = CloudFeaturesSettingsView(settings: app.cloudSettings)
        _ = BackupSettingsView(model: app.backupSettingsModel)
        _ = MCPServerSettingsView(
            model: app.mcpServerSettingsModel,
            voiceName: app.defaultMCPVoiceName
        )
        _ = BehindTheScenesView()
    }
}
