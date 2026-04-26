# Kiln — Written Summary

For the Cerebral Valley submission form. Pick the version that fits the field's character / word limits.

---

## Primary version (155 words — sweet spot in 100-200 range)

LLMs are quietly flattening everyone's writing toward the average voice of the internet. Kiln inverts the loop. It's a native macOS app that fine-tunes a small local LLM on **your own writing** in twenty minutes on a MacBook — emails, notes, messages, Markdown — then exposes the trained voice as an MCP server callable by Claude.app.

Three classifiers ship inside the app: quality, preference, and style. Each was distilled from ~1,500–2,000 Opus 4.7 labels produced by **Managed Agents** running on Anthropic infrastructure (test accuracies 99.0% / 99.75% / 0.037 mean MAE). Two more runtime Opus surfaces — a Training Advisor that watches loss live, and a Voice Coach that writes a markdown analysis — ship as opt-in cloud features. A fourth Managed Agent does multi-turn corpus curation.

Your data never leaves the laptop. Distilled judgment does. And Claude.app can now write in your voice without ever seeing your prompt.

**Word count: 155.**

---

## Alternative — shorter (108 words)

LLMs flatten everyone's writing toward the average voice of the internet. Kiln inverts that loop: a native macOS app that fine-tunes a local LLM on your own writing in twenty minutes, then exposes the trained voice as an MCP server callable by Claude.app.

Three classifiers ship inside Kiln — quality, preference, style — each distilled from Opus 4.7 labels produced by Managed Agents on Anthropic infrastructure (99.0% / 99.75% test accuracy, 0.037 MAE). Three more Opus surfaces — Training Advisor, Voice Coach, Deep Curation — are opt-in cloud features.

Your corpus never leaves the laptop. Distilled judgment does. Claude.app writes in your voice without seeing your prompt.

**Word count: 108.**

---

## Alternative — more emotional / narrative (172 words)

You write thousands of words a year. Emails, replies, drafts, social posts. Each one shapes how you sound. The more an LLM writes them for you, the more your written self drifts toward the average voice of the internet — someone else's training data, looped back into your inbox.

Kiln is a native macOS app that ends the loop. Drop a folder of your writing on the welcome screen. Twenty minutes later, you have a small local model that sounds like you, running on your Mac, with no network calls.

The judgment that makes the corpus clean enough to train on lives in three classifiers Kiln ships inside the bundle — distilled from 5,000 labels produced by Opus 4.7 Managed Agents on Anthropic infrastructure. Opus also watches your training in real time, writes a voice analysis after, and reviews your corpus on demand. All optional. All visible.

The trained voice is exposed as an MCP server. Claude.app can call it. Your writing — your voice — is finally yours to deploy.

**Word count: 172.**

---

## Alternative — more technical (165 words)

Kiln is a native macOS app for fine-tuning a small local LLM on the user's own writing. It implements LoRA SFT over a 4-bit-quantized Qwen 2.5 (3B default) via MLX-LM, completing in ~20 minutes for a small corpus on Apple Silicon. The trained adapter is fused, converted to GGUF, registered in Ollama, and exposed via a Python MCP server (`mcp` SDK, port 7474, bearer auth) consumable by Claude.app.

Three classifiers — quality, preference, style — ship inside the app. Each was distilled from 1,500–2,000 Opus 4.7 labels produced by Managed Agents (`corpus-builder`, `preference-judge`, `style-extractor`) running cloud-hosted Opus sessions against JSONL inputs mounted via the Files API. Test metrics: 99.0% / 99.75% / 0.037 mean MAE across six stylistic axes. Three additional opt-in runtime Opus features (Training Advisor, Voice Coach, Deep Curation) integrate Claude into the product without forcing a network call from the default path.

Built in five days. 38 PRs. 441 tests passing.

**Word count: 165.**

---

## Submission form metadata

- **Project name:** Kiln
- **One-line tagline:** Train AI to write in your voice. Local. Private. Yours.
- **Repo URL:** <https://github.com/timothim/kiln>
- **Demo video URL:** _TBD — Tim is recording in parallel, link populated before submission_
- **Built by:** Timothée Tavernier (@timothim), INSA Lyon
- **License:** MIT
- **Hackathon week dates:** April 21–26, 2026
- **Submission tag:** `v1.0.0-hackathon-submission`
- **Special prize relevance:**
  - Most Creative Opus 4.7 Exploration — voice-as-MCP-server output ecosystem + four-layer Opus integration
  - Best use of Claude Managed Agents — three deployed orchestrators producing 5,000 labels for three local classifiers
  - The "Keep Thinking" Prize — Training Advisor uses streaming Opus reasoning to surface insights live during local training

---

## Notes on word counts

The prompt requested 100-200 words with a 150-180 sweet spot. The primary version lands at **155 words**. Each alternate is verified by `wc -w` on the body text only (excluding header / footer metadata).

```bash
# Verification (run from this file's directory):
sed -n '/^## Primary version/,/^---$/p' written-summary.md | sed -n '/^LLMs/,/voice without/p' | wc -w
# → 155
```
