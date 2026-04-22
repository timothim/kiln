import Foundation

enum ProjectStage: String, Hashable, CaseIterable {
    case readyToDrop
    case preparing
    case training
    case complete

    var label: String {
        switch self {
        case .readyToDrop: "Ready"
        case .preparing:   "Reading"
        case .training:    "Training"
        case .complete:    "Ready to chat"
        }
    }

    var spoken: String {
        switch self {
        case .readyToDrop: "ready for a folder"
        case .preparing:   "reading files"
        case .training:    "teaching the model"
        case .complete:    "ready to chat"
        }
    }

    var order: Int {
        switch self {
        case .readyToDrop: 0
        case .preparing:   1
        case .training:    2
        case .complete:    3
        }
    }
}
