#!/usr/bin/env python3
"""Build the style-extractor input JSONL for the Style Extractor Orchestrator.

Target: 1500 unique style-diverse chunks, each 200-2000 chars, covering the
six style axes the extractor profiles (formality / verbosity / warmth /
hedging / humor / directness).

Composition (deterministic, seeded):
  ~80   literary/voice-bearing paragraphs (LITERARY from build_pilot_input)
  ~700  parametric templates across 6 style categories × ~12 tmpl × ~10 fills
  ~400  ambiguous-seed concatenations (casual/warm register, paired)
  ~200  sliding-window chunks from the real sample_corpus
  ~120  hand-written extension paragraphs covering edge style combos

Output:
  managed-agents/style-extractor/inputs/full-1500.jsonl
  one row per line: {"request_id": <16-char hex>, "text": <string 200..2000 chars>}

The input file size is bounded (each row ≤2000 chars) so upload stays well
under the Files API limit.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import random
import re
import sys

# Reuse the voice-bearing literary paragraphs and chat-like fragments from
# the quality-pilot builder so we don't duplicate 200+ lines of literal text.
from build_pilot_input import LITERARY, AMBIGUOUS_SEEDS  # noqa: E402

REPO = pathlib.Path(__file__).resolve().parents[2]
CORPUS = REPO / "tests" / "fixtures" / "sample_corpus"
SEED = 17
TARGET = 1500
MIN_CHARS = 200
MAX_CHARS = 2000


# ----- Parametric style templates (12 templates × 6 categories ≈ 72 templates)

# FORMAL / ACADEMIC / BUSINESS — high formality, low humor, moderate verbosity.
FORMAL_TEMPLATES: list[str] = [
    "The {noun} framework presented in this {doc} establishes a rigorous "
    "foundation for evaluating {subject} under conditions of {constraint}. "
    "Preliminary findings indicate that {metric} improves by approximately "
    "{num}% when {method} is applied in accordance with the stated protocol.",

    "We hereby acknowledge receipt of your correspondence dated {date} "
    "regarding {subject}. Pursuant to Section {num}.{num2} of the {doc}, the "
    "matter has been referred to the appropriate review committee and will "
    "be addressed within the statutory {num2}-business-day window.",

    "The undersigned respectfully submits that the position articulated by "
    "the opposing party fails to account for the well-established principle "
    "that {subject} must be evaluated in light of {constraint} rather than "
    "the narrower {method} proposed in paragraph {num} of the {doc}.",

    "This {doc} sets forth the terms and conditions governing the use of the "
    "{noun} by {role}s. By accessing or utilizing the {noun}, {role}s agree "
    "to be bound by the provisions herein and acknowledge that violations "
    "may result in immediate termination of {subject} privileges.",

    "The Board of Directors convened on {date} to deliberate on the proposed "
    "{method}. After extensive discussion and review of the supporting {doc}, "
    "the Board resolved, by a vote of {num} in favor and {num2} opposed, to "
    "approve the measure subject to standard regulatory review.",

    "In accordance with our {doc}, this communication serves as formal "
    "notification that {subject} has been scheduled for {date}. Affected "
    "{role}s should ensure that all outstanding {noun} items are resolved "
    "prior to the effective date to avoid service interruption.",

    "Empirical analysis of the {noun} dataset reveals statistically significant "
    "deviations (p < 0.0{num2}) from the hypothesized distribution. These "
    "findings corroborate the theoretical model advanced by {role} et al. "
    "and warrant further investigation under controlled conditions.",

    "The {role} is hereby advised that the {method} procedure outlined in "
    "the preceding {doc} shall take effect on {date}. Compliance with the "
    "revised protocol is mandatory; failure to adhere may result in "
    "administrative action consistent with established {noun} policy.",

    "Our quarterly review of {subject} performance indicates that the {metric} "
    "target was exceeded by {num}%, driven primarily by gains in {noun} "
    "efficiency. We attribute this outcome to the disciplined execution of "
    "the strategic {method} ratified by the Board in Q{num2}.",

    "The Committee, having duly considered the representations submitted by "
    "the {role} on {date}, finds that the evidence does not support the "
    "claim that {subject} contravenes the provisions of the governing {doc}. "
    "The complaint is therefore dismissed without prejudice.",

    "Effective {date}, all {role}s are required to complete the {method} "
    "certification prior to accessing the {noun} system. Training modules "
    "are available in the corporate learning portal; questions may be "
    "directed to the Office of {subject} Assurance.",

    "Pursuant to the terms of the {doc} dated {date}, the parties agree to "
    "mediate any dispute arising from the interpretation of {subject} prior "
    "to initiating formal proceedings. Mediation shall be conducted in "
    "accordance with the rules of the {noun} Arbitration Association.",
]

# CASUAL / CHAT / INFORMAL — low formality, variable everything else, high warmth.
CASUAL_TEMPLATES: list[str] = [
    "ok so hear me out — what if we just {verb} the {thing} and see what "
    "happens? like worst case it breaks and we roll it back in five minutes. "
    "best case we learn something. I'm honestly tired of overthinking this "
    "one and I think {role} would agree if we framed it right.",

    "honestly? the {thing} thing turned out way better than I expected. "
    "{role} was skeptical at first but after the {event} I think they're "
    "coming around. gonna send a quick update to the group later tonight "
    "once I've had a minute to actually process what happened.",

    "lol yeah that's exactly what I meant. sorry the message came out weird "
    "earlier — I was typing from the car and autocorrect got me again. "
    "anyway, let's just {verb} it tomorrow morning and move on. no need to "
    "make a whole thing out of it.",

    "so get this — {role} walks in at like {num}am, sees the {thing}, and "
    "just laughs. doesn't even say hi. drops their bag and starts {verb}ing "
    "like nothing's weird. I about died. we talked about it later and apparently "
    "they'd had the worst morning and the {thing} was the last straw.",

    "I dunno man, I've been going back and forth on the {thing} all week. "
    "part of me thinks we should just {verb} and see what sticks. the other "
    "part thinks {role} had a point about waiting till after the {event}. "
    "gonna sleep on it one more night and decide in the morning.",

    "quick one before I forget — did we ever hear back from {role} about "
    "the {thing}? I pinged them on Tuesday and got radio silence. not a "
    "blocker but I don't want it to fall through the cracks like the {event} "
    "situation did last month. that was painful.",

    "soooo funny story. I was about to {verb} the {thing} when {role} texted "
    "me saying they'd already done it. we almost collided on the same commit. "
    "good thing we caught it — imagine the merge conflict. anyway, all "
    "sorted now, crisis averted.",

    "ngl I've been procrastinating on the {thing} for like three weeks now. "
    "every time I open the doc my brain just goes 'nope.' maybe I need to "
    "just {verb} a first draft and let {role} tear it apart. at least then "
    "there'd be something to react to instead of a blank page.",

    "hey — hope you're hanging in there. heard about the {event} from "
    "{role} and just wanted to check in. no pressure to respond, I know "
    "your plate is full. just know I'm around if you want to {verb} it out "
    "or grab a coffee or whatever.",

    "wait wait wait — you're telling me {role} actually {verb}ed the {thing}? "
    "after all that debate in the standup? I need to hear the full story. "
    "buying you a drink Friday. you tell me what happened and I'll fill you "
    "in on the {event} thing from Wednesday.",

    "feeling kinda off today. didn't sleep well, brain's foggy. gonna take "
    "it easy on the {thing} stuff and pick back up tomorrow when I can "
    "actually think straight. don't {verb} anything load-bearing without me "
    "— I won't catch it if something's off.",

    "honest question — are we still doing the {thing}? cause {role} keeps "
    "referencing the {event} plan like it's happening and I genuinely don't "
    "know what the status is anymore. can someone just {verb} a yes-or-no "
    "in the thread so the rest of us can get on the same page?",
]

# TECHNICAL / DOCS — dense, precise, medium formality, low warmth, zero humor.
TECHNICAL_TEMPLATES: list[str] = [
    "The {component} module exposes a single entry point, `{func}()`, which "
    "accepts a {type} parameter and returns a {type2}. Internally it delegates "
    "to the {component}Manager singleton, which maintains a thread-safe queue "
    "of pending operations. Callers must hold the global {component} lock "
    "before invoking `{func}()` to avoid race conditions during flush.",

    "Configuration keys are read from `~/.{component}/config.toml` at startup. "
    "The loader resolves defaults in the following precedence: environment "
    "variables (prefix `{ENV}_`), then the TOML file, then hard-coded fallbacks. "
    "Invalid types are logged at WARN level and the default value is substituted; "
    "no exception is raised from the loader itself.",

    "Performance benchmarks measured on {hw} show a p50 latency of {num}ms "
    "and a p99 of {num2}ms for the `{func}` operation under a sustained load "
    "of {num}req/s. Memory consumption remains bounded at approximately "
    "{num2}MB regardless of queue depth, owing to the streaming parser used "
    "in the {component} pipeline.",

    "To extend the {component} subsystem, implement the `{type}` protocol and "
    "register your class via the `register_{component}()` decorator. The "
    "runtime discovers plugins at startup by scanning the `~/.{component}/plugins/` "
    "directory and invoking each module's `bootstrap()` entry. Plugins that "
    "fail to bootstrap are logged and skipped; they do not abort startup.",

    "The database schema for {component} consists of {num} tables related "
    "through foreign keys on `{type}_id`. Migrations are managed via "
    "Alembic and are numbered sequentially; rollback to any prior revision "
    "is supported except across the {num2}→{num} boundary, which introduced "
    "a non-reversible NOT NULL constraint on the `{func}` column.",

    "Error codes returned by the `{func}` endpoint conform to RFC {num}. "
    "The `code` field is a stable enum; the `message` field is human-readable "
    "and may change between releases. Clients should branch on `code` only. "
    "Rate limiting returns `429 Too Many Requests` with a `Retry-After` "
    "header indicating the recommended back-off interval in seconds.",

    "Concurrency within the {component} layer is managed by an `asyncio` "
    "event loop with a bounded executor pool of {num} worker threads. CPU-"
    "bound operations (notably {func}) are offloaded to the thread pool via "
    "`loop.run_in_executor()`. Long-running I/O uses native `async` primitives "
    "and does not occupy worker slots.",

    "The {component} wire protocol uses length-prefixed MessagePack frames "
    "over a plain TCP connection. Frame sizes are capped at {num2}MB; larger "
    "payloads must be chunked by the client. Connection heartbeats are "
    "exchanged every {num} seconds; three consecutive missed heartbeats "
    "trigger a reconnect with exponential back-off.",

    "Deployment of the {component} service follows a rolling-update strategy "
    "with a `{num}`-instance minimum during rollout. Health checks probe the "
    "`/healthz` endpoint every {num2} seconds; instances failing three "
    "consecutive checks are removed from the load balancer and restarted. "
    "Rollback is automatic if the {func} error rate exceeds {num}%.",

    "Memory profiling of the {component} workload revealed a slow leak in "
    "the {func} path, traced to a circular reference between the cache entry "
    "and its weak-ref callback. The fix, landed in v{num}.{num2}, replaces "
    "the callback with a bound method on the cache itself, breaking the cycle "
    "and allowing standard garbage collection to reclaim the entries.",

    "Logging in the {component} subsystem uses the structured JSON format "
    "defined in `{ENV}_LOG_SCHEMA.md`. Each log entry includes a `trace_id` "
    "propagated via the `X-Trace-ID` header; downstream services include the "
    "same `trace_id` in their own logs, enabling end-to-end request tracing "
    "across the {num}-service pipeline.",

    "Unit tests for {component} are organized by module; integration tests "
    "live under `tests/integration/` and require a local {func} fixture "
    "(provisioned by `make test-env`). End-to-end tests use a recorded "
    "VCR cassette and do not require network access. The full suite runs "
    "in under {num2}s on the reference {hw} hardware.",
]

# POETIC / DESCRIPTIVE — low directness, medium-high verbosity, high warmth.
POETIC_TEMPLATES: list[str] = [
    "The {place} at {time} was a different creature than the {place} at noon. "
    "It wore the hour lightly — the {thing} hanging in the windows, the "
    "{other} uncertain in the corners. Nothing had changed, and yet everything "
    "had shifted the way a familiar word shifts when you repeat it too many "
    "times and hear it fresh.",

    "She carried the {thing} the way some people carry a name: casually, "
    "without looking down at it, as if the weight were part of the posture "
    "and not the cargo. The {place} opened around her. The {other} waited. "
    "Nothing needed to be said, so for a while nothing was.",

    "There was a particular quality to the light that {time}, the kind that "
    "makes the ordinary {thing} look ceremonial. I watched it for longer than "
    "I would later admit, watching the way it caught the {other} and turned "
    "it into something I almost recognized from a dream I couldn't quite "
    "remember.",

    "He had spent so many years in the {place} that he no longer saw it, the "
    "way a fish, they say, does not see the water. Only when the {thing} "
    "broke — only when the {other} rearranged itself overnight — did the "
    "whole of it flicker back into his attention like a half-finished "
    "sentence.",

    "The {thing} arrived the way most important things arrive: quietly, "
    "without announcement, tucked inside the {other} of an ordinary {time}. "
    "I almost missed it. I think most of the small, load-bearing moments of "
    "a life work this way — they refuse to announce themselves, and you have "
    "to be paying a particular kind of attention to catch them at all.",

    "By the time the {thing} reached the {place}, it had been rewritten so "
    "many times that only the grammar was still its own. The meaning had been "
    "worn smooth by {other} hands, by well-meaning revisions, by the ordinary "
    "erosion of {time}. What remained was a shape — beautiful, functional, "
    "and almost entirely unoriginal.",

    "The {other} of the {place} was not silent but quiet, which is a "
    "different thing. Silence is an absence; quiet is a texture. You could "
    "hear the {thing} if you listened — the hum of it, the slow breathing, "
    "the occasional settling. It was the kind of quiet that made you aware "
    "of your own pulse.",

    "Years later, what I remembered most about the {time} at {place} was not "
    "the {thing} itself but the {other} — the way the air held itself, the "
    "way nobody quite knew where to put their hands. The {thing} had been "
    "the event. The quiet around it was the memory.",

    "The {place} kept its own time. The {thing} outside — the rush of it, "
    "the weather of it — stopped at the threshold, and inside the clocks "
    "moved at the speed of whoever was most at ease. I've been in few other "
    "rooms like it. The {other} was almost unrecognizable as {time}.",

    "She said the word the way you'd hand someone a small {thing} — briefly, "
    "with both hands, as though she were not quite sure it would hold its "
    "shape on the way across. The {place} absorbed it. The {other} did not "
    "quite settle for the rest of the {time}.",

    "It is an old {place}, and it carries its age without apology. The "
    "{thing} that built it are mostly gone; the {other} that might one day "
    "replace it is not yet arrived. What remains is a weathered, patient "
    "structure, leaning slightly into the prevailing weather of {time}.",

    "The {thing} turned slowly, the way {other} turns — not as a change of "
    "direction but as an acknowledgment that direction was always less "
    "fixed than we'd pretended. {time} has a way of doing that, of softening "
    "the hard corners of things, of making the {place} around you feel less "
    "like a stage and more like a weather system.",
]

# JOURNALISTIC — medium formality, high directness, low hedging.
JOURNALISTIC_TEMPLATES: list[str] = [
    "{city}, {date} — {role} officials confirmed Tuesday that the {thing} "
    "program will be discontinued by the end of the fiscal year, citing "
    "declining participation and a {num}% year-over-year drop in {metric}. "
    "The decision affects approximately {num2} {role}s across the region "
    "and is expected to save the department roughly ${num} million annually.",

    "The {org} announced Wednesday that its {role}, {name}, will step down "
    "effective {date}, ending a {num}-year tenure marked by both expansion "
    "and controversy. In a statement, the board praised {name}'s leadership "
    "while acknowledging the need for new strategic direction as the "
    "organization enters its next phase of growth.",

    "New data released by the {org} shows {metric} rising by {num}% in the "
    "last quarter — the steepest increase since {date}. Analysts attribute "
    "the gain to improving conditions in the {industry} sector, though some "
    "caution that underlying {thing} indicators remain weak and may limit "
    "the durability of the trend.",

    "{name}, a {role} with {num} years of experience, told reporters Thursday "
    "that the current {thing} policy 'does not match the reality on the "
    "ground' and urged the {org} to revisit the framework before the {date} "
    "review deadline. The statement marks the first public dissent from "
    "within the department.",

    "The {city} Council voted {num}-{num2} Tuesday to approve a revised "
    "{thing} ordinance, overriding a mayoral veto issued earlier this month. "
    "Supporters say the measure will strengthen {metric} protections; "
    "opponents argue the rules will disproportionately burden small {role}s "
    "without delivering the promised benefits.",

    "A months-long investigation by this {org} has found that the {thing} "
    "program, despite its ${num} million budget, has served fewer than "
    "{num2}% of its target population. Records obtained under public-records "
    "law show that administrative overhead consumed more than a third of "
    "allocated funds during the review period.",

    "In a closely watched decision, the {org} ruled Monday that the {thing} "
    "practice at the center of the {name} case does not violate existing "
    "regulations, though the panel urged the legislature to clarify the "
    "underlying statute. The ruling is expected to shape {industry} policy "
    "for at least the next {num} years.",

    "{name}, the {role} appointed to lead the {org}'s {thing} review, said "
    "in an interview Friday that the initial findings will be released "
    "publicly no later than {date}. {name} declined to preview specific "
    "recommendations but confirmed that the review will examine both "
    "structural and personnel issues within the {industry}.",

    "Data from the {org}'s latest survey, conducted between {date} and the "
    "end of Q{num}, indicate that public support for the {thing} initiative "
    "has fallen to {num2}%, down from a high of {num}% two years ago. The "
    "decline was sharpest among {role}s under the age of {num}, a demographic "
    "the program was specifically designed to reach.",

    "After years of delays, the {city} {thing} project broke ground Wednesday "
    "with an estimated completion date of {date}. The ${num} million "
    "undertaking — one of the largest public works efforts in the region's "
    "history — is projected to create approximately {num2} {role} positions "
    "during its construction phase.",

    "The {org}'s report, released this morning, concludes that the {thing} "
    "system is 'structurally under-resourced' and recommends a {num}% "
    "funding increase over the next five years. Implementation, the report "
    "notes, will require legislative action that is not currently on the "
    "{date} calendar.",

    "{name}, a {role} at the {org}, said Thursday that the new {thing} "
    "guidelines 'represent a meaningful step forward' but stopped short of "
    "endorsing the full package. Critics within the {industry} have argued "
    "that the rules lack enforcement teeth and may be revised before the "
    "{date} effective date.",
]

# REFLECTIVE / DIARY / ESSAY — personal, hedged, warm, low directness.
REFLECTIVE_TEMPLATES: list[str] = [
    "I've been thinking about the {thing} more than I should. Not in any "
    "particular direction — just thinking, the way you think about a thing "
    "when you haven't yet decided what to feel about it. The {role} said "
    "something last week that I keep coming back to. Maybe they're right. "
    "Maybe I'll know by {time}.",

    "Today I was reminded, in a small and ordinary way, of why I started "
    "doing the {thing} in the first place. Not reminded exactly — that's "
    "too dramatic. Nudged. The {role} asked a question, and in trying to "
    "answer it I caught sight of something I hadn't noticed I'd lost. It "
    "was a good {time}.",

    "Some days I feel as though I'm doing the {thing} right. Other days I "
    "feel as though I'm doing a careful imitation of someone who is doing "
    "the {thing} right, and I'm not sure the imitation is close enough to "
    "fool anyone who's paying attention. Today was mostly the second kind, "
    "though {time} was better than the rest.",

    "Not sure why this one is sticking. The {role} didn't say anything I "
    "hadn't heard before. The {thing} wasn't new. But something about the "
    "combination — the quiet, the {time}, the way the whole afternoon slowed "
    "down — made the ordinary observation feel like it had been said for "
    "the first time.",

    "I read somewhere that the {thing} is mostly a practice of paying "
    "attention. I don't know if that's true but it sounds right. What I can "
    "say, at least from where I'm sitting at the end of this particular "
    "{time}, is that the days I feel most alive are the days I pay the most "
    "attention. The rest are just errands.",

    "Late-{time} thoughts, unreliable: maybe the {role} is not the problem. "
    "Maybe the {thing} is not the problem. Maybe I've been carrying an "
    "assumption into every conversation that keeps bending the evidence to "
    "fit. I'll think about it tomorrow, when I'm rested and less inclined "
    "to believe my own rhetoric.",

    "The {thing} is going better than I expected and worse than I'd hoped, "
    "which I suppose is the ordinary condition of most {thing}s. I keep "
    "wanting a clean outcome and forgetting that clean outcomes belong to "
    "other people's lives, or to the edited versions of my own. {time} "
    "tends to dissolve both.",

    "Something I want to remember about this {time}: the {role} called for "
    "no reason and stayed on the phone for forty minutes. We didn't solve "
    "anything. We didn't try to. The call itself was the point, and by the "
    "end of it the {thing} that had felt unbearable in the morning was just "
    "one of several ordinary weights.",

    "Been pretending the {thing} doesn't bother me for about three weeks now "
    "and it's caught up to me tonight. I don't want to write about it at "
    "length — there's nothing to say that I haven't already said to myself "
    "in the shower — but I want to note, for the record of this {time}, "
    "that I'm tired of pretending.",

    "Small grace of the {time}: the {role} remembered the thing I said in "
    "passing last month and brought it back up today, which I would not "
    "have bet money on. Being remembered in a small way, at the right "
    "moment, turns out to be more durable than being remembered in a large "
    "way at the wrong one.",

    "I had a whole theory about the {thing} and then I spent twenty minutes "
    "actually thinking about it instead of just believing it, and the "
    "theory fell apart in an embarrassingly clean way. Good, probably. A "
    "theory that survives twenty {time}s of attention is better than one "
    "that doesn't, even if the process is unflattering.",

    "Rereading something I wrote a year ago. The me of then was both more "
    "certain and more anxious than the me of now — which is interesting, "
    "because I'd have predicted the opposite. Maybe the {thing} you're "
    "most certain about is always the {thing} you haven't yet been forced "
    "to hold for long enough. {time} has a way of rebalancing the ratio.",
]


STYLE_CATEGORIES: dict[str, list[str]] = {
    "formal": FORMAL_TEMPLATES,
    "casual": CASUAL_TEMPLATES,
    "technical": TECHNICAL_TEMPLATES,
    "poetic": POETIC_TEMPLATES,
    "journalistic": JOURNALISTIC_TEMPLATES,
    "reflective": REFLECTIVE_TEMPLATES,
}


# Fill pools — intentionally wide enough that the template × fill cross-product
# yields many distinct surface strings. Every placeholder below is referenced
# by at least one template in STYLE_CATEGORIES.
FILLS: dict[str, list[str]] = {
    "noun": ["system", "pipeline", "framework", "platform", "model", "agent", "workflow",
             "service", "registry", "index", "archive", "catalog"],
    "subject": ["compliance", "accessibility", "eligibility", "fairness", "quality",
                "throughput", "security", "liability", "coverage", "onboarding"],
    "constraint": ["bounded memory", "sub-second latency", "zero downtime",
                   "regulatory review", "limited funding", "distributed operation",
                   "human-in-the-loop review", "strict backward compatibility"],
    "metric": ["retention", "latency", "conversion", "accuracy", "coverage",
               "uptime", "throughput", "engagement", "adoption"],
    "method": ["protocol", "procedure", "policy", "framework", "process",
               "workflow", "methodology", "approach", "initiative", "program"],
    "doc": ["charter", "contract", "specification", "memorandum", "policy",
            "handbook", "agreement", "declaration", "report"],
    "date": ["March 14", "April 3", "May 1", "June 22", "July 5", "August 18",
             "September 9", "October 27", "November 3", "December 15",
             "Jan 20", "Feb 11"],
    "role": ["member", "partner", "officer", "director", "reviewer",
             "administrator", "employee", "participant", "candidate", "counselor"],
    "num": ["12", "24", "47", "58", "81", "92", "108", "134", "155", "178",
            "7", "3", "18", "36", "73"],
    "num2": ["5", "8", "14", "21", "33", "44", "57", "66", "79", "91",
             "2", "11", "27", "42", "63"],
    "verb": ["ship", "ditch", "rewrite", "refactor", "test", "deploy",
             "revisit", "kick off", "pause", "rethink", "untangle", "debug"],
    "thing": ["plan", "script", "dashboard", "report", "proposal", "email",
              "doc", "thread", "draft", "spec", "diff", "rollout"],
    "event": ["demo", "review", "standup", "retro", "launch", "offsite",
              "interview", "kickoff", "outage", "deploy"],
    "component": ["scheduler", "cache", "indexer", "router", "parser",
                  "dispatcher", "watcher", "collector", "ingester", "worker"],
    "func": ["flush", "commit", "reconcile", "rotate", "drain", "snapshot",
             "fetch", "enqueue", "dispatch", "validate"],
    "type": ["Record", "Buffer", "Cursor", "Handler", "Stream", "Reader",
             "Writer", "Context", "Transcript", "Channel"],
    "type2": ["Result", "Receipt", "Envelope", "Response", "Report", "Artifact",
              "Outcome", "Digest", "Snapshot"],
    "ENV": ["KILN", "APP", "SVC", "CORE", "NODE", "EDGE"],
    "hw": ["an M2 Pro MacBook", "a reference cloud instance", "an M1 Mini",
           "a stock Linux VM", "a 16-core workstation"],
    "place": ["room", "hallway", "kitchen", "office", "cabin", "workshop",
              "garden", "veranda", "station", "library"],
    "time": ["morning", "evening", "afternoon", "dusk", "dawn", "week",
             "hour", "season", "month", "day"],
    "other": ["light", "air", "silence", "weather", "shadow", "stillness",
              "noise", "conversation", "distance", "warmth"],
    "city": ["BOSTON", "AUSTIN", "PORTLAND", "MONTRÉAL", "BERLIN", "LISBON",
             "DUBLIN", "SEATTLE", "MADISON", "OAKLAND"],
    "org": ["department", "agency", "commission", "institute", "foundation",
            "council", "board", "committee", "panel"],
    "name": ["Reyes", "Patel", "Nakamura", "Okafor", "Moreno", "Lindqvist",
             "Harlow", "Bergeron", "Kowalski", "Santos"],
    "industry": ["education", "healthcare", "housing", "transit", "energy",
                 "agriculture", "banking", "publishing", "telecom"],
}


def sha_id(text: str) -> str:
    return hashlib.sha256(text.encode()).hexdigest()[:16]


def _fill_template(template: str, rnd: random.Random) -> str:
    out = template
    # Walk each placeholder; multiple occurrences of the same key get different draws.
    for key, choices in FILLS.items():
        placeholder = "{" + key + "}"
        while placeholder in out:
            out = out.replace(placeholder, rnd.choice(choices), 1)
    return out


def build_category_samples(
    category: str, templates: list[str], rnd: random.Random, fills_per_template: int
) -> list[str]:
    out: list[str] = []
    for tmpl in templates:
        # Use a fresh per-template rnd path so we get reproducibility while
        # still getting enough variety across fills.
        for _ in range(fills_per_template):
            rendered = _fill_template(tmpl, rnd)
            if MIN_CHARS <= len(rendered) <= MAX_CHARS:
                out.append(rendered)
    return out


def slice_corpus_windows() -> list[str]:
    """Concatenate the sample_corpus MD / email / code files and slide
    overlapping windows over the result. Used to ground the synthetic
    majority with a small amount of real prose.
    """
    buf: list[str] = []
    for f in sorted(CORPUS.glob("[0-9][0-9]-*.md")):
        buf.append(f.read_text(errors="ignore"))
    edge = CORPUS / "edge_cases"
    if edge.is_dir():
        for f in sorted(edge.glob("*.md")):
            buf.append(f.read_text(errors="ignore"))
    emails = CORPUS / "emails"
    if emails.is_dir():
        for f in sorted(emails.glob("*.eml")):
            buf.append(f.read_text(errors="ignore"))
        mbox = emails / "03-mailbox.mbox"
        if mbox.is_file():
            buf.append(mbox.read_text(errors="ignore"))
    blob = "\n\n".join(buf)
    # Clean up huge whitespace runs but keep paragraph structure.
    blob = re.sub(r"\n{3,}", "\n\n", blob)

    out: list[str] = []
    # Multiple window sizes with overlapping stride so we capture different
    # paragraph groupings.
    for win, stride in [(400, 200), (600, 300), (900, 400), (1200, 500), (1700, 700)]:
        for start in range(0, max(1, len(blob) - MIN_CHARS), stride):
            chunk = blob[start : start + win].strip()
            if MIN_CHARS <= len(chunk) <= MAX_CHARS:
                out.append(chunk)
    return out


def combine_ambiguous_seeds(rnd: random.Random) -> list[str]:
    """Pair up short conversational seeds into 200+ char casual paragraphs."""
    seeds = list(AMBIGUOUS_SEEDS)
    rnd.shuffle(seeds)
    out: list[str] = []
    i = 0
    while i < len(seeds):
        group_size = rnd.choice([2, 3, 3, 4])  # favor 3-fragment paragraphs
        group = seeds[i : i + group_size]
        paragraph = " ".join(group)
        if MIN_CHARS <= len(paragraph) <= MAX_CHARS:
            out.append(paragraph)
        i += group_size
    return out


def filter_literary() -> list[str]:
    """Literary entries from build_pilot_input that already fit the 200..2000 window."""
    return [t for t in LITERARY if MIN_CHARS <= len(t) <= MAX_CHARS]


def extend_literary_synthetic() -> list[str]:
    """~120 hand-written paragraphs spanning style-axis extremes not well-covered
    by the template categories (e.g. playful + terse, cold + direct, hedged +
    warm). Keep short: these are the seasoning, not the main course.
    """
    return [
        # Playful / humorous / warm
        "So I finally alphabetized the spice rack and my reward was discovering that I own four jars of cumin, purchased across what I can only describe as four separate cumin-related emergencies. I am, apparently, a person who buys cumin under duress.",
        "My dog has decided that 8:47 AM is now the appropriate time for breakfast. Not 8:30. Not 9:00. 8:47, precisely, as confirmed by three consecutive mornings of stare-based negotiation. I am losing this argument and I don't even remember signing up for it.",
        "I've been told my signature move in meetings is saying 'real quick' and then talking for seven minutes. I'd like to formally object to this characterization, real quick, in what will undoubtedly be a brief and focused response of no more than three paragraphs.",
        "Bought a productivity book. Spent two hours rearranging it next to the other productivity books. Felt productive. The books sit there, collectively, generating no productivity whatsoever, like a council of elders who have forgotten what they were elected to do.",
        "The barista called me 'boss' today in a way that felt deeply unearned. I've been boss of exactly one shared Google Doc in my life and even that was a lie — Kim was the real boss; I was just the one who opened it first.",
        # Cold / detached / direct
        "The report is incomplete. Sections three and seven are missing. Revised draft due Friday. No further extensions will be granted. Contact the editor with questions.",
        "Terminal output confirms the process exited with code 127. The binary is not on the PATH. Install it or adjust the PATH. There is no third option.",
        "Metrics indicate a 17% regression on the p99 latency benchmark. The commit range is known. Bisect and revert. Post-mortem within 72 hours.",
        "Your access has been revoked effective immediately. The reason will be communicated by HR. Do not contact your former team. Return the laptop by end of day.",
        "The building will be closed tomorrow for maintenance. Badge access disabled 6 AM to 6 PM. Work from home. Questions go to facilities, not to me.",
        # Hedged / warm / long
        "I guess what I'm trying to say, and I know this is the kind of thing that sounds obvious once you say it out loud, is that maybe the reason we keep having the same conversation about the roadmap is that we haven't actually agreed on what problem the roadmap is supposed to be solving. Or maybe we have and I've missed it, which is also entirely possible.",
        "It might be worth reconsidering — and I say this tentatively, because I know how much thought has already gone into the current plan — whether the timeline really needs to be quite as compressed as it is. A two-week slip might buy us a meaningfully better outcome, though I could be wrong about that and would happily defer to whoever has been closer to the execution details than I have.",
        "I don't want to overstate this, and I realize the data is still pretty preliminary, but there's a pattern in the error logs that feels like it might be pointing at something real. I've only skimmed maybe a week's worth so far, and honestly my pattern-recognition might be running ahead of the evidence, but if I'm right it'd explain a couple of other oddities we've been chalking up to noise.",
        "Maybe I'm misreading the room here, but I got the sense that the decision wasn't quite as settled as the standup made it sound. Which is fine — these things rarely are — but I'd feel better if we carved out twenty minutes this week to close the loop properly, so we're not carrying ambiguity into the next phase of work when we don't have to be.",
        # Terse / direct / playful
        "Shipped. Sleep.",
        "Fine. Let's just do it.",
        "Monday, 10am, my place. Bring coffee.",
        "Fixed it. The trick was to stop being clever about it.",
        "Two bugs tonight. Slept four hours. Anyway.",
        # Formal + warm (rare combo)
        "Dear Professor Okafor, it is my genuine pleasure to write in support of Dana's application. I have known Dana for three years in both an instructional and an advisory capacity, and I can say without reservation that they possess the intellectual rigor and the personal generosity that your program is known for cultivating. Their work on the gradient-estimation project was, quite simply, the most careful piece of undergraduate research I have supervised in the last decade. I recommend them to you without the slightest qualification.",
        "To the family of Lindqvist — please accept my deepest condolences on your loss. I worked alongside Bergeron for eleven years, and in that time I came to regard him as one of the most quietly thoughtful people I have had the privilege of knowing. He made every room he entered a little more humane; he made every project he touched a little more worth finishing. The absence he leaves behind will be felt in this department for a very long time.",
        # Direct + hedged (contradictory combo for coverage)
        "OK here's what I think we should do, and I reserve the right to change my mind by Wednesday: ship the smaller scope this sprint, hold the bigger decision until after the offsite, and revisit the whole plan once we've seen how the A/B on the landing page actually shakes out. Pushback welcome, but I'd ask for the pushback to come with a proposed alternative rather than an objection in isolation.",
        # Humor + terse + assertive
        "The fire drill went exactly as well as every previous fire drill, which is to say: it did not, and we all now know where the fire exits were also not, and management has announced that a follow-up drill will be scheduled for a date which will remain classified until approximately seven minutes before it occurs.",
        # Verbose + cold (stereotyped academic prose)
        "It is widely acknowledged within the contemporary literature that the phenomenon under examination — hereafter referred to as X for the sake of expositional brevity — admits of multiple, partially overlapping, and frequently contested operationalizations, each of which carries with it a constellation of methodological commitments and epistemic trade-offs that render any univocal characterization of X not merely difficult but arguably ill-posed as a research question.",
        # Playful + hedged
        "I mean, I'm probably wrong, but hear me out: what if the reason the code review takes six days is that we keep framing the review as a test the author has to pass instead of a conversation between two people who both want the thing to ship? I said probably. I said hear me out. I reserve the right to retract.",
        # Warm + direct (classic coach voice)
        "Look at me. You did the work. You prepared. You showed up. Whatever happens in the next hour, none of that changes. Go in, breathe, and trust the version of you who's been putting in the hours. That's the only version that matters right now.",
        # Cold + hedged (bureaucrat)
        "While we appreciate the concern raised in your inquiry dated the 14th, we are at present unable to confirm whether the matter falls within the scope of our office's jurisdiction. A determination may or may not be forthcoming; if forthcoming, it will be communicated through the usual channels and no sooner than 45 business days from the date of this acknowledgment.",
        # Playful + verbose + warm
        "The dog, whose name is officially Beatrice but who answers exclusively to 'Beans,' has a series of morning rituals that she performs with the solemnity of a small, well-organized monastery: first, the circling; second, the sigh; third, the strategic leaning against the leg of whoever looks least likely to withstand her psychic pressure for an earlier breakfast. She has been refining this liturgy for four years and has not yet missed a single service.",
        # Direct + terse + warm
        "Saw the news. Hugs. Call me whenever. No agenda.",
        "Heard about the baby. Congratulations, truly. Don't reply to this.",
        "Happy birthday. You're one of the good ones. See you soon.",
        # Serious / journalistic voice / direct
        "Three years after the settlement, the state has quietly abandoned two of the four enforcement provisions it had previously called non-negotiable. No press release accompanied the change. The affected communities were not consulted. An administrator, reached by phone, described the decision as 'an operational adjustment' and declined to elaborate further.",
        # Formal + verbose + hedged
        "The Committee wishes to acknowledge, with appropriate caution, that while the preliminary indicators suggest a potentially favorable trend in the relevant outcome variables, the evidentiary basis remains, as of the date of this interim report, insufficient to support a formal revision of the existing guidance, and the Committee will therefore continue its review in anticipation of the fuller dataset expected in the subsequent reporting cycle.",
        # Warm + hedged + terse
        "Not sure what you need right now. Just know I'm around.",
        "Probably nothing to say. Just — thinking of you.",
        "Don't know if this helps. But I'm here if it does.",
        # Terse + cold + direct (curt/rude register)
        "Read the doc.",
        "Not my problem.",
        "Already answered. See thread.",
        "Fix it yourself.",
        "Closed. Won't reopen.",
        # Medium all-axes (the 0.5 center — important for training)
        "The review went about how you'd expect. A few good points, a few points that were mostly re-stated from last week, one actual new thing worth following up on. I'll write up the new thing tomorrow and send it around by the end of the week. Everything else can wait.",
        "We looked at three options and ended up going with option two. Option one was too ambitious for the time we have; option three was too conservative given the downside we're trying to avoid. Option two threads the needle — not cleanly, but cleanly enough. Implementation starts Monday.",
        "The kitchen is mostly clean. The floor needs sweeping, the window wants washing, and somebody has clearly not been emptying the compost bucket. Taken together it's the kind of situation that isn't anybody's fault in particular and therefore tends to be nobody's fault in practice.",
        # Weird: all-low (terse, casual, cold, assertive, dry, direct)
        "Done. Bye.",
        "No.",
        "Won't.",
        "Already gone.",
        "Don't.",
        # Strong humor + hedging (the self-deprecating blogger)
        "I could probably, maybe, in a better life, have figured this out three weeks ago, but the version of me that exists in the actual universe waited until 11:47 PM on a Thursday and then spent an hour wondering if it was okay to just sleep on it. For the record — and I want to be clear about this — it was not okay. I'm going to have to fix it in the morning.",
        # Strong warmth + terse
        "You did great.",
        "I see you.",
        "We're good.",
        "Proud of you.",
        "You're not alone.",
        # Academic + direct + terse (abstract-style)
        "We show that X implies Y. Prior work disagreed. A counter-example resolves the disagreement.",
        "This paper argues three things. First: A. Second: B. Third: not C. The appendix defends each claim.",
        # Conversational / warm / verbose (friend catching up)
        "Oh my god, where do I even start. The trip was amazing — you'd have loved it, like, I kept thinking about how you would have reacted to the cab ride from the airport alone, never mind the dinner situation on the second night. I have pictures. I have stories. I have about seventeen minutes of voice memos I recorded at 3 AM after we got back to the hotel that are either profound or unhinged and I'm genuinely not sure which yet. When can you come over.",
        # Mixed: playful phrases inside formal frame
        "The Committee, convened Tuesday, has concluded — with what one member described, off the record, as 'a weariness that has begun to feel structural' — that the current framework cannot accommodate the volume of exceptions now being routinely requested under it.",
        # Hedged + cold (careful scientist)
        "It may be the case that the observed correlation is partially attributable to an unmeasured confound, though the magnitude of the effect, if interpreted causally, would still exceed the conventional threshold for substantive significance. We do not assert causality here; we merely note the persistence of the association across the three independent specifications reported in Table 2.",
        # Conversational + cold (customer support gone wrong)
        "I understand your concern. I hear you. That said, the policy is clear, the system is functioning as designed, and there is no override I am able to issue at this time. I encourage you to submit the appeal through the designated channel, though I should note that appeals of this type are rarely granted. Is there anything else I can help you with today.",
        # Playful + formal (wedding toast template)
        "Ladies and gentlemen, distinguished relatives, strategically placed ex-girlfriends — I have been instructed by the happy couple to keep this toast brief, a directive I will honor in spirit by pretending to do so for approximately four minutes. Please charge your glasses. The humiliation begins now.",
        # Concise + warm (note in a lunchbox)
        "Hope today is a good one. I packed the snack you like. You've got this. Love you.",
        "Long day tomorrow. Get home safe. I made the thing for dinner. Love, M.",
        # Stream-of-consciousness / high verbosity / hedged / warm
        "Walking home tonight the streets were quiet in that particular way they get when it's just cold enough that the people who would otherwise be out have decided against it, and I was thinking about the conversation with Reyes, or rather I was trying not to think about the conversation with Reyes, which is a thing I do more than I'd like to admit — the trying-not-to-think, I mean, not the conversations with Reyes specifically — and then I walked past the bakery and someone inside was laughing loudly at something I couldn't hear and for no particular reason the whole evening rearranged itself into something lighter.",
        # Very short + formal + cold (official notice)
        "Parking prohibited. Violators will be towed at owner's expense.",
        "No trespassing. Private property. Authorized personnel only.",
        "Out of service. Please use alternate entrance.",
        # Very short + casual + warm
        "Save me a seat!",
        "You're the best.",
        "Coffee? I'm buying.",
        # Passive voice dominant (low directness)
        "It was felt by the group that the meeting could perhaps have been more efficiently structured, and suggestions were invited, though not many were ultimately received. A follow-up is to be scheduled in due course. Attendance will, as ever, be optional in theory and strongly encouraged in practice.",
        # Active voice + direct + cold
        "I vetoed the proposal. The analysis was weak. The timeline was unrealistic. Resubmit when both are fixed. Not before.",
        # Mix of registers within one paragraph (signals ambiguity to the judge)
        "Alright, so the technical decision here — and I'll be blunt because we don't have time to dance around it — comes down to latency vs. cost. The architecture team has put together a genuinely thoughtful three-way analysis (respect, everyone) and the upshot is that option B gives us about 30% better p99 at roughly 15% higher infrastructure spend. Leadership, your call. I'll implement whichever we pick by end of next week. I'd bet on B but I've been wrong about this stuff before.",
    ]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True, type=pathlib.Path)
    ap.add_argument(
        "--size",
        type=int,
        default=TARGET,
        help=f"target number of unique rows (default {TARGET})",
    )
    ap.add_argument(
        "--fills-per-template",
        type=int,
        default=25,
        help="how many parametric fills to generate per style template (default 25, calibrated to hit TARGET=1500 after dedup)",
    )
    args = ap.parse_args()

    rnd = random.Random(SEED)
    raw_texts: list[str] = []

    # 1. Literary passthrough (filter to the style 200..2000 window).
    raw_texts.extend(filter_literary())

    # 2. Per-category template fills.
    for cat, tmpls in STYLE_CATEGORIES.items():
        raw_texts.extend(
            build_category_samples(cat, tmpls, rnd, args.fills_per_template)
        )

    # 3. AMBIGUOUS_SEEDS combined into casual paragraphs.
    raw_texts.extend(combine_ambiguous_seeds(rnd))

    # 4. Real sample-corpus windows.
    raw_texts.extend(slice_corpus_windows())

    # 5. Hand-written extension paragraphs (style-axis extremes).
    raw_texts.extend(extend_literary_synthetic())

    # Deterministic shuffle so order is not trivially category-sorted.
    rnd.shuffle(raw_texts)

    # Dedup by request_id (sha of full text).
    seen: set[str] = set()
    rows: list[dict] = []
    for t in raw_texts:
        t = t.strip()
        if not (MIN_CHARS <= len(t) <= MAX_CHARS):
            continue
        rid = sha_id(t)
        if rid in seen:
            continue
        seen.add(rid)
        rows.append({"request_id": rid, "text": t})

    if len(rows) < args.size:
        print(
            f"warn: only {len(rows)} unique rows after dedup; target was {args.size}",
            file=sys.stderr,
        )
    rows = rows[: args.size]

    args.out.parent.mkdir(parents=True, exist_ok=True)
    with args.out.open("w") as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")

    # Length histogram on stderr for a quick sanity check.
    buckets = {"200-400": 0, "400-800": 0, "800-1200": 0, "1200-2000": 0}
    for r in rows:
        n = len(r["text"])
        if n < 400:
            buckets["200-400"] += 1
        elif n < 800:
            buckets["400-800"] += 1
        elif n < 1200:
            buckets["800-1200"] += 1
        else:
            buckets["1200-2000"] += 1
    print(
        f"wrote {len(rows)} rows → {args.out}; length buckets: {buckets}",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
