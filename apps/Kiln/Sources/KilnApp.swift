import SwiftUI

@main
struct KilnApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Kiln") {
            RootView(model: model)
                // The Claude Design package is light-first — warm cream paper,
                // warm-brown foreground tiers, no dark variants specified.
                // Pinning to `.light` keeps the paper aesthetic when macOS is
                // in dark mode (otherwise the synthesized warm-dark variants
                // read as a generic dark theme, not the design's intent).
                .preferredColorScheme(.light)
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
                .preferredColorScheme(.light)
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
        // Audit post-merge: widen so the four tab labels never wrap and
        // the Behind-the-Scenes long-form copy doesn't compress.
        .frame(minWidth: 720, idealWidth: 820, minHeight: 640, idealHeight: 720)
    }
}
