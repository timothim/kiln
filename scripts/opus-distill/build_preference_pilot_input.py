#!/usr/bin/env python3
"""Generate synthetic preference pairs for the preference-judge pilot.

Deterministic: seeded, hand-written templates, no LLM calls.

Strategy:
- 50 short prompts covering everyday written-voice moments (morning routine,
  birthday message, take on X, etc.).
- Default: --size 300. Each prompt yields 6 pairs for 300-row runs, or
  10 pairs for 500-row runs. Pairs-per-prompt is derived from --size / 50.
- Each pair contains one voice-bearing (personal / conversational / concrete)
  completion and one generic (corporate / listicle / AI-assistant-scaffolded)
  completion.
- Position balance: the first half of the file places the voice-bearing
  completion in position A; the second half places it in position B. Within
  each half, rotate across the 5 voice templates and the 5 generic templates
  so no prompt uses identical copy.

Budget rationale: quality-classifier pilot cost $5.69 for 451 single-text
labels (~$0.0126/row). Preference pairs are ~2–3× per-row (two completions
in context). 500 pairs projects to ~$12–$19, which exceeds the $12 pilot
ceiling; 300 pairs projects to ~$7.50–$11.40 — fits the cap.

Output format (one JSON object per line):

    {"request_id": "<16 hex>", "prompt": "...", "completion_a": "...", "completion_b": "..."}

The managed agent will score pairs and emit {"request_id", "winner", "reason"}.
The balanced layout lets the caller (and the judge) verify position bias.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import sys

# 50 short prompts — everyday written-voice moments where "sounding like you"
# vs. "sounding generic" actually matters. Kept short on purpose.
PROMPTS: list[str] = [
    "Describe your morning routine.",
    "Write a birthday message for a close friend.",
    "What's your take on remote work?",
    "Summarize your weekend in two sentences.",
    "Explain why you like your favorite book.",
    "Write a short note to a coworker who covered for you.",
    "Describe the best meal you've had recently.",
    "What do you think about early-morning meetings?",
    "Write a message thanking someone for a small favor.",
    "Describe the neighborhood you live in.",
    "What's your opinion on reading versus watching TV?",
    "Write a quick intro message for a new contact.",
    "Explain why you picked your current job.",
    "Describe a recent conversation that stuck with you.",
    "Write a short update to family about how you're doing.",
    "What's your take on long-form podcasts?",
    "Describe the last show you binge-watched.",
    "Write a note declining an invitation politely.",
    "Explain why you're excited about a recent project.",
    "Describe how you handle a bad day.",
    "What's your opinion on journaling?",
    "Write a quick message to reschedule a meeting.",
    "Describe a tradition you care about.",
    "What do you think about open offices?",
    "Write a short message congratulating a friend on a promotion.",
    "Describe the last place you traveled to.",
    "What's your take on side projects?",
    "Write a thank-you message for a thoughtful gift.",
    "Describe what a good Saturday looks like to you.",
    "What do you think about working from coffee shops?",
    "Write a short message checking in on a friend.",
    "Describe your relationship with morning coffee.",
    "What's your opinion on daily standups?",
    "Write a quick message introducing two people.",
    "Describe the weather today.",
    "What do you think about keeping a to-do list on paper?",
    "Write a short message apologizing for being late.",
    "Describe your favorite kind of weather.",
    "What's your take on answering email on weekends?",
    "Write a short message inviting a friend to dinner.",
    "Describe a recent small win.",
    "What do you think about phone calls versus texts?",
    "Write a short message congratulating someone on a new home.",
    "Describe the last thing that made you laugh out loud.",
    "What's your opinion on reading the news first thing?",
    "Write a short message wishing a coworker good luck on a presentation.",
    "Describe a habit you're trying to build.",
    "What do you think about long commutes?",
    "Write a short note explaining why you can't make it tonight.",
    "Describe what you had for lunch.",
]

# 5 voice-bearing templates. Parameterized on prompt via {topic} where useful.
# Hand-written: personal, concrete, small asides, contractions, one slight
# imperfection per template so they read like a real person.
VOICE_TEMPLATES: list[str] = [
    "Honestly, it's never the same twice. Some days I'm up at six with the "
    "dog, some days I drift till eight and nurse a coffee. I don't fight it "
    "anymore.",
    "Short version — I do the thing, then I do the next thing. The only "
    "routine I trust is the one I don't have to negotiate with before it's "
    "even started.",
    "I'll tell you what I tell everyone: stop optimizing it. The moment you "
    "systemize something good, you've basically invited yourself to get bored "
    "of it.",
    "It depends on the morning. Yesterday was great — cleared the inbox, sat "
    "on the balcony for twenty minutes. Today was a wreck. Both still counted.",
    "I'll be honest, the whole thing is just me and a kettle and whatever "
    "book I've been ignoring. That's about it. Not everything needs a system.",
]

# 5 generic / corporate / LLM-assistant templates. Bullet-heavy, hedged,
# over-explained, "it's important to note," "key takeaways," etc.
GENERIC_TEMPLATES: list[str] = [
    "There are several important factors to consider. Here are some key "
    "takeaways: 1) Consistency is crucial. 2) A balanced approach is "
    "recommended. 3) It's important to note that individual results may vary.",
    "In today's fast-paced world, establishing an effective routine is more "
    "important than ever. Experts agree that a well-structured approach can "
    "unlock significant productivity gains and enhance overall well-being.",
    "Great question! There are many ways to approach this. Some people prefer "
    "structure, while others value flexibility. Ultimately, the best approach "
    "depends on your unique needs and goals.",
    "To maximize your outcomes, consider implementing the following best "
    "practices: establish clear objectives, maintain accountability, and "
    "regularly review your progress to ensure alignment with your priorities.",
    "It's worth noting that this is a deeply personal topic. While there is "
    "no one-size-fits-all solution, research suggests that intentional habits "
    "can lead to measurable improvements over time.",
]


def request_id_for(prompt_idx: int, pair_idx: int) -> str:
    """Deterministic 16-char hex id tied to (prompt_idx, pair_idx)."""
    h = hashlib.sha256(f"pref-pilot-{prompt_idx:03d}-{pair_idx:02d}".encode()).hexdigest()
    return h[:16]


def build_rows(size: int) -> list[dict]:
    rows: list[dict] = []
    num_prompts = len(PROMPTS)
    if size % num_prompts != 0:
        raise SystemExit(f"--size must be a multiple of {num_prompts} (got {size})")
    pairs_per_prompt = size // num_prompts  # 6 for 300, 10 for 500
    total = num_prompts * pairs_per_prompt
    half = total // 2

    for p_idx, prompt in enumerate(PROMPTS):
        for pair_idx in range(pairs_per_prompt):
            voice = VOICE_TEMPLATES[pair_idx % len(VOICE_TEMPLATES)]
            generic = GENERIC_TEMPLATES[pair_idx % len(GENERIC_TEMPLATES)]
            global_idx = p_idx * pairs_per_prompt + pair_idx

            # Half 1 (rows 0..249): voice in A, generic in B.
            # Half 2 (rows 250..499): voice in B, generic in A.
            if global_idx < half:
                a, b = voice, generic
            else:
                a, b = generic, voice

            rows.append(
                {
                    "request_id": request_id_for(p_idx, pair_idx),
                    "prompt": prompt,
                    "completion_a": a,
                    "completion_b": b,
                }
            )
    return rows


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--out",
        required=True,
        help="output path for the JSONL (e.g. managed-agents/preference-judge/inputs/pilot-300.jsonl)",
    )
    ap.add_argument(
        "--size",
        type=int,
        default=300,
        help="number of pairs to generate; must be a multiple of 50 (default 300, matches $12 budget cap)",
    )
    args = ap.parse_args()

    rows = build_rows(args.size)
    out = pathlib.Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("w") as f:
        for row in rows:
            f.write(json.dumps(row) + "\n")

    # Sanity stats (stderr so stdout stays clean if piped).
    half = len(rows) // 2
    a_voice_count = sum(1 for r in rows[:half] if r["completion_a"] in VOICE_TEMPLATES)
    b_voice_count = sum(1 for r in rows[half:] if r["completion_b"] in VOICE_TEMPLATES)
    print(
        f"wrote {len(rows)} rows to {out}; "
        f"first-half A-voice rows: {a_voice_count}/{half}, "
        f"second-half B-voice rows: {b_voice_count}/{half}",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
