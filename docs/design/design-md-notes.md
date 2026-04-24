# DESIGN.md — spec notes for Kiln

Reference for how Kiln adopts the [google-labs-code/design.md](https://github.com/google-labs-code/design.md) format. This file records what we rely on from the spec, what we extend, and how the tooling is wired into our workflow.

---

## 1. What DESIGN.md is

A single-file format for describing a visual identity to coding agents. YAML frontmatter encodes machine-readable tokens (colors, typography, spacing, rounding, components). The markdown body encodes human-readable rationale. Both halves live in one file so agents reading the file get tokens *and* the reasoning behind them.

- **License:** Apache-2.0.
- **Status:** `alpha`. The spec, token schema, and CLI are under active development — we should expect changes and re-validate when bumping the package.

## 2. Frontmatter schema — what we use

| Key | Required? | Shape | Kiln usage |
|---|---|---|---|
| `name` | yes | string | `Kiln` |
| `description` | no | string | One-sentence product identity |
| `version` | no | string (`alpha`) | Not pinned — we track the package version |
| `colors` | no | map of `<name>: "#hex"` (SRGB) | Firing amber + neutrals + semantic roles |
| `typography` | no | map of `<name>: { fontFamily, fontSize, fontWeight, lineHeight, letterSpacing, fontFeature?, fontVariation? }` | SF Pro hierarchy + SF Mono + numericText |
| `spacing` | no | map of `<name>: <Dimension\|number>` | 4-pt grid tokens (xxs/xs/sm/m/l/xl) |
| `rounded` | no | map of `<name>: <Dimension>` | Control, card, modal radii |
| `components` | no | map of `<name>: { backgroundColor, textColor, typography, rounded, padding, size, height, width }` | Firing-stage UI primitives |

**Token references** use curly braces: `"{colors.firing}"`, `"{rounded.md}"`, `"{typography.body-md}"`. Composite references (one token referencing another) are permitted only inside the `components` section.

**Component variants** follow `-hover` / `-active` / `-disabled` suffixes on the same base name (e.g. `button-primary`, `button-primary-hover`).

## 3. Canonical section order (prose body)

1. Overview
2. Colors
3. Typography
4. Layout
5. Elevation & Depth
6. Shapes
7. Components
8. Do's and Don'ts

Out-of-order sections trigger the `section-order` lint rule (warning). Duplicate section headings are rejected outright (error). Unknown headings are preserved — the linter does not strip them.

## 4. Lint rules

| Rule | Severity | What it checks |
|---|---|---|
| `broken-ref` | **error** | A `{path.to.token}` reference that doesn't resolve to a defined token |
| `missing-primary` | warning | No primary color defined |
| `contrast-ratio` | warning | WCAG AA ratio below 4.5 : 1 between a text color and its background |
| `orphaned-tokens` | warning | Tokens declared but never referenced |
| `missing-typography` | warning | Colors defined but no typography tokens |
| `section-order` | warning | Prose sections out of canonical order |
| `token-summary` | info | Informational summary of counts |

**No suppression mechanism.** Unknown content is preserved rather than suppressed; you cannot silence a rule via inline directives. Our strategy for Kiln-specific divergences from the warnings is to document them in a dedicated prose section (see §6 below).

## 5. CLI

```
npx @google/design.md lint    DESIGN.md [--format json]
npx @google/design.md diff    DESIGN.md DESIGN-v2.md [--format json]
npx @google/design.md export  --format [tailwind|dtcg] DESIGN.md
npx @google/design.md spec    [--rules] [--format json|markdown]
```

- `lint` exits nonzero on `error`-severity findings (only `broken-ref`); warnings do not fail CI by default.
- `export --format dtcg` produces [Design Token Community Group](https://design-tokens.github.io/community-group/format/) JSON — the format consumed by Figma Tokens, Style Dictionary, and other downstream tools.
- `diff` is useful in review — it surfaces token-level changes between two DESIGN.md versions.

## 6. How Kiln integrates

### 6.1 Where the file lives

`/DESIGN.md` at repo root. Single source of truth. `apps/Kiln/Sources/DesignSystem.swift` is its Swift projection — edits start in `DESIGN.md`, then flow to Swift in Phase 2.

### 6.2 Tooling

- Root-level `package.json` declares `@google/design.md` as a `devDependency`.
- `make design-lint` runs `npx @google/design.md lint DESIGN.md`. Degrades gracefully when npx is absent (matches the Makefile house style).
- `make design-export` writes `docs/design/tokens.dtcg.json`. The snapshot is committed so PR diffs stay readable.
- `.claude/hooks/pre-commit.sh` gates commits that stage `DESIGN.md`: if the file is in the index, `make design-lint` must pass. Non-DESIGN.md commits are unaffected and still only gate on `make test`.

### 6.3 Handling alpha-spec divergence

`@google/design.md` encodes generic design-web conventions (a primary color, a color-token-per-role layout). A macOS-native SwiftUI app deliberately relies on system semantic colors (`.primary`, `.secondary`, `.tertiary`) that adapt to light/dark mode automatically. A few lint rules therefore fire on Kiln despite our choices being intentional:

- **`missing-primary`**: we do not have a "brand primary" color in the web sense. Our single accent is `firing` (amber), used sparingly for firing moments. We document this in the prose; we do not invent a primary just to satisfy the rule.
- **`contrast-ratio`**: light/dark adaptive colors have no single hex, so the linter cannot measure their contrast. We declare light-mode hex approximations for lint coverage and explain the dark-mode pairing in prose.
- **`orphaned-tokens`**: some tokens (e.g. numeric-text typography) are consumed by SwiftUI modifiers rather than by `components` map entries. The linter cannot see these usages; we acknowledge the warning.

Divergences are listed in DESIGN.md's `## Do's and Don'ts` → *macOS-native conventions* subsection so they are visible to any agent reading the file.

### 6.4 Alpha-spec risk

Because the format is alpha, token schema and CLI surface may change. Mitigations:

- We pin the `@google/design.md` version in `package.json` + `package-lock.json`. Upgrades are an explicit PR, not automatic.
- We keep the DTCG export committed so the token snapshot is comparable across format revisions.
- We own DESIGN.md structurally — if a spec change demands migration, we migrate deliberately rather than accept breaking churn.

## 7. Workflow recap

1. Edit a design token → edit `/DESIGN.md`.
2. `make design-lint` → must be clean (or have a documented divergence).
3. Commit (pre-commit hook re-runs the lint automatically).
4. If the token is referenced from Swift, update `apps/Kiln/Sources/DesignSystem.swift` in the same commit to keep the Swift projection in sync (Phase 2+).
5. Re-export DTCG snapshot when tokens move: `make design-export`.
