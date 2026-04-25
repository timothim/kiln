import Foundation
import OSLog

/// Saturday Phase 2 — manages the lifecycle of the
/// ``kiln_trainer mcp-serve`` subprocess. The Swift app spawns it
/// when the user flips on "Expose voice as MCP server" in Settings,
/// monitors it, and shuts it down cleanly on toggle-off / app quit.
///
/// **The interesting product story** lives at the boundary: Claude.app
/// (or Claude Code) connects to this process via the standard MCP
/// stdio config and gets a ``write_in_user_voice`` tool that proxies
/// to local Ollama. Kiln itself never sees the prompt — it's
/// transported parent-to-child between Claude.app and our subprocess.
///
/// Lifecycle:
///   1. ``start(voiceName:)`` — spawns the subprocess, captures stderr
///      for the OS log channel, returns a ``Status.running`` snapshot
///      with the config snippet the user pastes into Claude.app.
///   2. ``stop()`` — SIGTERMs the child, waits up to 5s, escalates
///      to SIGKILL.
///
/// The class is ``@unchecked Sendable`` because ``Process`` isn't
/// Sendable; we serialize all state changes through a ``DispatchQueue``.

public final class MCPServerManager: @unchecked Sendable {
    public enum Status: Sendable, Hashable {
        case stopped
        case starting
        case running(voiceName: String, configSnippet: String)
        case failed(message: String)
    }

    public private(set) var status: Status = .stopped

    /// Test-only accessor for the underlying subprocess pid. Used by
    /// ``test_deinit_safety_net_terminates_running_subprocess`` to verify
    /// the deinit path actually reaps the child. Not exposed publicly
    /// because callers shouldn't reach past the ``Status`` enum.
    var processIdentifierForTesting: pid_t {
        queue.sync { process?.processIdentifier ?? 0 }
    }

    private let launcher: TrainerLauncher
    private let log = Logger(subsystem: "dev.kiln.core", category: "mcp-server")
    private let queue = DispatchQueue(label: "dev.kiln.mcp-server")
    private var process: Process? = nil

    public init(launcher: TrainerLauncher) {
        self.launcher = launcher
    }

    deinit {
        // Safety net: if a caller drops the manager while the child is
        // still running (e.g. settings view dismissed mid-launch), make
        // sure we don't leak a zombie ``mcp-serve`` process. ``stop()``
        // already implements SIGTERM → grace → SIGKILL; we route through
        // the same code path. Deinit can't await/dispatch, so we call
        // ``terminate`` synchronously and let the kernel clean up.
        if let process, process.isRunning {
            process.terminate()
            // Best-effort: give the child a brief moment, then SIGKILL.
            // We can't block deinit on a long sleep, so use a short
            // 0.5 s window — enough for a well-behaved child to exit
            // cleanly. Servers that ignore SIGTERM get SIGKILL'd.
            let deadline = Date().addingTimeInterval(0.5)
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
    }

    /// Spawn the server and return the ready-to-paste Claude.app
    /// MCP config snippet. Idempotent: calling start while running
    /// is a no-op.
    @discardableResult
    public func start(voiceName: String) throws -> Status {
        try queue.sync {
            if case .running = status {
                return status
            }
            status = .starting

            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            process.executableURL = launcher.executableURL
            process.arguments = launcher.argumentPrefix + [
                "mcp-serve", "--voice-name", voiceName,
            ]
            if let cwd = launcher.workingDirectory {
                process.currentDirectoryURL = cwd
            }
            if let env = launcher.environment {
                process.environment = env
            }
            process.standardInput = Pipe() // hold stdin open so the child doesn't EOF early
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            // Capture stderr lines into OSLog for visibility.
            let logSink = self.log
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty,
                      let chunk = String(data: data, encoding: .utf8)
                else { return }
                for line in chunk.split(separator: "\n", omittingEmptySubsequences: true) {
                    logSink.debug("[mcp-server] \(String(line), privacy: .public)")
                }
            }

            do {
                try process.run()
            } catch {
                status = .failed(message: error.localizedDescription)
                throw MCPServerError.launchFailed(message: error.localizedDescription)
            }
            self.process = process

            let snippet = Self.configSnippet(
                voiceName: voiceName,
                executableURL: launcher.executableURL,
                argumentPrefix: launcher.argumentPrefix,
                workingDirectory: launcher.workingDirectory
            )
            status = .running(voiceName: voiceName, configSnippet: snippet)
            log.debug("mcp-server spawned (pid=\(process.processIdentifier, privacy: .public))")
            return status
        }
    }

    /// Send SIGTERM, give the child up to ``graceSeconds`` (default 5s),
    /// then SIGKILL if still alive. Always lands the manager in
    /// ``Status.stopped``.
    public func stop(graceSeconds: TimeInterval = 5) {
        queue.sync {
            guard let process, process.isRunning else {
                status = .stopped
                self.process = nil
                return
            }
            process.terminate()
            let deadline = Date().addingTimeInterval(graceSeconds)
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.1)
            }
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
            self.process = nil
            status = .stopped
        }
    }

    /// Build the JSON snippet the user pastes into
    /// ``~/Library/Application Support/Claude/claude_desktop_config.json``
    /// to register Kiln's MCP server.
    static func configSnippet(
        voiceName: String,
        executableURL: URL,
        argumentPrefix: [String],
        workingDirectory: URL?
    ) -> String {
        let argv = argumentPrefix + ["mcp-serve", "--voice-name", voiceName]
        var entry: [String: Any] = [
            "command": executableURL.path,
            "args": argv,
        ]
        if let cwd = workingDirectory?.path {
            entry["cwd"] = cwd
        }
        let config: [String: Any] = [
            "mcpServers": [
                "kiln-voice": entry,
            ],
        ]
        // Audit M3: previously this swallowed JSONSerialization
        // failures with an empty Data() and returned ``"{}"``, leaving
        // the user with a useless "copy this snippet" surface and no
        // hint that anything went wrong. Foundation's
        // ``JSONSerialization.data`` only fails for non-JSON-encodable
        // values; the inputs here are all plain strings + arrays of
        // strings so a failure indicates a real bug. Surface it via
        // OSLog and an explicit ``configError(...)`` payload the UI
        // can detect (it starts with the magic ``__kiln_config_error:``
        // prefix that ``MCPServerSettingsView`` reads and renders as
        // a banner instead of pasting the broken snippet).
        do {
            let data = try JSONSerialization.data(
                withJSONObject: config,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            )
            return String(data: data, encoding: .utf8) ?? "__kiln_config_error: snippet bytes were not valid UTF-8"
        } catch {
            let log = Logger(subsystem: "dev.kiln.core", category: "mcp-server")
            log.error("config snippet serialization failed: \(error.localizedDescription, privacy: .public)")
            return "__kiln_config_error: \(error.localizedDescription)"
        }
    }
}

public enum MCPServerError: Error, Equatable, Sendable {
    case launchFailed(message: String)
    case alreadyRunning
}
