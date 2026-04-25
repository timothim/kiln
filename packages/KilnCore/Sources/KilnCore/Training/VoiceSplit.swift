import Foundation

/// A slice of the user's corpus — "drafts", "formal", "notes" — that the user
/// can include or exclude from an upcoming training run. Personas are inferred
/// upstream (corpus classifier) or defined by the user; this type only carries
/// the selection state through the UI → TrainingRequest wire.
///
/// M8 threads `VoiceSplit` through `TrainingRequest` for UI metadata only —
/// the Python sidecar ignores the field. M9+ will teach the trainer to honor
/// persona slicing (separate adapters or weighted sampling).
public struct Persona: Sendable, Equatable, Identifiable, Codable, Hashable {
    public let id: UUID
    public var label: String
    public var sampleCount: Int
    public var selected: Bool

    public init(
        id: UUID = UUID(),
        label: String,
        sampleCount: Int,
        selected: Bool = true
    ) {
        self.id = id
        self.label = label
        self.sampleCount = sampleCount
        self.selected = selected
    }
}

/// Pre-training cohort configuration. An empty `personas` array means
/// "train on the whole corpus as a single voice" — the fall-through case
/// when the corpus has no persona tags.
public struct VoiceSplit: Sendable, Equatable, Codable, Hashable {
    public let personas: [Persona]

    public init(personas: [Persona]) {
        self.personas = personas
    }

    public var selectedPersonas: [Persona] {
        personas.filter(\.selected)
    }

    public var selectedSampleCount: Int {
        selectedPersonas.reduce(0) { $0 + $1.sampleCount }
    }
}
