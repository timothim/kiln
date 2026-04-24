#!/usr/bin/env python3
"""Generate the synthetic "Alex Rivers" demo corpus.

Deterministic: a seeded RNG (default 20260424) plus template substitution
produces identical bytes each run. Output lives at
`tests/fixtures/demo_corpus/` (see that directory's PERSONA.md for the
voice spec).

The corpus is checked into the repo so the North-Star Demo can run
offline. Regenerate with:

    python scripts/demo-dataset/generate.py \
        --out tests/fixtures/demo_corpus \
        --seed 20260424

Total size is capped at 10 MB; the generator will refuse to write if the
cap is breached (so adding templates does not silently balloon the
fixture). Chunk count (at sentence granularity after ingestion) targets
~3000 so the adapter has enough signal to pick up Alex's tells.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import pathlib
import random
import sys

# ---------------------------------------------------------------------------
# vocabulary and micro-templates — the whole voice of Alex lives here.

NAMES_TEAM = ["Priya", "Theo", "Sofia", "Rui", "Noor", "Marta"]
NAMES_FRIEND = ["Duarte", "Inês", "Jakub", "Yasmin", "Tomás"]
PLACES = [
    "Lisbon", "Porto", "Bairro Alto", "Alfama", "Chiado",
    "Sintra", "Serra da Estrela", "Cascais", "Belém",
]
CAFES = ["Copenhagen Coffee Lab", "Fábrica", "Hello Kristof", "Dear Breakfast"]
TOOLS = [
    "mlx", "pytest", "ruff", "ollama", "the sidecar", "xcodebuild",
    "swift test", "the trainer", "the dataset doctor",
]
PKGS = ["lora", "tokenizers", "numpy", "anthropic", "httpx", "pydantic"]

MORNING_OPENINGS = [
    "Slept poorly. Two coffees before noon — regret.",
    "Up early. Fog over the river.",
    "Woke before the alarm, which is new.",
    "Late start. Skipped the run.",
    "Clear morning. Ran along the avenida.",
    "Feverish yesterday; better today. Took it slow.",
    "Rain since 5. Stayed in.",
]
WORK_FRAGMENTS = [
    "Worked on the {tool} pass. {knob} is the right knob; {lower} over-merged, {upper} missed the obvious near-dupes. Kept it.",
    "Priya pushed the {pkg} bump. Broke one test. Fixed it without regret — the test was wrong.",
    "Spent an hour on a bug that turned out to be a stale cache. Not the first time.",
    "Re-read my own PR from yesterday. Disliked three comments I'd left. Edited them.",
    "Theo sent designs for the Before/After panel. They're right; my layout was overcomplicated.",
    "Wrote a test that failed for the right reason. Rare enough to note.",
    "Rolled back the {tool} change. The perf gain wasn't worth the flakiness.",
    "Sofia flagged a race in the sidecar. She was right — reproduced on the third try.",
    "Pushed the fix. Ran {tool} twice to be sure.",
    "Refactored {pkg}. Feels lighter now, not necessarily faster.",
]
LIFE_FRAGMENTS = [
    "Walked to {place} after lunch. Got a coffee at {cafe}. Thought about nothing.",
    "Ran into {friend} at {place}. First time in months. Agreed to dinner next week; we'll see.",
    "Reading the Ursula Le Guin essays again. The one on anger still lands.",
    "Made pasta. Ate pasta. Read. Slept.",
    "Hiked {place} on Saturday. Wind hard enough to lean into.",
    "Mum called. She is fine. Father is fine. The dog is fine.",
    "Tried the new bakery on {place}. The pastel was underbaked.",
    "Watched the light on the Tejo from the office window. Forgot to work for ten minutes.",
]
REFLECTIONS = [
    "Shipping fast only feels good if the rollback is also fast. That's all.",
    "Most of my bad code is written while trying to prove I was right earlier.",
    "A test that was hard to write is a test I trust.",
    "The privacy argument for on-device compute isn't about threats. It's about what kinds of products get to exist.",
    "Good review is mostly reading slowly. The rest is taste.",
    "Half of \"rewriting\" is deleting.",
    "When I can't explain the bug in a sentence I haven't understood it yet.",
]
EMAIL_SUBJECTS_WORK = [
    "Re: rollout plan for the sidecar v2",
    "Benchmark results — last 3 nights",
    "On the GPU budget ask",
    "Follow-up from Tuesday's review",
    "Draft: PR etiquette memo",
    "Thanks for the debug session",
    "Heads-up on the data-pipeline refactor",
    "Proposal: quiet hours for releases",
]
EMAIL_SUBJECTS_PERSONAL = [
    "Dinner this weekend?",
    "Belated happy birthday",
    "Re: the hike — route A",
    "Book recommendation (finally)",
    "Quick thanks",
    "Miss you all",
]
EMAIL_BODY_WORK = [
    "Hi {name},\n\nQuick update on the rollout. The staging numbers are clean — {n} runs, zero regressions. I'll cut the release branch Friday morning unless you push back. No rush on your end; I'd rather wait a day than ship on a Monday.\n\nAlso: the benchmark Priya flagged is a fixture issue, not a real slowdown. Fix lands in the same PR.\n\n— Alex",
    "Hey {name},\n\nRe: the GPU ask — I'm pulling the request. The workload's been cold for two weeks and I don't want to hold capacity for a \"maybe\". If the summer ramp changes things I'll refile.\n\nThanks for the candid review.\n\nAlex",
    "{name},\n\nNo disagreement on the timeline. Two asks:\n\n1. Let me own the migration script. I'd rather debug my own mistakes.\n2. Can we keep the old path behind a flag for one more release? I've been burned by \"we'll just move everyone at once\".\n\n— A.",
    "Hi {name},\n\nShort note. The review comment I left on line {line} was unkind — I reread it this morning and it wasn't how I wanted to say it. Sorry about that. The technical point stands but the tone doesn't.\n\nHappy to redo it in a call if easier.\n\nAlex",
]
EMAIL_BODY_PERSONAL = [
    "Hi {name},\n\nAre you free Saturday? Thinking {place}, leave around 9, back by evening. No big plans otherwise — happy to bail if you're tired.\n\nLet me know.\n\nA.",
    "{name} —\n\nFinally finished \"{book}\". You were right. The middle drags but the last fifty pages are worth it. Dinner soon; my turn to cook.\n\nMiss you.\n\nAlex",
    "Hey {name},\n\nBelated happy birthday — I remembered on the day and then did nothing about it, which is the modern definition of intention. Coffee at {cafe} next week?\n\nA.",
]
BOOKS = ["Solaris", "A Wizard of Earthsea", "Stoner", "The Dispossessed", "Ficciones"]

NOTE_TITLES = [
    "on reproducibility",
    "a thing Priya said",
    "why [[determinism]] is not the point",
    "[[review]] — what I actually do",
    "the Friday-afternoon heuristic",
    "[[sidecar]] notes — what surprised me",
    "dataset vs model, one more time",
    "small kindnesses in code review",
    "on taking the rollback seriously",
    "what I got wrong about [[lora]]",
]
NOTE_BODIES = [
    "The point of reproducibility isn't replaying exactly the same thing. It's that when a run is off, you can tell whether the input or the process drifted. Most teams I've worked with confuse this. They store the code and forget the data, or vice versa. The asymmetry between the two is what tells you where to look.",
    "Priya said something in review yesterday that's still rattling around. \"If you can't write the test first, you don't know what the feature is yet.\" I don't know if I fully agree — sometimes the feature is obvious and the test is the annoying part — but I can't find a good counter-example. Sit with it.",
    "Determinism is not the goal. Debuggability is the goal; determinism is the cheapest route there most of the time. When it isn't — when the throughput cost is extreme — better telemetry is a valid substitute. Not something to say out loud to purists, but true.",
    "What I actually do in review: read the diff twice. First for shape, second for detail. If I have strong feelings on the first read, I wait an hour before typing. Half of them don't survive the hour. The half that do are worth the friction.",
    "If I find myself deploying on a Friday afternoon, I've already mismanaged the week. It's fine to skip the release and do it Monday; the PM worry about one lost day is cheaper than the one weekend paged awake.",
]
CODE_PY_HEADERS = [
    '"""Small helper. Keep it small."""',
    '"""Wrap the mlx_lm lora CLI so we can unit-test without a model."""',
    '"""TODO(alex): this was cute on day one; now it mostly gets in the way. Delete once the sidecar owns the pipe."""',
    '"""Do not move this module. The import path is load-bearing in two places."""',
]
CODE_PY_BODIES = [
    "def dedup(chunks):\n    # exact first, MinHash second. Order matters: exact is cheap.\n    seen = set()\n    out = []\n    for c in chunks:\n        h = hash(c.text)\n        if h in seen:\n            continue\n        seen.add(h)\n        out.append(c)\n    return out\n",
    "def _retry(fn, *, attempts=3):\n    # exponential backoff because the sidecar spawn race\n    # eats the first request roughly 1 in 20.\n    for i in range(attempts):\n        try:\n            return fn()\n        except ConnectionResetError:\n            if i == attempts - 1:\n                raise\n    return None\n",
    "def write_atomic(path, payload):\n    # write-temp + rename beats truncation. Learned the hard way.\n    tmp = path.with_suffix(path.suffix + '.tmp')\n    tmp.write_bytes(payload)\n    tmp.replace(path)\n",
]
CODE_TS_BODIES = [
    "// quick helper. no framework — keep it copy-pasteable.\nexport function clamp01(x: number): number {\n  if (x < 0) return 0;\n  if (x > 1) return 1;\n  return x;\n}\n",
    "// TODO(alex): move to the shared package once the design stabilizes.\n// (This has been 'TODO' for six weeks; it is a lie to call it a TODO.)\nexport const BYTES_IN_MB = 1024 * 1024;\n",
]

IMESSAGE_TURNS = [
    ("me", "still at the office — sofia broke the sidecar test suite and I am helping"),
    ("Duarte", "lol"),
    ("Duarte", "how long"),
    ("me", "20 min. dinner?"),
    ("Duarte", "yes — usual place"),
    ("me", "ok"),
    ("Inês", "did you see the thing priya pushed"),
    ("me", "about cuda graphs? yes"),
    ("Inês", "thoughts?"),
    ("me", "smart, a bit brave"),
    ("me", "I'd wait a week before shipping"),
    ("Inês", "yeah fair"),
    ("me", "coffee tmrw?"),
    ("Inês", "copenhagen 9?"),
    ("me", "done"),
    ("me", "book finished btw. you were right"),
    ("Inês", "told you"),
    ("me", "the middle did drag"),
    ("Inês", "worth it"),
    ("me", "agreed"),
]

SLACK_TURNS = [
    ("alex", "#eng", "heads up — pushing the sidecar fix. one test is quarantined, will unflag after monitor settles"),
    ("priya", "#eng", "cool. owned?"),
    ("alex", "#eng", "me for 24h"),
    ("priya", "#eng", "👍"),
    ("alex", "#eng", "benchmark numbers from last night in the thread. tl;dr: noise."),
    ("theo", "#design", "alex you around? want your eyes on the before/after spacing"),
    ("alex", "#design", "give me 10"),
    ("alex", "#design", "back"),
    ("theo", "#design", "ok — option A vs option B"),
    ("alex", "#design", "A. tighter gutter."),
    ("theo", "#design", "why"),
    ("alex", "#design", "the demo lives or dies on the eye going straight to the diff"),
    ("theo", "#design", "sold"),
    ("alex", "#random", "anyone want half a loaf of bread — overshot at the bakery"),
    ("sofia", "#random", "yes"),
    ("alex", "#random", "it's by my desk"),
    ("alex", "#eng", "rollout status: green across staging for 3h, promoting"),
    ("alex", "#eng", "if anyone sees the retry spike from last week come back, page me directly, not the rota"),
    ("noor", "#eng", "got it"),
    ("alex", "#eng", "thanks"),
]


# ---------------------------------------------------------------------------
# generator

class Writer:
    def __init__(self, rng: random.Random) -> None:
        self.rng = rng

    def pick(self, xs):
        return self.rng.choice(xs)

    def knobs(self):
        pairs = [(0.80, 0.85, 0.90), (0.82, 0.86, 0.92), (0.78, 0.83, 0.88)]
        lower, knob, upper = self.pick(pairs)
        return f"{knob}", f"{lower}", f"{upper}"

    def work_fragment(self):
        tpl = self.pick(WORK_FRAGMENTS)
        lower, knob, upper = self.knobs()
        return tpl.format(
            tool=self.pick(TOOLS), pkg=self.pick(PKGS),
            knob=knob, lower=lower, upper=upper,
        )

    def life_fragment(self):
        tpl = self.pick(LIFE_FRAGMENTS)
        return tpl.format(
            place=self.pick(PLACES),
            cafe=self.pick(CAFES),
            friend=self.pick(NAMES_FRIEND),
        )

    def journal_entry(self, day: dt.date) -> str:
        chunks = [f"# {day.isoformat()} — {day.strftime('%A')}", ""]
        chunks.append(self.pick(MORNING_OPENINGS))
        # 2-4 work fragments per entry
        n_work = self.rng.randint(2, 4)
        for _ in range(n_work):
            chunks.append("")
            chunks.append(self.work_fragment())
        # 1-3 life fragments per entry
        n_life = self.rng.randint(1, 3)
        for _ in range(n_life):
            chunks.append("")
            chunks.append(self.life_fragment())
        # almost always one reflection at the end
        if self.rng.random() < 0.75:
            chunks.append("")
            chunks.append(self.pick(REFLECTIONS))
        # sometimes a second reflection
        if self.rng.random() < 0.3:
            chunks.append("")
            chunks.append(self.pick(REFLECTIONS))
        chunks.append("")
        return "\n".join(chunks)

    def email(self, work: bool) -> str:
        if work:
            subject = self.pick(EMAIL_SUBJECTS_WORK)
            body_tpl = self.pick(EMAIL_BODY_WORK)
            body = body_tpl.format(
                name=self.pick(NAMES_TEAM),
                n=self.rng.randint(12, 240),
                line=self.rng.randint(4, 300),
            )
        else:
            subject = self.pick(EMAIL_SUBJECTS_PERSONAL)
            body_tpl = self.pick(EMAIL_BODY_PERSONAL)
            body = body_tpl.format(
                name=self.pick(NAMES_FRIEND),
                place=self.pick(PLACES),
                cafe=self.pick(CAFES),
                book=self.pick(BOOKS),
            )
        return f"Subject: {subject}\nFrom: Alex Rivers <alex@example.com>\n\n{body}\n"

    def note(self, title: str) -> str:
        # each note is 2-4 paragraphs of thinking plus 1-2 reflections
        paras = [self.pick(NOTE_BODIES)]
        n_extra = self.rng.randint(1, 3)
        for _ in range(n_extra):
            paras.append(self.pick(NOTE_BODIES))
        for _ in range(self.rng.randint(1, 2)):
            paras.append(self.pick(REFLECTIONS))
        return f"# {title}\n\n" + "\n\n".join(paras) + "\n"

    def code_py(self, filename: str) -> str:
        return "\n".join([self.pick(CODE_PY_HEADERS), "", self.pick(CODE_PY_BODIES)])

    def code_ts(self, filename: str) -> str:
        return self.pick(CODE_TS_BODIES)


def generate(out: pathlib.Path, seed: int, size_cap_bytes: int = 10 * 1024 * 1024) -> dict:
    rng = random.Random(seed)
    w = Writer(rng)
    stats = {"files": 0, "bytes": 0, "sentences": 0}

    def write(path: pathlib.Path, payload: str) -> None:
        nonlocal stats
        path.parent.mkdir(parents=True, exist_ok=True)
        data = payload.encode("utf-8")
        if stats["bytes"] + len(data) > size_cap_bytes:
            sys.exit(f"size cap {size_cap_bytes} bytes exceeded at {path}")
        path.write_bytes(data)
        stats["files"] += 1
        stats["bytes"] += len(data)
        stats["sentences"] += payload.count(". ") + payload.count("? ") + payload.count("! ") + 1

    # journal — one file per ~2 days covering ~6 months
    start = dt.date(2025, 11, 1)
    for i in range(90):
        day = start + dt.timedelta(days=i * 2)
        write(out / "journal" / f"{day.isoformat()}.md", w.journal_entry(day))

    # emails
    for i in range(28):
        write(out / "emails" / f"work-{i:02d}.md", w.email(work=True))
    for i in range(14):
        write(out / "emails" / f"personal-{i:02d}.md", w.email(work=False))

    # notes — every canonical title + extras
    for i, title in enumerate(NOTE_TITLES):
        slug = title.replace(' ', '-').replace('[[','').replace(']]','')
        write(out / "notes" / f"{i:02d}-{slug}.md", w.note(title))
    for i in range(50):
        title = rng.choice(NOTE_TITLES)
        write(out / "notes" / f"extra-{i:02d}.md", w.note(title))

    # code samples
    for i in range(18):
        write(out / "code_comments" / f"helper_{i:02d}.py", w.code_py(f"helper_{i:02d}.py"))
    for i in range(10):
        write(out / "code_comments" / f"util_{i:02d}.ts", w.code_ts(f"util_{i:02d}.ts"))

    # iMessage-style JSON, expanded by rolling the canned turns 60×
    im = []
    t = dt.datetime(2026, 2, 1, 8, 0, 0)
    for rep in range(60):
        for speaker, text in IMESSAGE_TURNS:
            t = t + dt.timedelta(minutes=rng.randint(1, 45))
            im.append({
                "timestamp": t.isoformat() + "Z",
                "from": speaker,
                "text": text,
            })
    write(out / "chat" / "imessage.json", json.dumps(im, indent=2, ensure_ascii=False))

    # Slack-style JSON
    sl = []
    t = dt.datetime(2026, 2, 1, 9, 0, 0)
    for rep in range(50):
        for user, channel, text in SLACK_TURNS:
            t = t + dt.timedelta(minutes=rng.randint(1, 30))
            sl.append({
                "ts": t.isoformat() + "Z",
                "user": user,
                "channel": channel,
                "text": text,
            })
    write(out / "chat" / "slack.json", json.dumps(sl, indent=2, ensure_ascii=False))

    return stats


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="tests/fixtures/demo_corpus")
    ap.add_argument("--seed", type=int, default=20260424)
    ap.add_argument("--size-cap", type=int, default=10 * 1024 * 1024)
    args = ap.parse_args()

    out = pathlib.Path(args.out).resolve()
    if out.exists():
        # wipe prior generated files but keep PERSONA.md
        for item in out.rglob("*"):
            if item.is_file() and item.name != "PERSONA.md":
                item.unlink()
        for item in sorted(out.rglob("*"), reverse=True):
            if item.is_dir() and not any(item.iterdir()):
                item.rmdir()

    stats = generate(out, args.seed, args.size_cap)
    print(
        f"wrote {stats['files']} files "
        f"({stats['bytes'] / 1024:.1f} KiB, "
        f"~{stats['sentences']} sentences) to {out}"
    )


if __name__ == "__main__":
    main()
