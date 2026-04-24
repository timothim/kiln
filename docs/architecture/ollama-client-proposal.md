# Ollama client — shared abstraction proposal

Status: **proposal** — awaiting LEAD review.
Author: CODER (M8)
Date: 2026-04-24

## Why this exists

Two milestones in flight need HTTP access to Ollama on `localhost:11434`:

- **M7 (LEAD)** — streamed generation for the chat surface (`Features/Chat`)
  and VoiceMirror reflections. Requires `POST /api/generate` with `stream: true`.
- **M8 (CODER)** — voice library: list fused adapters served by Ollama and
  switch which one is "active". Requires `GET /api/tags` and (later) a
  pull/tag flow.

Building these independently means two HTTP clients, two error enums, two
URLSession configurations, and two mocks. Drift is near-certain once either
side starts handling edge cases (timeouts, cold-start waits, pulls in
progress). This doc proposes a single `OllamaClient` in `KilnCore` so both
features share a tested surface.

## Scope

**In scope**
- `actor OllamaClient` in `packages/KilnCore/Sources/KilnCore/Ollama/OllamaClient.swift`.
- Two methods to start: `listModels()` (for M8) and `generate()` (for M7).
- Typed errors and a mockable protocol seam (`any OllamaClientProtocol`) so
  view models can drive off fixtures without spinning up a real Ollama.

**Out of scope for v1**
- Model pull UX (download progress bars). Deferred; `pull` becomes an M9+
  concern once the library view has a "Pull missing model" row.
- Embeddings endpoint.
- Any multi-host story. Localhost only.

## Proposed surface

```swift
public actor OllamaClient: OllamaClientProtocol {
    public init(
        baseURL: URL = URL(string: "http://localhost:11434")!,
        session: URLSession = .shared
    ) { … }

    /// GET /api/tags — list of models Ollama currently serves locally.
    public func listModels() async throws -> [OllamaModel]

    /// POST /api/generate with stream=true. Emits tokens as they arrive; the
    /// stream completes with `.finish(GenerateSummary)` on `done: true` or
    /// throws on transport / decode failure.
    public func generate(
        model: String,
        prompt: String,
        options: GenerateOptions = .init()
    ) -> AsyncThrowingStream<GenerateEvent, Error>
}

public protocol OllamaClientProtocol: Sendable {
    func listModels() async throws -> [OllamaModel]
    func generate(
        model: String, prompt: String, options: GenerateOptions
    ) -> AsyncThrowingStream<GenerateEvent, Error>
}

public struct OllamaModel: Sendable, Equatable, Codable {
    public let name: String          // "kiln/tim-drafts:latest"
    public let modifiedAt: Date
    public let sizeBytes: Int64
    public let digest: String
}

public struct GenerateOptions: Sendable {
    public var temperature: Double = 0.8
    public var numPredict: Int = 512
    public var stop: [String] = []
    public var seed: UInt64? = nil
}

public enum GenerateEvent: Sendable {
    case token(String)
    case finish(GenerateSummary)
}

public struct GenerateSummary: Sendable, Equatable {
    public let totalTokens: Int
    public let durationNs: UInt64
    public let evalCount: Int
}

public enum OllamaError: Error, Equatable {
    case notRunning                  // connect refused — suggest `ollama serve`
    case modelNotFound(String)       // 404 on the tag — surface "Pull this?"
    case httpStatus(Int, body: String?)
    case decode(String)
    case cancelled
}
```

## Error-handling ground rules

- Surface `notRunning` distinctly from other transport failures. The app's
  copy for "Ollama isn't running" is meaningfully different from "Ollama
  returned 500 on a generate." Conflating them produces useless UI strings.
- Never force-unwrap. The `URL(string:)!` above is acceptable in test-free
  module code only if guarded by a `#warning` — otherwise we factor it into
  a safe init. KilnCore CLAUDE.md forbids force-unwrap; the shipped version
  uses a failable init or a `Constants.defaultOllamaURL` from a build-time
  assertion.
- `httpStatus(_, body:)` carries the body so operators can grep logs for
  Ollama's own error prose without us trying to parse it.

## M8 fallback until this lands

M8 ships with `DiskVoicesProvider` (reads
`~/Library/Application Support/Kiln/Voices/*.json` metadata). It fulfills the
`VoicesProvider` protocol the sidebar selector binds to. Once `OllamaClient`
is merged, we add a thin `OllamaVoicesProvider` adapter:

```swift
public struct OllamaVoicesProvider: VoicesProvider {
    public init(client: any OllamaClientProtocol) { … }
    public func list() async throws -> [KilnVoices.Voice] {
        let models = try await client.listModels()
        return models
            .filter { $0.name.hasPrefix("kiln/") }
            .map { KilnVoices.Voice(
                id: … /* derive from digest or tag */,
                name: $0.name,
                ollamaTag: $0.name,
                createdAt: $0.modifiedAt
            ) }
    }
    public func activate(_ id: UUID) async throws { /* disk marker only */ }
}
```

Swap from disk to Ollama by changing the `voicesProvider` argument to
`AppModel.init`. Sidebar UI unchanged.

## Who builds it

Recommend **LEAD** owns the first cut. Two reasons:

1. **M7 needs streaming.** The non-trivial part of this proposal is
   `generate(...)` returning `AsyncThrowingStream<GenerateEvent, Error>` —
   that's LEAD's critical path. M8 only needs `listModels()`, which is a
   20-line async HTTP call.
2. **M8 is unblocked.** `DiskVoicesProvider` satisfies M8's UI contract.
   Nothing in M8 gates on `OllamaClient` landing. M7 meaningfully cannot
   ship without streaming generation.

CODER (me) is happy to PR the `listModels()` + `OllamaVoicesProvider`
follow-up once LEAD's first cut is in.

## Open questions

1. **Timeout defaults.** `URLSession.shared` has a 60s timeout by default.
   For generate-stream that might be fine (each chunk resets the interval).
   For list we probably want shorter (5s) because the "Ollama isn't running"
   path needs to resolve fast.
2. **Cold-start latency.** First generate after a model loads can take
   20–40s while Ollama reads the model into memory. Do we want a separate
   `warmup()` method that fires-and-forgets a 1-token generate to pre-load?
   M7's UX hinges on this feeling fast — worth a conversation.
3. **Tag-vs-digest identity.** Models are addressed by tag (`kiln/x:latest`)
   but digests are the stable identity. We'll want both in `OllamaModel` so
   the UI layer can key on tag while a downstream "pin this version" flow
   can key on digest later.
4. **Pull UX.** Out of scope for v1, but the shape matters: likely another
   `AsyncThrowingStream<PullEvent, Error>`. Worth agreeing on the event
   enum now so the v1 surface doesn't need reshaping.

## Next step

LEAD: leave review comments on this doc (either inline via a PR or in
`DECISIONS.md`). If the surface above is broadly OK, we go ahead. If the
answer is "LEAD already has a prototype, use that one," CODER pivots M8 to
consume it instead of `DiskVoicesProvider` as soon as it merges.
