import SwiftUI

/// Left pane — the project list. Section header, selectable rows, and a
/// footer button that mirrors ⌘N so the entry point is always visible.
struct SidebarView: View {
    @Bindable var model: AppModel

    var body: some View {
        List(selection: selectionBinding) {
            Section {
                ForEach(model.projects) { project in
                    ProjectCard(project: project)
                        .tag(Optional(project.id))
                }
            } header: {
                Text("Projects")
                    .font(Kiln.Font.caption)
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            newProjectFooter
        }
    }

    private var selectionBinding: Binding<Project.ID?> {
        Binding(
            get: { model.selectedProjectID },
            set: { newValue in
                withAnimation(Kiln.Motion.standard) {
                    model.select(newValue)
                }
            }
        )
    }

    private var newProjectFooter: some View {
        Button {
            withAnimation(Kiln.Motion.standard) {
                model.newProject()
            }
        } label: {
            HStack(spacing: Kiln.Space.xs) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: Kiln.Icon.small))
                    .foregroundStyle(.secondary)
                Text("New project")
                    .font(Kiln.Font.body)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("⌘N")
                    .font(Kiln.Font.mono)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, Kiln.Space.s)
            .padding(.vertical, Kiln.Space.xs + 2)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.thinMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
        .accessibilityLabel("New project")
        .accessibilityHint("Creates a blank project")
    }
}
