import SwiftUI

enum Kiln {

    enum Palette {
        /// Amber #D97706 — the single brand accent. Used only for firing moments:
        /// ingest drop glow, training progress, checkpoint pulse, export CTA.
        /// Never for body text, icons, or dividers.
        static let accent = Color(red: 217.0 / 255.0,
                                  green: 119.0 / 255.0,
                                  blue: 6.0 / 255.0)

        static let accentMuted = accent.opacity(0.18)
        static let accentWash  = accent.opacity(0.08)
    }

    enum Font {
        static let display = SwiftUI.Font.system(.title,    design: .default).weight(.semibold)
        static let title   = SwiftUI.Font.system(.title2,   design: .default).weight(.semibold)
        static let body    = SwiftUI.Font.system(.body,     design: .default)
        static let caption = SwiftUI.Font.system(.footnote, design: .default)
        static let mono    = SwiftUI.Font.system(.footnote, design: .monospaced)
    }

    enum Space {
        static let xxs: CGFloat = 4
        static let xs:  CGFloat = 8
        static let s:   CGFloat = 16
        static let m:   CGFloat = 24
        static let l:   CGFloat = 32
    }

    enum Radius {
        static let control: CGFloat = 8
        static let card:    CGFloat = 12
        static let modal:   CGFloat = 20
    }

    enum Icon {
        /// Inline utility glyph next to body text (e.g. sidebar action rows).
        static let small:       CGFloat = 14
        /// Heading-adjacent glyph paired with a display or title string.
        static let heading:     CGFloat = 22
        /// Quiet hero glyph for empty-state placeholders.
        static let placeholder: CGFloat = 30
        /// Prominent hero glyph for the launch drop zone.
        static let hero:        CGFloat = 34
    }

    enum Motion {
        static let standard: Animation = .smooth(duration: 0.35)
        static let glow: Animation = .easeInOut(duration: 1.8).repeatForever(autoreverses: true)
        static let stageTransition: AnyTransition = .asymmetric(
            insertion: .opacity.combined(with: .move(edge: .trailing)),
            removal:   .opacity.combined(with: .move(edge: .leading))
        )
    }

    enum Layout {
        static let minWindowWidth:  CGFloat = 900
        static let minWindowHeight: CGFloat = 560
        static let dropCardMaxWidth: CGFloat = 560
        static let sidebarMinWidth: CGFloat = 220
        static let sidebarIdeal:    CGFloat = 260
        static let sidebarMaxWidth: CGFloat = 320
        static let detailMinWidth:  CGFloat = 300
        static let detailIdeal:     CGFloat = 340
    }
}
