import SwiftUI

// MARK: - Color hex helpers

/// Hex-string → Color. macOS 14+ dynamic-color two-arg constructor for
/// light/dark pairs. The design package is light-first ("warm cream
/// paper") and we ship a paper-inverted dark variant so the app reads
/// equally well at night without re-skinning the whole token system.
private extension Color {
    /// Parse a six-digit `#RRGGBB` or eight-digit `#RRGGBBAA` hex literal.
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        let value = UInt64(s, radix: 16) ?? 0
        let r, g, b, a: Double
        if s.count == 8 {
            r = Double((value >> 24) & 0xFF) / 255
            g = Double((value >> 16) & 0xFF) / 255
            b = Double((value >> 8)  & 0xFF) / 255
            a = Double(value & 0xFF) / 255
        } else {
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8)  & 0xFF) / 255
            b = Double(value & 0xFF) / 255
            a = 1.0
        }
        self = Color(red: r, green: g, blue: b, opacity: a)
    }

    /// Light/dark pair driven by the active `NSAppearance`. Works in
    /// previews, in dark mode, and during runtime appearance switches.
    static func kiln(light: String, dark: String) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let resolved = appearance.bestMatch(from: [.darkAqua, .vibrantDark, .aqua]) ?? .aqua
            let isDark = resolved == .darkAqua || resolved == .vibrantDark
            let hex = isDark ? dark : light
            return NSColor.fromHex(hex) ?? .clear
        })
    }
}

private extension NSColor {
    /// Parses `#RRGGBB`, `#RRGGBBAA`, or `rgba(r,g,b,a)` (decimal) strings.
    static func fromHex(_ str: String) -> NSColor? {
        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("rgba(") || trimmed.hasPrefix("rgb(") {
            let inside = trimmed
                .replacingOccurrences(of: "rgba(", with: "")
                .replacingOccurrences(of: "rgb(", with: "")
                .replacingOccurrences(of: ")", with: "")
            let parts = inside.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 3 else { return nil }
            let r = (Double(parts[0]) ?? 0) / 255
            let g = (Double(parts[1]) ?? 0) / 255
            let b = (Double(parts[2]) ?? 0) / 255
            let a = parts.count >= 4 ? (Double(parts[3]) ?? 1) : 1
            return NSColor(red: r, green: g, blue: b, alpha: a)
        }
        var hex = trimmed
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard let value = UInt64(hex, radix: 16) else { return nil }
        if hex.count == 8 {
            let r = Double((value >> 24) & 0xFF) / 255
            let g = Double((value >> 16) & 0xFF) / 255
            let b = Double((value >> 8)  & 0xFF) / 255
            let a = Double(value & 0xFF) / 255
            return NSColor(red: r, green: g, blue: b, alpha: a)
        } else {
            let r = Double((value >> 16) & 0xFF) / 255
            let g = Double((value >> 8)  & 0xFF) / 255
            let b = Double(value & 0xFF) / 255
            return NSColor(red: r, green: g, blue: b, alpha: 1)
        }
    }
}

/// Swift projection of `/DESIGN.md`. Every token here maps 1:1 to an entry in DESIGN.md's
/// YAML frontmatter. Token changes start in DESIGN.md, then `make design-lint` should pass,
/// then this file is updated to match.
///
/// **Paper-and-Ember redesign (Apr 2026):** complete token rewrite — warm cream paper
/// surfaces, warm-brown foreground tiers, serif body type, single amber accent.
///
/// **Source-stability aliases.** The previous token names (`Kiln.Space.xxs`,
/// `Kiln.Radius.sm`, `Kiln.Font.bodyMD`, etc.) all still resolve. The new design's
/// `s-N` / `r-N` scales are added alongside, so call sites can migrate
/// incrementally.
enum Kiln {

    enum Palette {
        // MARK: - Surface tiers (1:1 with `proto-styles.css :root`)

        /// Root app background — `--paper` `#FAF7F2`. The whole app sits on
        /// this warm cream canvas.
        static let paper        = Color(hex: "#FAF7F2")

        /// Cards, panels — `--surface` `#FFFFFF`. Pure white, slightly lighter
        /// than paper so cards float as paper-on-paper.
        static let surface      = Color(hex: "#FFFFFF")

        /// Secondary fill — `--surface-2` `#F5F1EA`. Chips, kbd, button-secondary.
        static let surface2     = Color(hex: "#F5F1EA")

        /// Sunken regions — `--surface-sunken` `#EDE8DF`. Log blocks, prompt
        /// bars, sample cards.
        static let surfaceSunken = Color(hex: "#EDE8DF")

        /// Post-it card surface — Advisor and Voice Coach. The design uses
        /// `--surface` for these too; the slight warmth comes from context.
        /// Kept as a separate token so call sites can be targeted later.
        static let surfacePaper = Color(hex: "#FFFFFF")

        // MARK: - Foreground tiers — 1:1 with `--on-surface[-N]`

        /// `#1F1B16` — primary text.
        static let onSurface    = Color(hex: "#1F1B16")

        /// `#4A453E` — secondary text.
        static let onSurface2   = Color(hex: "#4A453E")

        /// `#837B6E` — tertiary, captions, mono labels.
        static let onSurface3   = Color(hex: "#837B6E")

        /// `#B5AFA3` — placeholder, disabled, drop-zone *empty-state* border.
        static let onSurface4   = Color(hex: "#B5AFA3")

        // MARK: - Hairlines

        /// `--hairline` `rgba(31,27,22,0.10)`.
        static let hairline     = Color(hex: "#1F1B16").opacity(0.10)

        /// `--hairline-strong` `rgba(31,27,22,0.20)` — the louder edge.
        static let hairlineStrong = Color(hex: "#1F1B16").opacity(0.20)

        /// Legacy alias kept for source-stability — points at `hairline` at
        /// the same quiet alpha so the call sites that previously asked for
        /// "the quieter hairline" still resolve cleanly.
        static let hairline2    = hairline

        // MARK: - The one accent — amber, only on firing moments

        /// `--firing` `#D97706` — the single brand accent. Used only for
        /// firing moments: training progress, drop-zone targeted state,
        /// *Teach* CTA, ember pulse. Never on body text, dividers, or
        /// decorative tints. (DESIGN.md §amber rule.)
        static let firing       = Color(hex: "#D97706")

        /// `--firing-2` `#C2410C` — hover / deeper accent.
        static let firing2      = Color(hex: "#C2410C")

        /// `--firing-wash` `rgba(217, 119, 6, 0.10)` — 10% amber. Targeted
        /// drop-zone fill, signature highlights, gentle row tints.
        static let firingWash   = Color(hex: "#D97706").opacity(0.10)

        /// `--firing-line` `rgba(217, 119, 6, 0.32)` — 32% amber border. Used
        /// on received-state drop zones, persona "active" outlines.
        static let firingLine   = Color(hex: "#D97706").opacity(0.32)

        /// Legacy alias for code that previously consumed a stronger wash.
        /// Points at `firing-line` so existing call sites still resolve.
        static let firingWashStrong = firingLine

        /// White label paired with `firing` on `button-primary` — the only
        /// place amber ever becomes a background.
        static let onFiring     = Color.white

        // MARK: - Status (per proto-styles.css `:root`)

        /// `--success` `#16A34A`.
        static let ok           = Color(hex: "#16A34A")
        static let okWash       = Color(hex: "#16A34A").opacity(0.10)

        /// `--warn` `#CA8A04` — gold, distinct from amber so warnings don't
        /// read as firing moments.
        static let warn         = Color(hex: "#CA8A04")
        static let warnWash     = Color(hex: "#CA8A04").opacity(0.10)

        /// `--danger` `#B91C1C` — error icons + destructive labels only.
        /// Never used as a background fill.
        static let danger       = Color(hex: "#B91C1C")
        static let dangerWash   = Color(hex: "#B91C1C").opacity(0.10)
    }

    enum Font {
        // MARK: - Primary tokens, 1:1 with DESIGN.md typography

        /// Modal / sheet headline — serif 32 / 500 / 1.2.
        static let display = SwiftUI.Font.system(size: 32, weight: .medium, design: .serif)

        /// Panel header — serif 24 / 500 / 1.25.
        static let title   = SwiftUI.Font.system(size: 24, weight: .medium, design: .serif)

        /// Default body — serif 16 / 400 / 1.55. **The hero font.** Used everywhere
        /// prose lives: drop-zone copy, completion text, Voice Coach essay, chat replies.
        static let body    = SwiftUI.Font.system(size: 16, weight: .regular, design: .serif)

        /// UI label — sans 13 / 500 / 1.4. Button labels, settings labels, controls.
        static let label   = SwiftUI.Font.system(size: 13, weight: .medium, design: .default)

        /// Caption — sans 12 / 400 / 1.4. Footnotes, secondary text in chrome.
        static let caption = SwiftUI.Font.system(size: 12, weight: .regular, design: .default)

        /// Mono metadata — mono 11 / 400 / 1.4. Paths, kbd shortcuts, log content.
        static let meta    = SwiftUI.Font.system(size: 11, weight: .regular, design: .monospaced)

        /// Eyebrow / kbd — mono 10 / 500. Used above titled sections; pair with
        /// `.kerning(0.4)` and `.textCase(.uppercase)` at the call site.
        static let eyebrow = SwiftUI.Font.system(size: 10, weight: .medium, design: .monospaced)

        /// Tabular figures (tnum) for incrementing counters. Pair with
        /// `.contentTransition(.numericText())` for per-character crossfade.
        static let numeric = SwiftUI.Font.system(size: 16, weight: .medium, design: .serif)
            .monospacedDigit()

        // MARK: - Source-stability aliases (legacy names → new tokens)

        /// Legacy `bodyMD` alias — same as `body`.
        static let bodyMD = body
        /// Legacy `bodySM` alias — caption is the closest analog.
        static let bodySM = caption
        /// Legacy `mono` alias — same as `meta`.
        static let mono = meta
    }

    enum Space {
        // MARK: - Primary tokens — `s-N` scale per DESIGN.md
        static let s1:  CGFloat = 4
        static let s2:  CGFloat = 8
        static let s3:  CGFloat = 12
        static let s4:  CGFloat = 16
        static let s5:  CGFloat = 20
        static let s6:  CGFloat = 24
        static let s7:  CGFloat = 32
        static let s8:  CGFloat = 40
        static let s9:  CGFloat = 56
        static let s10: CGFloat = 80

        // MARK: - Source-stability aliases (legacy names map onto s-N scale)
        static let xxs: CGFloat = s1   // 4
        static let xs:  CGFloat = s2   // 8
        static let sm:  CGFloat = s3   // 12
        static let m:   CGFloat = s4   // 16
        static let l:   CGFloat = s6   // 24
        static let xl:  CGFloat = s7   // 32
    }

    enum Radius {
        // MARK: - Primary tokens — 1:1 with `proto-styles.css :root`
        // The design's actual scale is sm 4 / md 6 / lg 10 / xl 14 — much
        // tighter than my earlier 4/6/8/10/12/16. Smaller radii read as
        // paper-and-print-quality, not iOS-rounded.
        static let rSm:   CGFloat = 4    // `--r-sm` — tags, kbd, small chips
        static let rMd:   CGFloat = 6    // `--r-md` — buttons, controls
        static let rLg:   CGFloat = 10   // `--r-lg` — drop zone, cards, modals
        static let rXl:   CGFloat = 14   // `--r-xl` — sheet, hero panel
        static let pill:  CGFloat = 999  // pill shapes (chips, tags)

        // MARK: - Source-stability aliases (legacy names → new scale)
        static let r1: CGFloat = rSm     // 4
        static let r2: CGFloat = rMd     // 6
        static let r3: CGFloat = rMd     // 6 (was 8; closest design value)
        static let r4: CGFloat = rLg     // 10
        static let r5: CGFloat = rLg     // 10 (was 12; closest design value)
        static let r6: CGFloat = rXl     // 14 (was 16; closest design value)

        // MARK: - Semantic aliases at call sites
        static let sm: CGFloat = rSm
        static let md: CGFloat = rMd
        static let lg: CGFloat = rLg
        static let control = rMd          // inline buttons, stage badges
        static let card    = rLg          // generic cards, panels — design's `--r-lg` 10
        static let modal   = rXl          // full-bleed modals, sheets
        static let hero    = rXl          // hero card / canvas wrap
    }

    enum Icon {
        /// Inline utility glyph next to body text.
        static let small:       CGFloat = 14
        /// Heading-adjacent glyph paired with a display or title string.
        static let heading:     CGFloat = 22
        /// Quiet hero glyph for empty-state placeholders.
        static let placeholder: CGFloat = 30
        /// Prominent hero glyph for the launch drop zone.
        static let hero:        CGFloat = 34
    }

    enum Motion {
        // MARK: - The kindled curve
        //
        // `cubic-bezier(0.32, 0.72, 0, 1)` — slow to start, settles to neutral.
        // The kiln-firing rhythm in motion form. SwiftUI's `Animation.timingCurve`
        // takes the four control points inline; the constants below pair them
        // with each canonical duration so call sites bind to a *moment*, not a
        // raw bezier.
        private static let cp1x: Double = 0.32
        private static let cp1y: Double = 0.72
        private static let cp2x: Double = 0.0
        private static let cp2y: Double = 1.0

        // MARK: - Timings (paired with kindled by default)

        /// 120ms — hover, press. Use as `.animation(Kiln.Motion.micro, value: …)`.
        static let micro:    Animation = .timingCurve(cp1x, cp1y, cp2x, cp2y, duration: 0.12)

        /// 220ms — tab switch, picker open, micro-toggle.
        static let std:      Animation = .timingCurve(cp1x, cp1y, cp2x, cp2y, duration: 0.22)

        /// 350ms — surface mount, panel reveal. The default `Kiln.Motion.standard`.
        static let kind:     Animation = .timingCurve(cp1x, cp1y, cp2x, cp2y, duration: 0.35)

        /// 360ms — route crossfade between surfaces.
        static let route:    Animation = .timingCurve(cp1x, cp1y, cp2x, cp2y, duration: 0.36)

        /// 1.8s — ember pulse cycle. Alpha-only, repeating, autoreverses.
        static let ember:    Animation = .easeInOut(duration: 1.8)
            .repeatForever(autoreverses: true)

        /// 540ms — typewriter cursor blink cadence. Independent of the
        /// kindled curve (a blink is a metronome, not a transition); kept
        /// here so call sites don't reach for an inline `.easeInOut(duration:)`.
        static let cursorBlink: Animation = .easeInOut(duration: 0.54)
            .repeatForever(autoreverses: true)

        // MARK: - Source-stability aliases (legacy names → new timings)

        static let standard: Animation = kind            // 350ms kindled
        static let glow: Animation     = ember           // 1.8s alpha pulse
        static let microToggle         = micro           // 120ms hover/press
        static let sampleReveal        = kind            // 350ms — was 0.6s; the redesign replaces sample fade with type-on
        static let skeletonPulse       = ember           // 1.8s — was 0.9s; unified with ember cadence

        // MARK: - Stage transition

        /// Crossfade between surface routes, per DESIGN.md ("Crossfades, not slides").
        /// Replaces the previous trailing-/leading-edge slide with a pure opacity swap.
        static let stageTransition: AnyTransition = .opacity.animation(route)
    }

    /// Opacity values for ad-hoc fills. The redesign moves most of these onto
    /// explicit token surfaces (`surface-2`, `surface-sunken`, `firing-wash`,
    /// `firing-wash-strong`) — these tokens are kept for source-stability
    /// during the migration. Where a view used to call
    /// `Color.primary.opacity(Kiln.Opacity.cardFill)`, prefer
    /// `Kiln.Palette.surface2` going forward.
    enum Opacity {
        /// 4% — equivalent of the original ad-hoc card fill. Most call sites
        /// should migrate to `Kiln.Palette.surface2`.
        static let cardFill: Double = 0.04
        /// 6% — equivalent of the original ad-hoc code-fill. Most call sites
        /// should migrate to `Kiln.Palette.surfaceSunken`.
        static let codeFill: Double = 0.06
        /// 8% — the louder neutral track. For new sites prefer
        /// `Kiln.Palette.surfaceSunken` directly.
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
        static let centerMinWidth:  CGFloat = 360
        static let detailMinWidth:  CGFloat = 300
        static let detailIdeal:     CGFloat = 340
        /// Title-bar height for the redesigned shell — 44pt per DESIGN.md.
        static let titleBarHeight:  CGFloat = 44
    }
}
