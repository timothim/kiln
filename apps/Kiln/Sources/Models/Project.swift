import Foundation

struct Project: Identifiable, Hashable {
    enum Size: String, CaseIterable, Hashable {
        case small  = "1.5B"
        case medium = "3B"
        case large  = "7B"

        var displayName: String { rawValue }

        var approximateWeightGiB: Double {
            switch self {
            case .small:  1.0
            case .medium: 1.9
            case .large:  4.4
            }
        }
    }

    let id: UUID
    var name: String
    var folderName: String?
    var modelSize: Size
    var stage: ProjectStage
    var lastTrained: Date?
    var keptChunks: Int?
    var totalChunks: Int?

    init(id: UUID = UUID(),
         name: String,
         folderName: String? = nil,
         modelSize: Size = .medium,
         stage: ProjectStage = .readyToDrop,
         lastTrained: Date? = nil,
         keptChunks: Int? = nil,
         totalChunks: Int? = nil) {
        self.id = id
        self.name = name
        self.folderName = folderName
        self.modelSize = modelSize
        self.stage = stage
        self.lastTrained = lastTrained
        self.keptChunks = keptChunks
        self.totalChunks = totalChunks
    }

    /// Safe slug for terminal hand-off copy. Lowercase, alphanumerics and hyphens only.
    var slug: String {
        let allowed = CharacterSet.alphanumerics
        let lowered = name.lowercased()
        let mapped = lowered.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(mapped)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return collapsed.isEmpty ? "model" : collapsed
    }
}
