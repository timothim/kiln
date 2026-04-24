import SwiftUI

/// Left pane — the project list. Section header, selectable rows, and a
/// bottom inset that stacks the voice selector above the "New project"
/// footer so the active voice is visible at a glance regardless of which
/// project is open.
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
            VStack(spacing: 0) {
                Divider()
                voiceSelectorFooter
                Divider()
                newProjectFooter
            }
            .background(.thinMaterial)
        }
        .task {
            await model.voicesModel.refresh()
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

    private var voiceSelectorFooter: some View {
        VoiceSelectorView(
            voices: model.voicesModel.voices,
            activeID: model.voicesModel.activeID,
            onSelect: { id in
                Task { await model.voicesModel.activate(id) }
            },
            onManage: {
                // M8 placeholder — a dedicated "Manage voices" surface lands
                // with the Ollama-backed provider. No-op for now so the menu
                // entry doesn't dangle, but the user doesn't get sent
                // anywhere that isn't built yet.
            }
        )
        .padding(.horizontal, Kiln.Space.m)
        .padding(.vertical, Kiln.Space.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
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
            .padding(.horizontal, Kiln.Space.m)
            .padding(.vertical, Kiln.Space.xs + 2)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("New project")
        .accessibilityHint("Creates a blank project")
    }
}
