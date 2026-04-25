import SwiftUI

/// Top-level scene content. Switches between the launch drop zone (no projects)
/// and the three-pane workspace (one or more projects). The switch is
/// transitioned with Kiln.Motion.stageTransition so the first project creation
/// reads as a crossfade rather than a cut.
struct RootView: View {
    @Bindable var model: AppModel

    var body: some View {
        ZStack {
            if model.projects.isEmpty {
                EmptyDropView(model: model)
                    .transition(.opacity)
            } else {
                WorkspaceView(model: model)
                    .transition(Kiln.Motion.stageTransition)
            }
        }
        .frame(minWidth: Kiln.Layout.minWindowWidth,
               minHeight: Kiln.Layout.minWindowHeight)
    }
}

/// Three-pane layout: sidebar (projects) · center (stage router) · detail (stage-specific).
struct WorkspaceView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationSplitView(columnVisibility: $model.sidebarVisibility) {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(
                    min: Kiln.Layout.sidebarMinWidth,
                    ideal: Kiln.Layout.sidebarIdeal,
                    max: Kiln.Layout.sidebarMaxWidth
                )
        } content: {
            StageRouterView(model: model)
                .frame(minWidth: Kiln.Layout.centerMinWidth)
        } detail: {
            DetailView(project: model.selectedProject, model: model)
                .navigationSplitViewColumnWidth(
                    min: Kiln.Layout.detailMinWidth,
                    ideal: Kiln.Layout.detailIdeal
                )
        }
        .navigationSplitViewStyle(.balanced)
    }
}
