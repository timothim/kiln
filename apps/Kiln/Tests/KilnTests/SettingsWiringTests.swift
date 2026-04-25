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

    // MARK: - Audit C2 regression: Voice Coach open / close lifecycle

    func test_openVoiceCoach_constructs_model_and_input_from_training_report() {
        let app = AppModel()
        let adapterURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kiln-c2-test-adapter.safetensors")
        FileManager.default.createFile(atPath: adapterURL.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: adapterURL) }

        var project = Project(name: "VC test", stage: .complete)
        project.trainingReport = TrainingReport(
            adapterURL: adapterURL,
            itersCompleted: 200,
            totalIters: 200,
            finalLoss: 1.234,
            finalValLoss: 1.567,
            wallClockSec: 312.5,
            interrupted: false,
            partialCheckpoint: false
        )
        app.projects = [project]
        XCTAssertNil(app.voiceCoachModel)

        app.openVoiceCoach(for: project.id)
        XCTAssertNotNil(app.voiceCoachModel, "openVoiceCoach must populate voiceCoachModel")
        XCTAssertNotNil(app.voiceCoachInput)
        // Snapshot carries fields we sliced from the training report.
        XCTAssertEqual(app.voiceCoachInput?.styleSignature["voice_name"], .string("VC test"))
        XCTAssertEqual(app.voiceCoachInput?.styleSignature["iters_completed"], .number(200))
        XCTAssertEqual(app.voiceCoachInput?.styleSignature["final_train_loss"], .number(1.234))
    }

    func test_openVoiceCoach_is_noop_without_training_report() {
        let app = AppModel()
        let project = Project(name: "No-report", stage: .training)   // no trainingReport
        app.projects = [project]
        app.openVoiceCoach(for: project.id)
        XCTAssertNil(app.voiceCoachModel)
        XCTAssertNil(app.voiceCoachInput)
    }

    func test_closeVoiceCoach_clears_state() {
        let app = AppModel()
        let adapterURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kiln-c2-close-test.safetensors")
        FileManager.default.createFile(atPath: adapterURL.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: adapterURL) }

        var project = Project(name: "Close test", stage: .complete)
        project.trainingReport = TrainingReport(
            adapterURL: adapterURL,
            itersCompleted: 1, totalIters: 1,
            finalLoss: nil, finalValLoss: nil,
            wallClockSec: 1, interrupted: false, partialCheckpoint: false
        )
        app.projects = [project]

        app.openVoiceCoach(for: project.id)
        XCTAssertNotNil(app.voiceCoachModel)
        app.closeVoiceCoach()
        XCTAssertNil(app.voiceCoachModel)
        XCTAssertNil(app.voiceCoachInput)
    }
}
