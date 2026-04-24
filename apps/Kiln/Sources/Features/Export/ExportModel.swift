import Foundation
import KilnCore
import Observation

/// Observable state machine for the Ollama export pipeline. Drives a
/// four-stage progress UI (fuse → GGUF → Modelfile → Ollama) and surfaces
/// the final model name once the daemon confirms.
@Observable
@MainActor
final class ExportModel {
    enum Status: Equatable {
        case idle
        case running
        case completed(modelName: String)
        case failed(message: String, recoverable: Bool)
    }

    struct Progress: Equatable {
        var fuse: StageState = .pending
        var gguf: StageState = .pending
        var modelfile: StageState = .pending
        var ollama: StageState = .pending
    }

    enum StageState: Equatable {
        case pending
        case running
        case done(artifact: String)
        case failed(message: String)
    }

    var status: Status = .idle
    var progress: Progress = Progress()

    private let exporter: OllamaExporter
    private var streamTask: Task<Void, Never>?

    init(exporter: OllamaExporter) {
        self.exporter = exporter
    }

    func start(request: ExportRequest) {
        if case .running = status { return }
        status = .running
        progress = Progress(fuse: .running, gguf: .pending, modelfile: .pending, ollama: .pending)

        let exporter = self.exporter
        streamTask = Task { [weak self] in
            do {
                for try await event in exporter.runStreaming(request: request) {
                    if Task.isCancelled { break }
                    self?.apply(event, outputName: request.outputName)
                }
                self?.finalizeOnStreamClose(outputName: request.outputName)
            } catch is CancellationError {
                self?.status = .failed(message: "Export cancelled.", recoverable: true)
            } catch {
                self?.status = .failed(message: error.localizedDescription, recoverable: true)
            }
        }
    }

    func cancel() {
        streamTask?.cancel()
        streamTask = nil
    }

    // MARK: - Event handling

    private func apply(_ event: ExportEvent, outputName: String) {
        switch event {
        case .ready:
            break
        case .stageDone(let stage, let artifact, let interrupted):
            switch stage {
            case .fuse:
                progress.fuse = .done(artifact: artifact)
                progress.gguf = .running
            case .gguf:
                progress.gguf = .done(artifact: artifact)
                // Modelfile render is synchronous on the sidecar; we treat it
                // as done the moment the gguf stage finishes so the UI shows
                // the three-of-four checkmark even though the sidecar does
                // not emit a dedicated modelfile event.
                progress.modelfile = .done(artifact: "Modelfile")
                progress.ollama = .running
            case .modelfile:
                progress.modelfile = .done(artifact: artifact)
            case .ollama:
                progress.ollama = .done(artifact: artifact)
                if !interrupted {
                    status = .completed(modelName: artifact.isEmpty ? outputName : artifact)
                }
            }
            if interrupted {
                status = .failed(
                    message: "Export interrupted at \(stage.rawValue) stage.",
                    recoverable: true
                )
            }
        case .stageFailed(let stage, _, let message, let recoverable):
            switch stage {
            case .fuse: progress.fuse = .failed(message: message)
            case .gguf: progress.gguf = .failed(message: message)
            case .modelfile: progress.modelfile = .failed(message: message)
            case .ollama: progress.ollama = .failed(message: message)
            }
            status = .failed(message: message, recoverable: recoverable)
        }
    }

    private func finalizeOnStreamClose(outputName: String) {
        if case .running = status {
            // Stream ended without a terminal done(stage="ollama"). The
            // subprocess already decided the outcome via exit code; if it exited
            // 0 with no ollama-done, the pipeline succeeded with --skip-ollama.
            status = .completed(modelName: outputName)
        }
    }
}

// MARK: - Preview factories

extension ExportModel {
    static func mockIdle() -> ExportModel {
        ExportModel(exporter: PreviewExporter(scenario: .idle))
    }

    static func mockMidway() -> ExportModel {
        let m = ExportModel(exporter: PreviewExporter(scenario: .idle))
        m.status = .running
        m.progress = Progress(
            fuse: .done(artifact: "fused"),
            gguf: .running,
            modelfile: .pending,
            ollama: .pending
        )
        return m
    }

    static func mockCompleted() -> ExportModel {
        let m = ExportModel(exporter: PreviewExporter(scenario: .idle))
        m.status = .completed(modelName: "kiln-preview")
        m.progress = Progress(
            fuse: .done(artifact: "fused"),
            gguf: .done(artifact: "kiln.gguf"),
            modelfile: .done(artifact: "Modelfile"),
            ollama: .done(artifact: "kiln-preview")
        )
        return m
    }

    final class PreviewExporter: OllamaExporter, @unchecked Sendable {
        enum Scenario { case idle }
        init(scenario _: Scenario) {}
        func runStreaming(request _: ExportRequest) -> AsyncThrowingStream<ExportEvent, Error> {
            AsyncThrowingStream { $0.finish() }
        }
    }
}
