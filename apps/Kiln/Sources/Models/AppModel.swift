import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class AppModel {
    var projects: [Project] = []
    var selectedProjectID: Project.ID?
    var sidebarVisibility: NavigationSplitViewVisibility = .all

    var selectedProject: Project? {
        guard let id = selectedProjectID else { return nil }
        return projects.first { $0.id == id }
    }

    func newProject(name: String = "Untitled project") {
        let project = Project(name: name, stage: .readyToDrop)
        projects.append(project)
        selectedProjectID = project.id
    }

    func select(_ id: Project.ID?) {
        selectedProjectID = id
    }

    func ingest(folderURL: URL) {
        let folderName = folderURL.lastPathComponent
        if let id = selectedProjectID,
           let idx = projects.firstIndex(where: { $0.id == id }),
           projects[idx].stage == .readyToDrop {
            projects[idx].folderName = folderName
            projects[idx].name = folderName
            projects[idx].stage = .preparing
            return
        }

        let project = Project(name: folderName,
                              folderName: folderName,
                              stage: .preparing)
        projects.append(project)
        selectedProjectID = project.id
    }

    func updateStage(of id: Project.ID, to stage: ProjectStage) {
        guard let idx = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[idx].stage = stage
        if stage == .complete {
            projects[idx].lastTrained = Date()
        }
    }
}
