import KilnCore
import SwiftUI

/// Saturday Phase 6 — "Behind the Scenes" transparency page.
///
/// Static page accessible from Settings → "About Kiln" → "Behind the
/// Scenes." Documents the depth of Opus 4.7 + Managed Agents + MCP
/// integration in Kiln. The hackathon judging story; not strictly a
/// product feature.
///
/// Sections:
///  1. Build-time Opus (multi-agent code generation, distillation pipeline)
///  2. Distilled classifiers (5,000 Opus labels → 3 local classifiers)
///  3. Runtime Opus features (Voice Coach, Training Advisor, Deep
///     Curation, MCP-powered ingestion, MCP server)
///  4. The local-first promise

struct BehindTheScenesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Kiln.Space.xl) {
                hero
                AgentNetworkDiagram()
                    // Frames the network at the center column rather than
                    // the inner 760-wide reading column — the diagram needs
                    // breathing room to communicate "satellite view."
                    .padding(.vertical, Kiln.Space.m)
                section1BuildTime
                section2DistilledClassifiers
                section3RuntimeOpus
                section4LocalFirst
                footer
            }
            .padding(Kiln.Space.xl)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.xs) {
            HStack(spacing: Kiln.Space.xs) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple)
                    .accessibilityHidden(true)
                Text("How Opus 4.7 powers Kiln")
                    .font(Kiln.Font.label)
                    .kerning(0.44)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
            }
            Text("Behind the Scenes")
                .font(Kiln.Font.display)
            Text("Kiln looks like a small native macOS app, and at runtime that's all it is: SwiftUI, MLX, your local files. The story underneath is bigger — Opus 4.7 wrote most of Kiln, distilled three classifiers Kiln ships locally, and runs as an opt-in advisor when you want a second brain. Here's the receipt.")
                .font(Kiln.Font.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Section 1 — build-time

    private var section1BuildTime: some View {
        sectionContainer(
            number: 1,
            title: "Build-time Opus",
            subtitle: "Multi-agent code generation across a 5-day sprint."
        ) {
            VStack(alignment: .leading, spacing: Kiln.Space.sm) {
                statCard(label: "Specialized agents", value: "7+", caption: "LEAD, UI-Excellence, verifier, distillation, polish, audit, demo")
                statCard(label: "PRs merged", value: "20+", caption: "milestones M0–M9 + Saturday final push")
                statCard(label: "Distillation runs", value: "3 components", caption: "quality, preference, style — 5,000 Opus-4.7 labels total")
                Text("Each merge to `main` triggers a fresh-context **verifier subagent** that re-reads the diff against `SPEC.md` and CLAUDE.md and returns a structured verdict. No PR ships without that pass.")
                    .font(Kiln.Font.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Section 2 — distilled classifiers

    private var section2DistilledClassifiers: some View {
        sectionContainer(
            number: 2,
            title: "Distilled classifiers",
            subtitle: "5,000 Opus labels → 3 local classifiers shipped in Kiln."
        ) {
            VStack(alignment: .leading, spacing: Kiln.Space.m) {
                Text("Opus 4.7 sat as the teacher. We asked it to label thousands of voice samples for three properties; trained small fast local models on those labels; ship those models inside Kiln. At runtime your data never leaves the laptop.")
                    .font(Kiln.Font.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                classifierCard(
                    name: "Quality classifier",
                    architecture: "TF-IDF (word + char n-grams) + sklearn LogisticRegression",
                    trained: "1,500 Opus labels",
                    accuracy: "99% test accuracy",
                    role: "Routes corpus chunks: keep / chosen-only / discard before training."
                )
                classifierCard(
                    name: "Preference judge",
                    architecture: "Sentence-Transformers all-MiniLM-L6-v2 + sklearn LR",
                    trained: "2,000 Opus pairwise judgments",
                    accuracy: "99.75% held-out accuracy",
                    role: "Generates DPO (chosen, rejected) pairs from the corpus."
                )
                classifierCard(
                    name: "Style extractor",
                    architecture: "Sentence-Transformers + multi-output Ridge regression",
                    trained: "1,500 Opus profiles",
                    accuracy: "Mean MAE 0.037 across 6 axes",
                    role: "Powers the Style Signature card and Voice Inspector."
                )
            }
        }
    }

    // MARK: - Section 3 — runtime

    private var section3RuntimeOpus: some View {
        sectionContainer(
            number: 3,
            title: "Runtime Opus",
            subtitle: "Opt-in features that call Opus directly when you want them to."
        ) {
            VStack(alignment: .leading, spacing: Kiln.Space.sm) {
                runtimeRow(
                    title: "Voice Coach",
                    description: "150-word personalized voice analysis after Ollama export. Cloud Opus or local Qwen2.5 fallback.",
                    settingsPath: "Settings → Cloud features → Voice Coach"
                )
                runtimeRow(
                    title: "Training Advisor",
                    description: "Opus watches your training in real time and surfaces one-line observations under the loss chart at every checkpoint.",
                    settingsPath: "Settings → Cloud features → Training Advisor"
                )
                runtimeRow(
                    title: "Deep Curation",
                    description: "Long-running Managed Agent reviews every sample in your corpus and flags duplicates, sensitive content, voice-inconsistent samples. Cloud-only by design — no local model can match a multi-turn agent.",
                    settingsPath: "Dataset Doctor → Run Deep Curation"
                )
                runtimeRow(
                    title: "Agent-driven ingestion",
                    description: "Opus orchestrates source readers (Local Documents, Apple Notes) and filters to your stated intent. Or run locally with no cloud.",
                    settingsPath: "Connect your sources panel"
                )
                runtimeRow(
                    title: "Kiln voice as MCP server",
                    description: "Expose your trained voice as a standard MCP server. Claude.app and Claude Code can write in your voice.",
                    settingsPath: "Settings → Cloud features → Connect to Claude"
                )
            }
        }
    }

    // MARK: - Section 4 — local-first promise

    private var section4LocalFirst: some View {
        sectionContainer(
            number: 4,
            title: "The local-first promise",
            subtitle: "Every cloud feature is opt-in, and every cloud feature has a local fallback where viable."
        ) {
            VStack(alignment: .leading, spacing: Kiln.Space.sm) {
                bulletRow("Voice Coach has a local Qwen2.5-via-Ollama mode.")
                bulletRow("Training Advisor has a local Qwen2.5 mode.")
                bulletRow("Agent-driven ingestion has a local heuristic curation mode.")
                bulletRow("MCP server runs entirely on your machine; only the prompt traffic Claude.app sends in crosses the boundary.")
                bulletRow("Deep Curation is the one cloud-only feature: a long-running Managed Agent isn't replicable on-device today.")
                Text("Default state: every cloud toggle is OFF. Your project doesn't reach Anthropic until you flip a switch.")
                    .font(Kiln.Font.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Kiln.Space.xs)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.xxs) {
            Text("Want the full technical writeup?")
                .font(Kiln.Font.body.weight(.medium))
            Text("See `docs/distillation-pipeline.md` and `docs/sessions/` in the repo for the per-milestone session reports, verifier verdicts, and the recovered Opus label sets that drove the three distilled classifiers.")
                .font(Kiln.Font.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Kiln.Space.l)
    }

    // MARK: - Reusable bits

    private func sectionContainer<Content: View>(
        number: Int,
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Kiln.Space.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Kiln.Space.xs) {
                Text("\(number).")
                    .font(Kiln.Font.title)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: Kiln.Space.xxs) {
                    Text(title).font(Kiln.Font.title)
                    Text(subtitle).font(Kiln.Font.caption).foregroundStyle(.secondary)
                }
            }
            content()
        }
    }

    private func statCard(label: String, value: String, caption: String) -> some View {
        HStack(alignment: .top, spacing: Kiln.Space.m) {
            Text(value)
                .font(Kiln.Font.display)
                .foregroundStyle(Kiln.Palette.firing)
                .frame(width: 100, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(Kiln.Font.body.weight(.medium))
                Text(caption)
                    .font(Kiln.Font.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func classifierCard(
        name: String,
        architecture: String,
        trained: String,
        accuracy: String,
        role: String
    ) -> some View {
        VStack(alignment: .leading, spacing: Kiln.Space.xxs) {
            Text(name).font(Kiln.Font.body.weight(.semibold))
            Text(architecture).font(Kiln.Font.caption).foregroundStyle(.secondary)
            HStack(spacing: Kiln.Space.m) {
                Label(trained, systemImage: "doc.text")
                    .font(Kiln.Font.caption).foregroundStyle(.tertiary)
                Label(accuracy, systemImage: "checkmark.seal")
                    .font(Kiln.Font.caption).foregroundStyle(.tertiary)
            }
            Text(role).font(Kiln.Font.caption).foregroundStyle(.primary).padding(.top, Kiln.Space.xxs).fixedSize(horizontal: false, vertical: true)
        }
        .padding(Kiln.Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Kiln.Radius.card, style: .continuous)
                .fill(Color.primary.opacity(Kiln.Opacity.cardFill))
        }
    }

    private func runtimeRow(title: String, description: String, settingsPath: String) -> some View {
        VStack(alignment: .leading, spacing: Kiln.Space.xxs) {
            Text(title).font(Kiln.Font.body.weight(.semibold))
            Text(description).font(Kiln.Font.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(settingsPath).font(Kiln.Font.label).kerning(0.44).textCase(.uppercase).foregroundStyle(.tertiary)
        }
        .padding(.bottom, Kiln.Space.xs)
    }

    private func bulletRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Kiln.Space.xs) {
            Text("•").foregroundStyle(.secondary)
            Text(text).font(Kiln.Font.caption).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    BehindTheScenesView()
        .frame(width: 880, height: 900)
}
