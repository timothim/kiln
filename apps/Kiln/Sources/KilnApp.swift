import SwiftUI

@main
struct KilnApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Kiln") {
            RootView(model: model)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Project") {
                    withAnimation(Kiln.Motion.standard) {
                        model.newProject()
                    }
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            SidebarCommands()
        }

        // Audit C1: Settings scene wires the four panels — Cloud features
        // (API key + per-feature toggles), Backup, MCP server, and the
        // Behind-the-Scenes "About Opus" page. ⌘, opens it. Without
        // this scene every cloud feature was unreachable from a running
        // app even though the panel views, models, and tests existed.
        Settings {
            SettingsRoot(model: model)
        }
    }
}

/// Wraps the four Settings tabs. Lives at the App level so the model
/// refs are stable across re-opens of the Settings window.
private struct SettingsRoot: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView {
            CloudFeaturesSettingsView(settings: model.cloudSettings)
                .tabItem { Label("Cloud features", systemImage: "cloud") }

            BackupSettingsView(model: model.backupSettingsModel)
                .tabItem { Label("Backup", systemImage: "lock.shield") }

            MCPServerSettingsView(
                model: model.mcpServerSettingsModel,
                voiceName: model.defaultMCPVoiceName
            )
            .tabItem { Label("MCP server", systemImage: "network") }

            BehindTheScenesView()
                .tabItem { Label("About Opus", systemImage: "sparkles") }
        }
        .frame(minWidth: 560, minHeight: 600)
    }
}
