#!/usr/bin/env python3
"""Generate synthetic preference pairs for the preference-judge pilot/full run.

Deterministic: seeded, hand-written templates, no LLM calls.

Strategy:
- 50 short prompts covering everyday written-voice moments (morning routine,
  birthday message, take on X, etc.).
- --size N (default 300). Each prompt yields N/50 pairs.
- Each pair contains one voice-bearing (personal / conversational / concrete)
  completion and one generic (corporate / listicle / AI-assistant-scaffolded)
  completion.
- **Position randomized per row** using a seeded deterministic RNG. For each
  (prompt_idx, pair_idx) we pick a coin — heads → voice in A, tails → voice in
  B. The coin is derived from a SHA-256 of the row key, so runs are reproducible.
  We do NOT use the first-half / second-half layout any more: the previous
  layout let a naive judge encode `if global_idx < half: pick A else pick B`
  as a shortcut, even though the judge is supposed to read the completions.
- **20 voice + 20 generic templates** (up from 5 each). The expanded pool
  removes the ability to memorize a handful of prefixes and substring-match
  the input. Every template is prompt-agnostic so any prompt can pair with any
  template without producing nonsense.

Budget rationale: quality-classifier pilot cost $5.69 for 451 single-text
labels (~$0.0126/row). Preference pairs are ~2–3× per-row (two completions
in context). 2000 pairs at managed-agent pricing is well within the demo
budget; 300-pair pilot runs stay cheap.

Output format (one JSON object per line):

    {"request_id": "<16 hex>", "prompt": "...", "completion_a": "...", "completion_b": "..."}

The managed agent will score pairs and emit {"request_id", "winner", "reason"}.
Position randomization lets the caller (and the judge) verify position bias:
if the resulting winner distribution is ~50/50 A/B, the judge is reading the
text rather than picking by slot.
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

# 20 voice-bearing templates. Personal, concrete, conversational. Varied
# rhythm, vocabulary, length. A couple lean wry, a couple lean earnest, a
# couple lean terse, a couple lean reflective. Hand-written.
VOICE_TEMPLATES: list[str] = [
    "Honestly, it's never the same twice. Some days I'm up at six with the dog, some days I drift till eight and nurse a coffee. I don't fight it anymore.",
    "Short version — I do the thing, then I do the next thing. The only routine I trust is the one I don't have to negotiate with before it's even started.",
    "I'll tell you what I tell everyone: stop optimizing it. The moment you systemize something good, you've basically invited yourself to get bored of it.",
    "It depends on the morning. Yesterday was great — cleared the inbox, sat on the balcony for twenty minutes. Today was a wreck. Both still counted.",
    "I'll be honest, the whole thing is just me and a kettle and whatever book I've been ignoring. That's about it. Not everything needs a system.",
    "Okay so — I put the kettle on, I stare at nothing, and then somewhere around the third sip it becomes a day. There isn't much more to it than that.",
    "Funny you ask. I used to think I had one. Turns out I just have a rotation of three moods and the weather decides which one shows up.",
    "My take? Overrated as a concept, underrated as a constraint. The shape of the morning matters more than what's in it, and I figured that out late.",
    "Look, I get up, I don't talk to anyone for forty minutes, and I consider that a success. Anything beyond that is gravy. Most days there's no gravy.",
    "You want the real answer or the polite one. Real one: I wing it and lie about it later when someone asks if I'm a morning person.",
    "Here's the thing — I kept trying to make it a ritual and it kept refusing. So now it's just a sequence of small things I don't resent. Good enough.",
    "Grew up with a dad who read the paper in silence for an hour and I swore I'd never do that. Now I read my phone in silence for an hour. Progress.",
    "Best morning I've had in months was last Tuesday. Rain, no plans, toast. That's the bar now and most days don't clear it, which is fine.",
    "I'm not going to pretend it's a thing. I put shoes on, I drink something warm, I answer one email I shouldn't. That's the whole script.",
    "There's a window, maybe twenty minutes, where nothing's happened yet and everything still could. I try to protect that and I fail about half the time.",
    "My partner thinks I'm a morning person and I think I'm a person who drinks coffee quickly enough to pass. These are different claims.",
    "Truthfully the routine is the cat. Cat gets fed, cat gets petted, cat decides I may now make breakfast. I'm not in charge here and I've made peace with it.",
    "If I've got a good one going it's because I stopped checking the news before nine. That one change did more than any app or book I tried before it.",
    "I keep it boring on purpose — same mug, same corner of the couch, same order. Boring is the point; boring is what the rest of the day isn't.",
    "On a great day I'm outside by seven. On a normal day I'm upright by nine. On a rough day I negotiate with the ceiling for a while. All three count.",
]

# 20 generic / corporate / LLM-assistant templates. Bullet-heavy, hedged,
# over-explained, listicle cadence, "it's important to note," "key takeaways,"
# corporate-wellness register.
GENERIC_TEMPLATES: list[str] = [
    "There are several important factors to consider. Here are some key takeaways: 1) Consistency is crucial. 2) A balanced approach is recommended. 3) It's important to note that individual results may vary.",
    "In today's fast-paced world, establishing an effective routine is more important than ever. Experts agree that a well-structured approach can unlock significant productivity gains and enhance overall well-being.",
    "Great question! There are many ways to approach this. Some people prefer structure, while others value flexibility. Ultimately, the best approach depends on your unique needs and goals.",
    "To maximize your outcomes, consider implementing the following best practices: establish clear objectives, maintain accountability, and regularly review your progress to ensure alignment with your priorities.",
    "It's worth noting that this is a deeply personal topic. While there is no one-size-fits-all solution, research suggests that intentional habits can lead to measurable improvements over time.",
    "Here's a comprehensive overview of the key considerations: First, it's essential to understand your baseline. Second, leverage proven frameworks. Third, iterate based on measurable feedback loops.",
    "This is a multifaceted question that deserves a thoughtful response. In general, experts recommend a balanced, evidence-based approach tailored to your specific context and long-term objectives.",
    "There are a number of strategies you can employ to achieve optimal results. The most effective approaches typically combine structure, intentionality, and a willingness to adapt as circumstances evolve.",
    "It's important to approach this topic with nuance. Research indicates that outcomes are influenced by a wide range of variables, including individual preferences, environmental factors, and personal goals.",
    "Let's break this down into digestible components: Understanding the fundamentals. Identifying your priorities. Developing an actionable framework. Monitoring and adjusting as needed for continuous improvement.",
    "When considering this topic, it's helpful to reflect on a few foundational principles: clarity of purpose, consistency of practice, and a commitment to ongoing learning and self-improvement.",
    "To provide a thorough response, let's explore several perspectives. While preferences vary, most successful individuals emphasize the importance of intentionality, reflection, and adaptive strategy.",
    "Here are some practical tips to consider: 1. Start small. 2. Build gradually. 3. Track your progress. 4. Celebrate wins. 5. Remain flexible. These principles apply across a wide variety of contexts.",
    "This is an area where many people find success by following established best practices. Generally speaking, a disciplined, goal-oriented approach yields the most sustainable long-term outcomes.",
    "In summary, the most effective approach involves a combination of clear goals, consistent action, and thoughtful reflection. These elements work together to create a framework for sustained growth.",
    "It would be beneficial to consider the broader context. Factors such as environment, mindset, and external support systems all play a significant role in shaping your overall experience and results.",
    "A holistic approach is often recommended. By integrating multiple dimensions — physical, mental, emotional, and social — individuals can create a more balanced and fulfilling lived experience.",
    "Let me provide you with some guidance on this topic. Fundamentally, success in this area hinges on aligning your actions with your values and maintaining a growth-oriented mindset throughout the journey.",
    "From a high-level perspective, there are several key dimensions to consider. Each contributes uniquely to the overall outcome, and the interplay between them can significantly influence your experience.",
    "It's essential to recognize that meaningful change takes time. By committing to a structured process and leveraging proven methodologies, you can create lasting positive impact in the areas that matter most.",
]


def request_id_for(prompt_idx: int, pair_idx: int) -> str:
    """Deterministic 16-char hex id tied to (prompt_idx, pair_idx)."""
    h = hashlib.sha256(f"pref-pilot-{prompt_idx:03d}-{pair_idx:02d}".encode()).hexdigest()
    return h[:16]


def voice_in_a(prompt_idx: int, pair_idx: int) -> bool:
    """Seeded per-row coin toss. True → voice in A, False → voice in B.

    Uses a separate hash namespace from request_id so the two aren't correlated.
    """
    h = hashlib.sha256(f"pref-position-{prompt_idx:03d}-{pair_idx:02d}".encode()).hexdigest()
    return int(h[:8], 16) % 2 == 0


def build_rows(size: int) -> list[dict]:
    rows: list[dict] = []
    num_prompts = len(PROMPTS)
    if size % num_prompts != 0:
        raise SystemExit(f"--size must be a multiple of {num_prompts} (got {size})")
    pairs_per_prompt = size // num_prompts

    for p_idx, prompt in enumerate(PROMPTS):
        for pair_idx in range(pairs_per_prompt):
            voice = VOICE_TEMPLATES[(p_idx * 7 + pair_idx * 3) % len(VOICE_TEMPLATES)]
            generic = GENERIC_TEMPLATES[(p_idx * 11 + pair_idx * 5) % len(GENERIC_TEMPLATES)]

            if voice_in_a(p_idx, pair_idx):
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
        help="number of pairs to generate; must be a multiple of 50 (default 300)",
    )
    args = ap.parse_args()

    rows = build_rows(args.size)
    out = pathlib.Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("w") as f:
        for row in rows:
            f.write(json.dumps(row) + "\n")

    voice_in_a_count = sum(1 for r in rows if r["completion_a"] in VOICE_TEMPLATES)
    voice_in_b_count = len(rows) - voice_in_a_count
    unique_a_prefixes = len({r["completion_a"][:40] for r in rows})
    unique_b_prefixes = len({r["completion_b"][:40] for r in rows})
    print(
        f"wrote {len(rows)} rows to {out}; "
        f"voice-in-A: {voice_in_a_count}/{len(rows)} "
        f"(expected ~{len(rows)//2}), "
        f"unique completion_a 40-char prefixes: {unique_a_prefixes}, "
        f"unique completion_b 40-char prefixes: {unique_b_prefixes}",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
