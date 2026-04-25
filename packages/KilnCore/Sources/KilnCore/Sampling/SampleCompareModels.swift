import Foundation

/// The three fixed Voice Mirror variants. Wire tags match the Python sidecar's
/// ``sample-compare`` ``--variant`` tags and ``events.generation(prompt_id=...)``.
public enum SampleCompareVariant: String, Sendable, Hashable, Codable, CaseIterable {
    case base      // no adapter — just the base model
    case sft       // base + SFT adapter
    case sftdpo    // base + SFT + DPO adapter
}

/// One row the sidecar emits for a single variant's completion.
public struct SampleCompareGeneration: Sendable, Hashable {
    public let variant: SampleCompareVariant
    public let prompt: String
    public let completion: String
    public let tokens: Int
    public let tokensPerSec: Double

    public init(
        variant: SampleCompareVariant,
        prompt: String,
        completion: String,
        tokens: Int,
        tokensPerSec: Double
    ) {
        self.variant = variant
        self.prompt = prompt
        self.completion = completion
        self.tokens = tokens
        self.tokensPerSec = tokensPerSec
    }
}

/// Event stream pushed up from ``SampleCompareRunner``.
///
/// The Swift side doesn't reuse ``TrainingEvent`` because that type models
/// training-loop progress (loss, checkpoints). Sample-compare has a simpler
/// lifecycle: ready → N×generation → done, plus per-variant errors.
public enum SampleCompareEvent: Sendable, Hashable {
    case ready(version: String, mlx: String)
    case generation(SampleCompareGeneration)
    /// Emitted when a variant couldn't produce a completion — most often
    /// because its adapter path was missing. Other variants still run; the
    /// consumer should show a failure state on the affected card only.
    case variantFailed(variant: SampleCompareVariant?, message: String, code: String)
    case done(interrupted: Bool, variantsDelivered: [SampleCompareVariant])
}

public struct SampleCompareRequest: Sendable, Hashable {
    public let model: String
    public let prompt: String
    public let variants: [VariantSpec]
    public let maxTokens: Int
    public let temperature: Double
    public let topP: Double
    public let seed: UInt64
    /// Hidden test seam — forwarded as ``--generator-entry`` to the sidecar.
    /// Integration tests point this at ``fake_generator.py``; production omits it.
    public let generatorEntry: String?

    public init(
        model: String = "mlx-community/Qwen2.5-3B-Instruct-4bit",
        prompt: String,
        variants: [VariantSpec],
        maxTokens: Int = 200,
        temperature: Double = 0.7,
        topP: Double = 0.9,
        seed: UInt64 = 42,
        generatorEntry: String? = nil
    ) {
        self.model = model
        self.prompt = prompt
        self.variants = variants
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.seed = seed
        self.generatorEntry = generatorEntry
    }

    public struct VariantSpec: Sendable, Hashable {
        public let variant: SampleCompareVariant
        public let adapterPath: URL?

        public init(variant: SampleCompareVariant, adapterPath: URL?) {
            self.variant = variant
            self.adapterPath = adapterPath
        }

        /// Returns the flag token the sidecar expects:
        /// ``base``, ``sft:/path/to/sft.safetensors``, ``sftdpo:/path/...``.
        public func cliToken() -> String {
            switch variant {
            case .base:
                return "base"
            case .sft, .sftdpo:
                let path = adapterPath?.path ?? ""
                return "\(variant.rawValue):\(path)"
            }
        }
    }
}
