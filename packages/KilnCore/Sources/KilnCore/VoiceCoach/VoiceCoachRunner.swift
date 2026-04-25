import Foundation
import OSLog

/// Saturday Phase 1 — Voice Coach runner. Wraps ``python -m
/// kiln_trainer voice-coach`` so the Swift app can ask Opus 4.7 (or
/// local Qwen via Ollama) for a 150-word voice analysis after
/// successful Ollama export.

public struct VoiceCoachInput: Sendable, Hashable, Codable {
    public let styleSignature: [String: AnyCodable]
    public let sampleCompletions: [SampleCompletion]

    public init(styleSignature: [String: AnyCodable], sampleCompletions: [SampleCompletion]) {
        self.styleSignature = styleSignature
        self.sampleCompletions = sampleCompletions
    }

    public struct SampleCompletion: Sendable, Hashable, Codable {
        public let prompt: String
        public let completion: String

        public init(prompt: String, completion: String) {
            self.prompt = prompt
            self.completion = completion
        }
    }

    enum CodingKeys: String, CodingKey {
        case styleSignature = "style_signature"
        case sampleCompletions = "sample_completions"
    }
}

/// Type-erased JSON value so we can round-trip the deterministic
/// style signature (mix of strings, numbers, arrays) without dragging
/// every consumer through a typed schema. The runner only needs to
/// pass the dict through; Opus does the interpretation.
public enum AnyCodable: Sendable, Hashable, Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case stringArray([String])
    case numberArray([Double])

    public init(_ value: String) { self = .string(value) }
    public init(_ value: Double) { self = .number(value) }
    public init(_ value: Bool) { self = .bool(value) }
    public init(_ value: [String]) { self = .stringArray(value) }
    public init(_ value: [Double]) { self = .numberArray(value) }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let arr = try? c.decode([String].self) {
            self = .stringArray(arr)
        } else if let arr = try? c.decode([Double].self) {
            self = .numberArray(arr)
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? c.decode(Double.self) {
            self = .number(n)
        } else {
            self = .string("")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .stringArray(let a): try c.encode(a)
        case .numberArray(let a): try c.encode(a)
        }
    }
}

public struct VoiceReport: Sendable, Hashable {
    public let markdown: String
    /// Model id the report was produced by (e.g. ``"claude-opus-4-7"``
    /// for cloud mode, ``"qwen2.5:7b"`` for local mode). Drives the
    /// "Powered by Claude Opus 4.7" / "Running locally with Qwen2.5"
    /// badge in the UI.
    public let modelID: String

    public init(markdown: String, modelID: String) {
        self.markdown = markdown
        self.modelID = modelID
    }
}

public enum VoiceCoachMode: String, Sendable, Hashable, Codable {
    case cloud
    case local
}

public enum VoiceCoachError: Error, Equatable, Sendable {
    /// Cloud mode without a configured API key. UI surfaces a "Set up
    /// API key in Settings → Cloud features" CTA.
    case missingAPIKey
    /// Subprocess exited non-zero with a typed error code from the
    /// sidecar. ``code`` is the wire-protocol ``error.code`` value.
    case sidecarError(code: String, message: String)
    case unexpectedExit(code: Int32, stderrTail: String)
    case launchFailed(message: String)
    case emptyReport
}

public protocol VoiceCoachRunner: Sendable {
    func generate(
        input: VoiceCoachInput,
        mode: VoiceCoachMode,
        apiKey: String?
    ) async throws -> VoiceReport
}

public final class SubprocessVoiceCoachRunner: VoiceCoachRunner, @unchecked Sendable {
    private let launcher: TrainerLauncher
    private let log = Logger(subsystem: "dev.kiln.core", category: "voice-coach")

    public init(launcher: TrainerLauncher) {
        self.launcher = launcher
    }

    public func generate(
        input: VoiceCoachInput,
        mode: VoiceCoachMode,
        apiKey: String?
    ) async throws -> VoiceReport {
        // Cloud mode without a key is deterministic-fail; surface
        // immediately rather than spawning the subprocess.
        if mode == .cloud && (apiKey?.isEmpty ?? true) {
            throw VoiceCoachError.missingAPIKey
        }

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("kiln-voice-coach-\(UUID().uuidString).json")
        let payload = try JSONEncoder().encode(input)
        try payload.write(to: tmp, options: .atomic)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let args: [String] = [
            "voice-coach",
            "--mode", mode.rawValue,
            "--input-file", tmp.path,
        ]

        // Pre-launch cancellation check + SIGTERM (with 5 s grace →
        // SIGKILL) hook on outer-task cancellation. ``Task.detached``
        // does not propagate the parent's cancellation, so the
        // ``withTaskCancellationHandler`` ``onCancel`` runs on the
        // cancelling task and SIGTERMs the child synchronously, then
        // escalates to SIGKILL if the child is still alive after the
        // grace window. Same pattern as DistilledClassifierRunner with
        // OllamaExporter's escalation.
        try Task.checkCancellation()

        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = launcher.executableURL
        process.arguments = launcher.argumentPrefix + args
        if let cwd = launcher.workingDirectory {
            process.currentDirectoryURL = cwd
        }
        var env = launcher.environment ?? ProcessInfo.processInfo.environment
        if let apiKey, !apiKey.isEmpty {
            env["ANTHROPIC_API_KEY"] = apiKey
        }
        process.environment = env
        process.standardOutput = stdout
        process.standardError = stderr

        struct ProcessBox: @unchecked Sendable { let p: Process }
        let box = ProcessBox(p: process)

        let log = self.log
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) {
                do {
                    try process.run()
                } catch {
                    throw VoiceCoachError.launchFailed(message: error.localizedDescription)
                }

                // Drain stdout and stderr concurrently to EOF — sequential
                // reads would deadlock if the child filled the 64 KB stderr
                // pipe buffer before stdout closed (e.g. an anthropic-SDK
                // traceback on a malformed API response).
                async let stdoutTask = Task.detached { stdout.fileHandleForReading.readDataToEndOfFile() }.value
                async let stderrTask = Task.detached { stderr.fileHandleForReading.readDataToEndOfFile() }.value
                let stdoutData = await stdoutTask
                let stderrData = await stderrTask

                process.waitUntilExit()

                let stdoutText = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderrText = String(data: stderrData, encoding: .utf8) ?? ""

                var report: VoiceReport? = nil
                var sidecarError: VoiceCoachError? = nil
                for raw in stdoutText.split(separator: "\n", omittingEmptySubsequences: true) {
                    let line = String(raw)
                    guard let data = line.data(using: .utf8),
                          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let event = obj["event"] as? String
                    else {
                        log.debug("voice-coach: skipping unparseable line: \(line, privacy: .public)")
                        continue
                    }
                    switch event {
                    case "voice_report":
                        if let md = obj["markdown"] as? String,
                           let model = obj["model"] as? String {
                            report = VoiceReport(markdown: md, modelID: model)
                        }
                    case "error":
                        if (obj["recoverable"] as? Bool) == false {
                            let code = obj["code"] as? String ?? "internal"
                            let message = obj["message"] as? String ?? ""
                            if code == "data_invalid" && message.contains("ANTHROPIC_API_KEY") {
                                sidecarError = .missingAPIKey
                            } else {
                                sidecarError = .sidecarError(code: code, message: message)
                            }
                        }
                    default:
                        continue
                    }
                }

                if let sidecarError {
                    throw sidecarError
                }
                if process.terminationStatus != 0 {
                    throw VoiceCoachError.unexpectedExit(
                        code: process.terminationStatus,
                        stderrTail: String(stderrText.suffix(4096))
                    )
                }
                guard let report else {
                    throw VoiceCoachError.emptyReport
                }
                return report
            }.value
        } onCancel: {
            if box.p.isRunning {
                box.p.terminate()
                let deadline = DispatchTime.now() + .seconds(5)
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: deadline) {
                    if box.p.isRunning {
                        kill(box.p.processIdentifier, SIGKILL)
                    }
                }
            }
        }
    }
}
