import Foundation
import KilnCore
import Observation
import SwiftUI

@Observable
@MainActor
final class AppModel {
    var projects: [Project] = []
    var selectedProjectID: Project.ID?
    var sidebarVisibility: NavigationSplitViewVisibility = .all
    var prepareModel: PrepareModel?

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
        if let existing = prepareModel, case .running = existing.status {
            return
        }

        let folderName = folderURL.lastPathComponent
        let projectID: Project.ID
        if let id = selectedProjectID,
           let idx = projects.firstIndex(where: { $0.id == id }),
           projects[idx].stage == .readyToDrop {
            projects[idx].folderName = folderName
            projects[idx].name = folderName
            projects[idx].stage = .preparing
            projectID = projects[idx].id
        } else {
            let project = Project(name: folderName,
                                  folderName: folderName,
                                  stage: .preparing)
            projects.append(project)
            selectedProjectID = project.id
            projectID = project.id
        }

        let model = PrepareModel()
        prepareModel = model
        model.start(
            folderURL: folderURL,
            outputDirectory: Self.scratchDirectory(for: projectID)
        )
    }

    func cancelPrepare() {
        prepareModel?.cancel()
    }

    func resetPrepare() {
        prepareModel?.reset()
        prepareModel = nil
    }

    func continueToTraining(projectID: Project.ID) {
        guard let model = prepareModel, case .completed(let report) = model.status else { return }
        guard let idx = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[idx].ingestReport = report
        projects[idx].keptChunks = report.chunksAfterQuality
        projects[idx].totalChunks = report.chunksBeforeDedup
        projects[idx].stage = .training
        prepareModel = nil
    }

    func updateStage(of id: Project.ID, to stage: ProjectStage) {
        guard let idx = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[idx].stage = stage
        if stage == .complete {
            projects[idx].lastTrained = Date()
        }
    }

    static func scratchDirectory(for projectID: Project.ID) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base
            .appendingPathComponent("Kiln", isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
            .appendingPathComponent(projectID.uuidString, isDirectory: true)
            .appendingPathComponent("ingest", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
