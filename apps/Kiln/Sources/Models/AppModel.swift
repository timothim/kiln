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
    var trainModel: TrainModel?
    var exportModel: ExportModel?
    var chatModel: ChatModel?

    /// Saved-voice library — drives the sidebar's bottom-pinned selector.
    /// Always non-nil so the selector has something to bind to at launch.
    let voicesModel: VoicesModel

    /// Injected so tests can supply a fake TrainingRunner. Nil in the default
    /// init path — production wiring resolves the Python sidecar launcher.
    private let trainingRunnerFactory: (@MainActor () -> TrainingRunner)?
    private let ollamaExporterFactory: (@MainActor () -> OllamaExporter)?
    private let ollamaClientFactory: (@MainActor () -> OllamaClient)?

    init(
        trainingRunnerFactory: (@MainActor () -> TrainingRunner)? = nil,
        ollamaExporterFactory: (@MainActor () -> OllamaExporter)? = nil,
        ollamaClientFactory: (@MainActor () -> OllamaClient)? = nil,
        voicesProvider: (any VoicesProvider)? = nil
    ) {
        self.trainingRunnerFactory = trainingRunnerFactory
        self.ollamaExporterFactory = ollamaExporterFactory
        self.ollamaClientFactory = ollamaClientFactory
        if let voicesProvider {
            self.voicesModel = VoicesModel(provider: voicesProvider)
        } else {
            self.voicesModel = VoicesModel()
        }
    }

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

    // MARK: - Ingest

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
        if let trainPath = report.outputPaths?.trainJSONL {
            projects[idx].preparedDatasetURL = URL(fileURLWithPath: trainPath)
        }
        projects[idx].stage = .training
        prepareModel = nil
        // Reset any stale TrainModel from a previous session so the Teach
        // empty-state shows cleanly.
        trainModel?.reset()
        trainModel = nil
    }

    // MARK: - Train

    func startTraining(projectID: Project.ID, voiceSplit: VoiceSplit? = nil) {
        guard let idx = projects.firstIndex(where: { $0.id == projectID }) else { return }
        guard let datasetURL = projects[idx].preparedDatasetURL else { return }
        if let existing = trainModel, case .running = existing.status { return }

        // Persist the configured split on the project so re-entering the Train
        // stage preserves selection (and so it rides on the TrainingRequest).
        if let voiceSplit {
            projects[idx].voiceSplit = voiceSplit
        }
        let resolvedSplit = projects[idx].voiceSplit

        let runDir = Self.runDirectory(for: projectID)
        // PR #23 Training Advisor wire — read the user's "Enable Training
        // Advisor" toggle from the canonical defaults keys defined in
        // ``CloudFeaturesSettingsKeys``. The earlier post-merge note
        // ("the CloudFeaturesSettings reads/writes the same defaults
        // keys") was correct in intent but used the wrong literal —
        // ``CloudFeaturesSettingsKeys.trainingAdvisorEnabled`` is the
        // dotted ``dev.kiln.cloud.trainingAdvisor.enabled`` form, not
        // the bare ``trainingAdvisorEnabled`` literal that was hardcoded
        // here. Fixing the audit's C4: toggle in Settings now actually
        // gates the advisor.
        let advisorEnabled = UserDefaults.standard.bool(
            forKey: CloudFeaturesSettingsKeys.trainingAdvisorEnabled
        )
        let advisorLocal = UserDefaults.standard.bool(
            forKey: CloudFeaturesSettingsKeys.voiceCoachLocalMode
        )
        let request = TrainingRequest(
            datasetURL: datasetURL,
            runDir: runDir,
            model: Self.defaultBaseModel(for: projects[idx].modelSize),
            voiceSplit: resolvedSplit,
            enableAdvisor: advisorEnabled,
            advisorMode: advisorLocal ? "local" : "cloud"
        )
        let model = TrainModel(runner: resolveTrainingRunner())
        trainModel = model
        model.start(request: request, voiceSplit: resolvedSplit)
    }

    func cancelTraining() {
        trainModel?.cancel()
    }

    func resetTraining() {
        trainModel?.reset()
        trainModel = nil
    }

    func continueFromTraining(projectID: Project.ID) {
        guard let model = trainModel, case .completed(let report) = model.status else { return }
        guard let idx = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[idx].trainingReport = report
        projects[idx].lastTrained = Date()
        projects[idx].stage = .complete
        trainModel = nil
    }

    // MARK: - Export

    func startExport(projectID: Project.ID) {
        guard let idx = projects.firstIndex(where: { $0.id == projectID }) else { return }
        guard let report = projects[idx].trainingReport else { return }
        if let existing = exportModel, case .running = existing.status { return }

        let userName = NSFullUserName().isEmpty ? projects[idx].name : NSFullUserName()
        let outputName = "kiln-\(projects[idx].slug)"
        let runDir = report.adapterURL.deletingLastPathComponent()
        let request = ExportRequest(
            model: Self.defaultBaseModel(for: projects[idx].modelSize),
            adapterURL: report.adapterURL,
            runDir: runDir,
            userName: userName,
            outputName: outputName,
            llamaCppDir: Self.llamaCppDir(),
            quantization: nil,
            skipGGUF: false,
            skipOllama: false
        )
        let model = ExportModel(exporter: resolveOllamaExporter())
        exportModel = model
        model.start(request: request)
    }

    func cancelExport() {
        exportModel?.cancel()
    }

    func dismissExport() {
        exportModel = nil
    }

    // MARK: - Chat

    func openChat(for projectID: Project.ID) {
        guard let idx = projects.firstIndex(where: { $0.id == projectID }) else { return }
        let modelName = "kiln-\(projects[idx].slug)"
        chatModel = ChatModel(modelName: modelName, client: resolveOllamaClient())
    }

    func closeChat() {
        chatModel?.cancel()
        chatModel = nil
    }

    // MARK: - Helpers

    func updateStage(of id: Project.ID, to stage: ProjectStage) {
        guard let idx = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[idx].stage = stage
        if stage == .complete {
            projects[idx].lastTrained = Date()
        }
    }

    private func resolveTrainingRunner() -> TrainingRunner {
        if let factory = trainingRunnerFactory {
            return factory()
        }
        let launcher = TrainerLauncher.uvRun(trainerPackageDir: Self.trainerPackageDir())
        return SubprocessTrainingRunner(launcher: launcher)
    }

    private func resolveOllamaExporter() -> OllamaExporter {
        if let factory = ollamaExporterFactory {
            return factory()
        }
        let launcher = TrainerLauncher.uvRun(trainerPackageDir: Self.trainerPackageDir())
        return SubprocessOllamaExporter(launcher: launcher)
    }

    private func resolveOllamaClient() -> OllamaClient {
        if let factory = ollamaClientFactory {
            return factory()
        }
        return URLSessionOllamaClient()
    }

    /// Best-effort resolver for a llama.cpp checkout. Respects the
    /// ``KILN_LLAMA_CPP_DIR`` env var, then falls back to a few common
    /// locations under the user's home directory. When none resolve the
    /// export stage will emit a friendly error event and the UI will show
    /// a recoverable failure.
    static func llamaCppDir() -> URL? {
        let fm = FileManager.default
        if let explicit = ProcessInfo.processInfo.environment["KILN_LLAMA_CPP_DIR"] {
            let url = URL(fileURLWithPath: explicit)
            if fm.fileExists(atPath: url.path) { return url }
        }
        let home = fm.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent("llama.cpp"),
            home.appendingPathComponent("Developer/llama.cpp"),
            URL(fileURLWithPath: "/opt/homebrew/Cellar/llama.cpp")
        ]
        return candidates.first { fm.fileExists(atPath: $0.path) }
    }

    static func scratchDirectory(for projectID: Project.ID) -> URL {
        let base = supportBase()
        let dir = base
            .appendingPathComponent("Kiln", isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
            .appendingPathComponent(projectID.uuidString, isDirectory: true)
            .appendingPathComponent("ingest", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func runDirectory(for projectID: Project.ID) -> URL {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let ts = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let dir = supportBase()
            .appendingPathComponent("Kiln", isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
            .appendingPathComponent(projectID.uuidString, isDirectory: true)
            .appendingPathComponent("runs", isDirectory: true)
            .appendingPathComponent(ts, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func supportBase() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }

    private static func defaultBaseModel(for size: Project.Size) -> String {
        switch size {
        case .small:  return "mlx-community/Qwen2.5-1.5B-Instruct-4bit"
        case .medium: return "mlx-community/Qwen2.5-3B-Instruct-4bit"
        case .large:  return "mlx-community/Qwen2.5-7B-Instruct-4bit"
        }
    }

    /// Locate the in-tree kiln_trainer Python package. Walks up from the
    /// running executable's directory — works for both `swift run` out of
    /// `apps/Kiln/build/...` and the final `Kiln.app` bundle when the
    /// package is shipped alongside.
    private static func trainerPackageDir() -> URL {
        let fm = FileManager.default
        let cwdProbe = URL(fileURLWithPath: fm.currentDirectoryPath)
            .appendingPathComponent("packages/kiln_trainer")
        let candidates: [URL] = [
            Bundle.main.bundleURL
                .deletingLastPathComponent()
                .appendingPathComponent("packages/kiln_trainer"),
            cwdProbe
        ]
        for url in candidates where fm.fileExists(atPath: url.path) {
            return url
        }
        // Last-ditch fallback — walk upward from cwd looking for `pyproject.toml`
        // inside a `packages/kiln_trainer` sibling. This handles being launched
        // from a child working dir in dev.
        var cursor = URL(fileURLWithPath: fm.currentDirectoryPath)
        for _ in 0..<6 {
            let probe = cursor.appendingPathComponent("packages/kiln_trainer")
            if fm.fileExists(atPath: probe.appendingPathComponent("pyproject.toml").path) {
                return probe
            }
            cursor.deleteLastPathComponent()
        }
        return cwdProbe
    }
}
