import Foundation

/// Swift-side mirror of `ERROR_CODES` in the Python sidecar plus the
/// Swift-only launch/cancel paths. Values carry enough detail to drive
/// user-facing copy without re-fetching the raw event.
public enum TrainingError: Error, LocalizedError, Equatable, Hashable, Sendable {
    // Sidecar-emitted codes.
    case oom(message: String)
    case dataInvalid(message: String)
    case modelNotFound(message: String)
    case adapterInvalid(message: String)
    case ggufFailed(message: String)
    case ollamaUnavailable(message: String)
    case subprocessFailed(message: String)
    case sigterm(message: String)
    case internalError(message: String)

    // Runner-only cases. Cancellation is modelled as an error on the event
    // stream; consumers decide whether to surface it as .failed or map it to
    // a partial-completion .completed.
    case cancelled
    case launchFailed(message: String)
    case decodingFailed(line: String, underlying: String)
    case unexpectedExit(code: Int32, stderrTail: String)

    public var errorDescription: String? {
        switch self {
        case .oom(let message):
            return "Out of memory during training. \(message)"
        case .dataInvalid(let message):
            return "Dataset rejected by the trainer: \(message)"
        case .modelNotFound(let message):
            return "Base model not found: \(message)"
        case .adapterInvalid(let message):
            return "Adapter invalid: \(message)"
        case .ggufFailed(let message):
            return "GGUF conversion failed: \(message)"
        case .ollamaUnavailable(let message):
            return "Ollama unavailable: \(message)"
        case .subprocessFailed(let message):
            return "Trainer subprocess failed: \(message)"
        case .sigterm(let message):
            return "Training was terminated: \(message)"
        case .internalError(let message):
            return "Internal trainer error: \(message)"
        case .cancelled:
            return "Training was cancelled."
        case .launchFailed(let message):
            return "Could not launch trainer: \(message)"
        case .decodingFailed(let line, let underlying):
            return "Malformed sidecar event: \(underlying) — line: \(line.prefix(200))"
        case .unexpectedExit(let code, let tail):
            return "Trainer exited with code \(code). \(tail)"
        }
    }

    /// Map a Python `error` event's `code` string onto the typed Swift case.
    /// Unknown codes fall through to `.internalError` so the UI still renders
    /// something useful rather than dropping the event.
    public static func fromCode(_ code: String, message: String, recoverable: Bool = false) -> TrainingError {
        switch code {
        case "oom": return .oom(message: message)
        case "data_invalid": return .dataInvalid(message: message)
        case "model_not_found": return .modelNotFound(message: message)
        case "adapter_invalid": return .adapterInvalid(message: message)
        case "gguf_failed": return .ggufFailed(message: message)
        case "ollama_unavailable": return .ollamaUnavailable(message: message)
        case "subprocess_failed": return .subprocessFailed(message: message)
        case "sigterm": return .sigterm(message: message)
        case "internal": return .internalError(message: message)
        default: return .internalError(message: "unknown code \(code): \(message)")
        }
    }
}
