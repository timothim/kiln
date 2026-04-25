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

        /// Reverse of `stageTransition` — the new view slides in from the
        /// leading edge while the old slides out to the trailing edge.
        /// Wired up by `StageRouterView` when the user navigates *back*
        /// (e.g. resets prepare to readyToDrop) so the direction of
        /// motion mirrors the conceptual direction of travel.
        static let stageTransitionBackward: AnyTransition = .asymmetric(
            insertion: .opacity.combined(with: .move(edge: .leading)),
            removal:   .opacity.combined(with: .move(edge: .trailing))
        )

        // --- Semantic variants of `standard`, registered by the
        // Saturday UI audit so call sites stop reaching for inline
        // duration literals. Names describe the moment, not the duration.

        /// Pin toggles, chip flips, in-place state swaps. Slightly faster
        /// than `standard` so the surface feels responsive rather than
        /// "loaded." Used in Voice Mirror's pin/highlight transitions.
        static let microToggle: Animation = .smooth(duration: 0.2)

        /// New-sample reveal in the Growing Model panel. Slower than
        /// `standard` so the eye lands on the new card before the rest of
        /// the layout reflows.
        static let sampleReveal: Animation = .smooth(duration: 0.6)

        /// Skeleton-card pulse during loading. Matches the cadence of an
        /// inhale-exhale; slow enough to read as "thinking" rather than
        /// "spinning."
        static let skeletonPulse: Animation = .easeInOut(duration: 0.9)
            .repeatForever(autoreverses: true)

        // --- Sunday animation pass. Each token is paired with a single
        // motion *moment* so call sites pick by intent, not by duration.

        /// Per-element step in a stagger sequence — Voice Mirror column
        /// reveal, multi-card fade-ins. Tight (180ms) so the whole
        /// sequence stays under 1 s for 4 elements.
        static let staggerStep: Animation = .smooth(duration: 0.18)

        /// Brief glow sweep when a newly arrived item should be noticed
        /// (loss-curve latest dot, just-shown sample). easeOut so it
        /// blooms then settles.
        static let highlightSweep: Animation = .easeOut(duration: 0.5)

        /// Sub-agent hierarchy connector lines growing from parent to
        /// child. Slightly slower than `microToggle` so the line draws
        /// rather than snaps.
        static let connectorGrow: Animation = .smooth(duration: 0.3)

        /// Slow continuous pulse for the agent-network diagram on the
        /// Behind the Scenes page. Easeful, repeating, autoreversing —
        /// reads as "alive" without ever attracting active attention.
        static let networkPulse: Animation = .easeInOut(duration: 2.2)
            .repeatForever(autoreverses: true)

        /// Live-indicator dot pulse (MCP server "running," voice "loaded").
        /// Subtle alpha breath so the dot says "I am awake" without
        /// becoming decoration.
        static let statusPulse: Animation = .easeInOut(duration: 1.4)
            .repeatForever(autoreverses: true)
    }

    /// Opacity values for ad-hoc fills the system has organically standardized
    /// on. `cardFill` is the quiet 4% wash used under sample cards, voice
    /// chips, info pills, and panel surfaces — not loud enough to compete
    /// with content. `codeFill` is the slightly louder 6% wash used under
    /// mono text (terminal hand-off line, import command block, code badges)
    /// where the box itself needs to read as a "block." Both pair with
    /// `Color.primary` so they adapt to dark mode automatically.
    ///
    /// DESIGN.md doesn't sanction these as named tokens yet — flagged in
    /// `docs/audits/saturday-ui-audit.md` as a candidate. Until the patch
    /// lands, the source of truth is here.
    enum Opacity {
        static let cardFill: Double = 0.04
        static let codeFill: Double = 0.06
        /// 8% primary — the louder neutral used on capsule tracks, skeleton
        /// loaders, and the user-side chat bubble background. Distinguishes
        /// "filled track" from the quieter `cardFill`.
        static let trackFill: Double = 0.08
    }

    enum Layout {
        static let minWindowWidth:  CGFloat = 900
        static let minWindowHeight: CGFloat = 560
        static let dropCardMaxWidth: CGFloat = 560
        static let sidebarMinWidth: CGFloat = 220
        static let sidebarIdeal:    CGFloat = 260
        static let sidebarMaxWidth: CGFloat = 320
        /// Minimum width for the center stage pane in the NavigationSplitView.
        /// Narrower than this and stage headers start truncating.
        static let centerMinWidth:  CGFloat = 360
        static let detailMinWidth:  CGFloat = 300
        static let detailIdeal:     CGFloat = 340
    }
}
