import SwiftUI

/// Swift projection of `/DESIGN.md`. Every token here maps 1:1 to an entry in DESIGN.md's
/// YAML frontmatter. Token changes start in DESIGN.md, then `make design-lint` must pass,
/// then this file is updated to match. Never edit this file first — it drifts fast.
///
/// DESIGN.md color tokens that resolve via SwiftUI's semantic layer (`surface`,
/// `surface-elevated`, `on-surface`, `on-surface-secondary`, `on-surface-tertiary`) have
/// no Swift constants here — views reference `.regularMaterial`, `.primary`, `.secondary`,
/// `.tertiary` directly per DESIGN.md §Colors.
enum Kiln {

    enum Palette {
        /// Amber #D97706 — the single brand accent. Used only for firing moments:
        /// training progress bar, ember glow, ingest drop-zone targeted state,
        /// the *Teach your model* CTA. Never on checkmarks, success ticks, identity
        /// dots, error states, body text, icons, or dividers.
        static let firing = Color(red: 217.0 / 255.0,
                                  green: 119.0 / 255.0,
                                  blue: 6.0 / 255.0)

        /// 8% amber wash. Allowed only on: drop-zone targeted state, training-stage
        /// card background, *Teach* CTA backing pill. Forbidden on sample cards,
        /// error panels, or any neutral elevated surface.
        static let firingWash = firing.opacity(0.08)

        /// #D32F2F — used for error icons and destructive-button labels only.
        /// Never used as a background fill; destructive intent is communicated via
        /// label color + confirmation copy, not loud surfaces.
        static let danger = Color(red: 211.0 / 255.0,
                                  green: 47.0 / 255.0,
                                  blue: 47.0 / 255.0)

        /// Maps to DESIGN.md `surface-sunken` (#F2F2F7 approximation). Used for
        /// sunken fills: sample cards, log panel backgrounds, neutral error panels.
        /// `NSColor.controlBackgroundColor` adapts to dark mode natively.
        static let surfaceSunken = Color(nsColor: .controlBackgroundColor)
    }

    enum Font {
        // Primary tokens — 1:1 with DESIGN.md typography.
        static let display = SwiftUI.Font.system(.title,    design: .default).weight(.semibold)
        static let title   = SwiftUI.Font.system(.title2,   design: .default).weight(.semibold)
        static let bodyMD  = SwiftUI.Font.system(.body,     design: .default)
        static let bodySM  = SwiftUI.Font.system(.footnote, design: .default)
        /// 11pt semibold. DESIGN.md specifies `+0.04em` letter-spacing — apply
        /// `.kerning(0.44)` at the call site (SwiftUI has no em-relative kerning).
        static let label   = SwiftUI.Font.system(size: 11, weight: .semibold)
        static let mono    = SwiftUI.Font.system(.footnote, design: .monospaced)
        /// Tabular figures (tnum) for stable-width incrementing counters.
        /// Pair with `.contentTransition(.numericText())` for per-character crossfade.
        static let numeric = SwiftUI.Font.system(.body, design: .default)
            .weight(.medium)
            .monospacedDigit()

        // Call-site aliases — semantic names that map to DESIGN.md body-md / body-sm.
        static let body    = bodyMD
        static let caption = bodySM
    }

    enum Space {
        // 4-point grid, tokens match DESIGN.md frontmatter.
        static let xxs: CGFloat = 4
        static let xs:  CGFloat = 8
        static let sm:  CGFloat = 12
        static let m:   CGFloat = 16
        static let l:   CGFloat = 24
        static let xl:  CGFloat = 32
    }

    enum Radius {
        // Primary tokens — 1:1 with DESIGN.md rounded.
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 20

        // Call-site aliases — semantic names for readability at use sites.
        static let control = sm    // inline buttons, stage badges
        static let card    = md    // cards, panels, sample cards, drop zone
        static let modal   = lg    // full-bleed modals, training HUD
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
