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
    }
}
