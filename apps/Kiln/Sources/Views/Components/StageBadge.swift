import SwiftUI

/// Small stage pill. Amber only during `.training` (firing moment); neutral
/// otherwise. Always pairs color with a label — color is never the only signal.
struct StageBadge: View {
    let stage: ProjectStage

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)
            Text(stage.label)
                .font(Kiln.Font.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Kiln.Space.xs)
        .padding(.vertical, 3)
        .background {
            Capsule(style: .continuous)
                .fill(pillColor)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Stage: \(stage.spoken)")
    }

    private var dotColor: Color {
        switch stage {
        case .training:    Kiln.Palette.accent
        case .complete:    .secondary
        case .preparing:   .secondary
        case .readyToDrop: Color.secondary.opacity(0.55)
        }
    }

    private var pillColor: Color {
        switch stage {
        case .training:    Kiln.Palette.accentWash
        default:           Color.primary.opacity(0.05)
        }
    }
}
