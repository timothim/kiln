#!/usr/bin/env python3
"""Build the 500-row pilot input JSONL for the Distillation Orchestrator.

Composition (deterministic, seeded):
  ~200  high-quality voice-bearing snippets from tests/fixtures/sample_corpus/*.md
         + 20 hand-picked public-domain literary snippets
  ~150  low-quality synthetic (auto-replies, log lines, boilerplate)
  ~150  ambiguous: edge_cases/ + chat JSON extracts + short utterances

Output:
  managed-agents/corpus-builder/inputs/pilot-500.jsonl
  one row per line: {"request_id": <16-char hex>, "text": <string <= 1000 chars>}
"""
import argparse
import hashlib
import json
import pathlib
import random
import re
import sys

REPO = pathlib.Path(__file__).resolve().parents[2]
CORPUS = REPO / "tests" / "fixtures" / "sample_corpus"
SEED = 42
TARGET = 500


LITERARY = [
    "Call me Ishmael. Some years ago—never mind how long precisely—having little or no money in my purse, and nothing particular to interest me on shore, I thought I would sail about a little and see the watery part of the world.",
    "It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.",
    "All happy families are alike; each unhappy family is unhappy in its own way.",
    "The old man was thin and gaunt with deep wrinkles in the back of his neck. The brown blotches of the benevolent skin cancer the sun brings from its reflection on the tropic sea were on his cheeks.",
    "Mother died today. Or maybe yesterday, I can't be sure. The telegram from the home says: 'Your mother passed away. Funeral tomorrow. Deep sympathy.' Which leaves the matter doubtful; it could have been yesterday.",
    "In my younger and more vulnerable years my father gave me some advice that I've been turning over in my mind ever since. 'Whenever you feel like criticizing anyone,' he told me, 'just remember that all the people in this world haven't had the advantages that you've had.'",
    "Many years later, as he faced the firing squad, Colonel Aureliano Buendía was to remember that distant afternoon when his father took him to discover ice.",
    "It was a bright cold day in April, and the clocks were striking thirteen. Winston Smith, his chin nuzzled into his breast in an effort to escape the vile wind, slipped quickly through the glass doors of Victory Mansions.",
    "The sky above the port was the color of television, tuned to a dead channel.",
    "Last night I dreamt I went to Manderley again. It seemed to me I stood by the iron gate leading to the drive, and for a while I could not enter, for the way was barred to me.",
    "The sun shone, having no alternative, on the nothing new. Murphy sat out of it, as though he were free, in a mew in West Brompton.",
    "Stately, plump Buck Mulligan came from the stairhead, bearing a bowl of lather on which a mirror and a razor lay crossed.",
    "The man in black fled across the desert, and the gunslinger followed.",
    "Mrs. Dalloway said she would buy the flowers herself. For Lucy had her work cut out for her.",
    "It was a pleasure to burn. It was a special pleasure to see things eaten, to see things blackened and changed.",
    "For a long time, I used to go to bed early. Sometimes, when I had put out my candle, my eyes would close so quickly that I had not even time to say 'I'm going to sleep'.",
    "The past is a foreign country; they do things differently there.",
    "Happy families are all alike; every unhappy family is unhappy in its own way. Everything was in confusion in the Oblonskys' house.",
    "They shoot the white girl first. With the rest they can take their time.",
    "One summer afternoon Mrs. Oedipa Maas came home from a Tupperware party whose hostess had put perhaps too much kirsch in the fondue.",
    "You are about to begin reading Italo Calvino's new novel, If on a winter's night a traveler. Relax. Concentrate. Dispel every other thought. Let the world around you fade.",
    "When he was nearly thirteen, my brother Jem got his arm badly broken at the elbow. When it healed, and Jem's fears of never being able to play football were assuaged, he was seldom self-conscious about his injury.",
    "It was the best of times, it was the worst of times, it was the age of wisdom, it was the age of foolishness, it was the epoch of belief, it was the epoch of incredulity.",
    "I am an invisible man. No, I am not a spook like those who haunted Edgar Allan Poe; nor am I one of your Hollywood-movie ectoplasms. I am a man of substance, of flesh and bone, fiber and liquids.",
    "Lolita, light of my life, fire of my loins. My sin, my soul. Lo-lee-ta: the tip of the tongue taking a trip of three steps down the palate to tap, at three, on the teeth.",
    "It was a queer, sultry summer, the summer they electrocuted the Rosenbergs, and I didn't know what I was doing in New York.",
    "As Gregor Samsa awoke one morning from uneasy dreams he found himself transformed in his bed into a gigantic insect.",
    "I had the story, bit by bit, from various people, and, as generally happens in such cases, each time it was a different story.",
    "Someone must have slandered Josef K., for one morning, without having done anything wrong, he was arrested.",
    "Who is John Galt? The light was ebbing, and Eddie Willers could not distinguish the bum's face.",
    "124 was spiteful. Full of a baby's venom. The women in the house knew it and so did the children.",
    "In the beginning, sometimes I left messages in the street. Where to start the story?",
    "The cold passed reluctantly from the earth, and the retiring fogs revealed an army stretched out on the hills, resting.",
    "Whether I shall turn out to be the hero of my own life, or whether that station will be held by anybody else, these pages must show.",
    "I write this sitting in the kitchen sink. That is, my feet are in it; the rest of me is on the draining-board, which I have padded with our dog's blanket.",
    "It was like so, but wasn't. People came and went, and the days got colder, and then warmer again.",
    "There was a boy called Eustace Clarence Scrubb, and he almost deserved it.",
    "None of them knew the color of the sky. Their eyes glanced level, and were fastened upon the waves that swept toward them.",
    "The story so far: In the beginning the Universe was created. This has made a lot of people very angry and been widely regarded as a bad move.",
    "When Mr. Bilbo Baggins of Bag End announced that he would shortly be celebrating his eleventy-first birthday with a party of special magnificence, there was much talk and excitement in Hobbiton.",
    "It was love at first sight. The first time Yossarian saw the chaplain he fell madly in love with him.",
    "We slept in what had once been the gymnasium. The floor was of varnished wood, with stripes and circles painted on it, for the games that were formerly played there.",
    "A screaming comes across the sky. It has happened before, but there is nothing to compare it to now.",
    "He was an old man who fished alone in a Gulf Stream skiff and he had gone eighty-four days now without taking a fish.",
    "The drought had lasted now for ten million years, and the reign of the terrible lizards had long since ended.",
    "In a hole in the ground there lived a hobbit. Not a nasty, dirty, wet hole, filled with the ends of worms and an oozy smell.",
    "You better not never tell nobody but God. It'd kill your mammy.",
    "There was no possibility of taking a walk that day. We had been wandering, indeed, in the leafless shrubbery an hour in the morning.",
    "All this happened, more or less. The war parts, anyway, are pretty much true.",
    "The sun shone brilliantly after the storm, and the smell of wet asphalt rose up like a memory I didn't know I had.",
    "She looked at me the way someone looks at a bird that has flown into a window — part pity, part relief that it wasn't her.",
    "I have been thinking about what you said and I think you are mostly right. The part you are wrong about is the part that matters most.",
    "The house on the hill was not haunted. It was merely lonely, which is a different condition and arguably worse.",
    "By the time I reached the station the last train had already pulled away, and the platform was empty except for a single folded newspaper.",
    "What nobody tells you about grief is how physical it is — how it lives in the shoulders, the jaw, the back of the throat.",
    "Halfway through the second cup of coffee I understood that the problem I had been trying to solve was not the actual problem.",
    "He wrote letters to his daughter for eleven years and mailed exactly none of them. They were stacked in a shoebox in the closet, sorted by date.",
    "The city at four in the morning is neither the city of the night nor the city of the day. It is a third thing, quieter than either, with its own rules.",
    "I used to believe that if you worked hard enough, you could make anyone see you the way you wanted to be seen. I no longer believe this.",
    "The river in winter runs slower but louder, like an old man who has learned the value of taking his time but has not yet learned to whisper.",
    "There is a particular kind of silence that happens in a house where a child has just stopped crying, and you do not want to break it.",
    "I was seventeen when I first understood that kindness is a decision, not a feeling, and that you can make it on the worst days, too.",
    "The dog knew the route better than I did. I just held the leash and pretended I was in charge, and the dog was kind enough to let me believe it.",
    "You can tell a lot about a person by the books they keep unread. The ones they bought with good intentions and never opened say more than the ones they finished.",
    "My grandmother's kitchen smelled of cumin and onions and the particular warmth of cast iron that has been cared for across decades.",
    "The first draft is always the draft where you find out what you actually think, as opposed to what you thought you thought.",
    "Sometimes the right thing to do is obvious, and the hard part is not figuring it out but getting yourself to actually do it.",
    "On the train ride home I started rewriting the conversation in my head, giving myself all the good lines I hadn't thought of at the time.",
    "There is a particular exhaustion that comes from spending a day pretending to be a slightly better version of yourself.",
    "She had the habit, when thinking hard about something, of holding her breath without realizing it, until the world seemed to pause with her.",
    "The old barn leaned a little more each year, as though it had been standing up straight for long enough and had decided it was done.",
    "I've learned that the people who say 'I'm fine' most often are the ones most worth checking in on, and the ones who say it least.",
    "You don't notice the small kindnesses of a city until you leave it, and then suddenly you notice their absence everywhere at once.",
    "The hardest part of moving on isn't letting go of the thing itself — it's letting go of the version of yourself that wanted it.",
    "I sat on the porch for an hour after the phone call, watching the light change, trying to decide what to feel first.",
    "We are all, I think, a little more fragile and a little more durable than we tend to give ourselves credit for, and usually at inconvenient times.",
    "There's a trick to reading poetry aloud that took me years to learn: you have to trust the silences as much as the words.",
    "The new manager, on her first day, asked each of us what was the one thing she could do that would make our job better. Almost nobody had an answer ready.",
    "The best advice I ever got about writing was from a carpenter: if it looks like it was easy, you did it right, and you probably worked twice as hard.",
]

LOW_QUALITY_PATTERNS = [
    "Thank you for your email. I am currently out of the office and will return on {d}. For urgent matters, please contact {n} at {n}@{c}.com.",
    "This email and any attachments are confidential and may be privileged. If you have received this in error please delete it and notify {n} immediately.",
    "[2025-{mm}-{dd} {hh}:{mi}:{ss}] INFO [main] Starting application version 2.4.{p} in {env} mode",
    "[2025-{mm}-{dd} {hh}:{mi}:{ss}] ERROR [worker-{p}] Connection refused: could not connect to upstream service at {host}:{p}",
    "[2025-{mm}-{dd} {hh}:{mi}:{ss}] WARN [{module}] deprecated flag --{flag} used; support will be removed in version 3.{p}",
    "© 2025 {c}. All rights reserved. Use of this site is subject to the Terms of Service updated on {d}.",
    "To unsubscribe from emails from {c} click {link}. Manage your preferences at {c}.com/prefs.",
    "Your one-time passcode is {p}. This code expires in {p2} minutes. Do not share this code with anyone, not even {c} staff.",
    "<div class='{module}'><p>Lorem ipsum dolor sit amet {n} consectetur {flag}</p></div><script src='/app-{p}.js'></script>",
    "Save {p}% on your next order at {c}! Use code SAVE{p2} at checkout. Offer expires {d}. Limited time only.",
    "Hi {n}, thanks for signing up with {c}! To complete registration click the link we sent to {n}@{c}.com.",
    "Your order #{p} at {c} has shipped via {carrier}. Tracking: 1Z{p}{p2}{p}. Expected delivery: {d}.",
    "Build succeeded. 0 warnings, 0 errors. Elapsed: {p2}m {p}s. Artifact: {c}-{p}.{ext}.",
    "running test_{module}_{flag} ... ok\nrunning test_{module}_edge ... ok\nrunning test_{module}_happy_path ... FAILED (line {p})",
    "class {n}(BaseModel):\n    id: int\n    {flag}: str\n    email: EmailStr\n    created_at: datetime",
    "def {flag}(self, x, y):\n    # auto-generated stub for {module}\n    self.x = x\n    self.y = y\n    return self._{flag}()",
    "function {flag}() {{ return {module}({p}); }} // generated on {d}",
    "Please wait while we load your {content}… This may take up to {p} seconds.",
    "Page not found at /{module}/{flag}. The {content} you're looking for may have moved or been deleted on {d}.",
    "Cookie notice: we use cookies on {c}.com to improve your experience. Accept all | Customize | Reject non-essential",
    "RT @{n}: Just finished reading this piece on {content}. Highly recommend for anyone interested in {flag}! {h}",
    "Loading {content}… Loading {content}… Loading {content}… Timeout after {p}ms.",
    "Error: ENOENT: no such file or directory, open '/tmp/{c}-{p}.log' in {module}",
    "HTTP/1.1 200 OK\nContent-Type: application/json\nContent-Length: {p}\nX-Request-ID: {p2}-{p}",
    "SELECT id, name FROM {flag} WHERE {flag}_id = {p} AND status = '{content}' LIMIT {p2};",
    "git commit -m \"wip: {flag} for {content}\"\ngit push origin {flag}/{module}",
    "You have ({p}) new notifications from {c}. Click here to view them or manage preferences.",
    "This message was sent from an unmonitored mailbox at {c}. Please do not reply. For support, visit {c}.com/help.",
    "Agree to the terms and conditions to continue using {c}. [checkbox] I agree to the Terms of Service updated {d}.",
    "Your session with {c} expired after {p} minutes of inactivity. Please log in again to continue your {content}.",
    "docker run --rm -v $PWD:/app {c}/{module}:{p}.{p2} python /app/{flag}.py --env {env}",
    "Your payment of ${p}.{p2} to {c} was declined. Please update your payment method before {d} to avoid service interruption.",
    "[CI] Job {flag}-{p} on {module} queue {content}: status=failed, exit_code={p2}, duration={p}s. See logs.",
    "From: noreply@{c}.com\nTo: {n}@{c}.com\nSubject: Account security alert — action required by {d}",
    "@everyone the {content} meeting scheduled for {d} has been moved to {hh}:{mi} per {n}'s calendar",
    "{n}: hey\n{n}: you there?\n{n}: nvm\n{n}: found it",
    "<html><head><meta charset='utf-8'><title>{c}</title></head><body class='{module}'>{content}</body></html>",
    "FROM ubuntu:22.04\nRUN apt-get update && apt-get install -y {flag}\nCOPY . /app\nCMD [\"python\", \"/app/{module}.py\"]",
    "[{hh}:{mi}:{ss}] {n} joined the channel\n[{hh}:{mi}:{ss}] {n} left the channel\n[{hh}:{mi}:{ss}] {n} joined the channel",
    "Subscribe to our newsletter for exclusive {content} from {c}! Enter your email below and we'll send you weekly {flag} updates.",
]

AMBIGUOUS_SEEDS = [
    "I don't know what to do. Everyone seems to want something different from me and I can't keep track anymore.",
    "maybe later when things calm down a bit",
    "lol that's wild — did you see the end of it or did you stop halfway",
    "tbh I think he's right, even if his delivery leaves something to be desired",
    "gonna grab coffee brb — want anything from the place on 5th?",
    "ok thx for the heads up, I'll loop back once I've had a chance to read it",
    "can we talk? Something came up and I'd rather not put it in writing",
    "idk, you tell me — it's your call and I'll back whatever you decide",
    "Fine, fine, you win. But don't come crying to me when it blows up in your face.",
    "Just got home. You up? Want to hop on a call for ten minutes and debrief?",
    "Need to think about this one. It's more tangled than I initially realized and I want to sleep on it.",
    "Sorry I missed your call — was in back-to-back meetings all afternoon. Call you back after 6?",
    "On my way. Traffic's a nightmare so maybe 20 instead of 10.",
    "Saw that. Will respond properly later tonight once I'm not typing from my phone.",
    "Not sure this is going to work. I've tried the three things you suggested and none of them changed anything.",
    "Let's circle back tomorrow. Too much going on right now to give this the attention it deserves.",
    "Running 10 minutes late — getting out of the previous thing ran long. Apologies.",
    "Weather's been nuts lately. Three seasons in a single week.",
    "Did you see the email from Jess? She's asking about the thing we talked about last Thursday.",
    "Miss you. Hope the move is going smoothly. Let me know when you're settled.",
    "I keep going back and forth on this. Some days it feels obvious, other days I can't see it at all.",
    "Fair point. I'd push back on the third bullet though — I don't think we have enough evidence yet.",
    "Been thinking about what you said at lunch. You might be onto something.",
    "Quick q — do we have a doc somewhere that explains the routing logic, or is it all tribal knowledge?",
    "Confirmed. Ping me if anything else comes up before the review tomorrow.",
    "That's… a lot. Let me read through it once more before I respond properly.",
    "Not sure I agree but I'll think about it. Not worth arguing right now.",
    "Worth noting: the deadline slipped again. Third time this quarter.",
    "Small thing — the copy on the landing page feels off. Can we look at it together Friday?",
    "Moving on — what's the plan for next week?",
    "I think we're overcomplicating this. What if we just shipped the v1 and iterated?",
    "Reading the draft now. First impression: stronger than I expected.",
    "Honest question: is this worth doing at all, or are we sunk-cost-ing it?",
    "Glad I'm not the only one who noticed. Thought I was losing my mind.",
    "One more thing before I forget — can you check the timezones on the calendar invite?",
    "Signal strength over there? I keep losing you.",
    "Too tired to write a real response right now. Short version: yes.",
    "The scope keeps creeping. We should re-baseline before committing to more.",
    "Small brag: got the test suite under 90 seconds finally.",
    "Late to the party on this one. Catching up now.",
    "Is this a bad time? I can call back in twenty minutes if you're mid-thing.",
    "The thing I keep coming back to is whether we're optimizing for the right metric in the first place.",
    "Ok last thought and then I'll stop — what if the issue is not the tool but the workflow around it?",
    "You already know what I'm going to say. I'm going to say it anyway.",
    "Rough week. Not ready to talk about it yet but I will be soon.",
    "Thanks for being patient with me on this. I know I've been slower to respond than usual.",
    "I was going to wait until Monday to bring it up but it feels more urgent than that.",
    "Re: your question — yes, but with caveats. The caveats matter more than the yes.",
    "Honestly the part I liked best was the middle. The ending felt a little rushed to me.",
    "Not asking you to fix anything, just wanted to vent for a minute.",
    "If we pull this off we're going to have to figure out what to do for an encore.",
    "Watched it twice. First time for the plot, second time for everything I missed.",
    "Spent the morning reorganizing my notes. Feels better. Still not done.",
    "I can't tell if the quiet means it's working or it's broken.",
    "Reminder to self: ask about the onboarding doc in standup tomorrow.",
    "Did we ever get clarity on the ownership question or is that still floating?",
    "Brain is absolute mush today. Going to call it early and try again fresh.",
    "Drafting a longer response in email. This one was worth more than a slack reply.",
    "Got pulled into something. Will have to skip the 3pm — apologies for the late notice.",
    "The fact that we're even having this conversation tells me something is off upstream.",
    "You had me at 'incremental'. That's exactly the right framing.",
    "Not a blocker but flagging it now so it doesn't become one later.",
    "Final ask of the day: can someone sanity check the numbers in the shared doc?",
    "I had a whole argument prepared and then I read your second paragraph and it dissolved.",
    "Give me 20 to wrap up this thing and I'm all yours.",
    "Coming back to this after a walk. Clearer in my head now.",
    "Short-term annoying, long-term the right move. I'll live with the annoying.",
    "Feels premature to have an opinion. Let me sit with it.",
    "Not in love with any of the options but option 2 is least bad.",
    "Something about the way that was phrased is sticking with me. Not sure why.",
    "Skipping the meeting today — agenda is all ground we've already covered.",
    "Sanity check: we agreed on the cutoff being end-of-day Thursday, right?",
    "Yes I know I keep bringing this up. I'll stop after this one I promise.",
    "Reading between the lines of that response. Want to confirm I'm reading correctly.",
    "Let me know if you want a second pair of eyes. Happy to jump in.",
    "Took the afternoon off. Needed the reset. Back tomorrow at normal time.",
    "Putting a pin in it. Don't want to lose the thread but not the right moment.",
    "Filed under: things we said we'd revisit but never did.",
    "For posterity: the reason we went with approach B was the constraint around latency.",
    "Small update, not urgent: the api docs page is out of date in a few places.",
]


def sha_id(text: str) -> str:
    return hashlib.sha256(text.encode()).hexdigest()[:16]


def slice_windows(text: str, max_chars: int = 400, min_chars: int = 60) -> list[str]:
    sents = re.split(r"(?<=[.!?])\s+", text.strip())
    windows: list[str] = []
    cur = ""
    for s in sents:
        if not s:
            continue
        if cur and len(cur) + 1 + len(s) > max_chars:
            windows.append(cur.strip())
            cur = s
        else:
            cur = (cur + " " + s) if cur else s
    if cur:
        windows.append(cur.strip())
    return [w for w in windows if min_chars <= len(w) <= 1000]


def load_high_quality() -> list[str]:
    out: list[str] = []
    # Sample corpus: try multiple window sizes to extract more distinct snippets
    for f in sorted(CORPUS.glob("[0-9][0-9]-*.md")):
        text = f.read_text(errors="ignore")
        out.extend(slice_windows(text, max_chars=400, min_chars=60))
        out.extend(slice_windows(text, max_chars=220, min_chars=40))
        out.extend(slice_windows(text, max_chars=700, min_chars=80))
    # Also chat JSONs / other code for voice-bearing continuation text
    for f in CORPUS.glob("*.py"):
        out.extend(slice_windows(f.read_text(errors="ignore"), max_chars=300, min_chars=50))
    for f in CORPUS.glob("*.swift"):
        out.extend(slice_windows(f.read_text(errors="ignore"), max_chars=300, min_chars=50))
    for f in CORPUS.glob("*.ts"):
        out.extend(slice_windows(f.read_text(errors="ignore"), max_chars=300, min_chars=50))
    random.shuffle(out)
    return out[:200] + LITERARY


def load_low_quality() -> list[str]:
    rnd = random.Random(SEED + 1)
    fills = {
        "d": ["Mar 14", "Apr 3", "May 1", "Jun 22", "Jul 5", "Aug 18", "Sep 9", "Oct 27", "Nov 3", "Dec 15"],
        "n": ["sarah", "mike", "jordan", "priya", "alex", "dana", "rafa", "kim", "luke", "nora"],
        "c": ["acme", "widget", "globex", "initech", "soylent", "cyberdyne", "tyrell", "weyland", "umbrella", "vandelay"],
        "mm": ["01", "02", "03", "04", "05", "06", "07", "08", "09", "10", "11", "12"],
        "dd": ["02", "05", "09", "14", "18", "22", "25", "28", "30"],
        "hh": ["01", "04", "08", "11", "14", "17", "20", "23"],
        "mi": ["05", "13", "22", "30", "37", "44", "52", "59"],
        "ss": ["01", "09", "17", "25", "33", "41", "48", "59"],
        "p": [str(rnd.randrange(100, 9999)) for _ in range(20)],
        "p2": [str(rnd.randrange(10, 99)) for _ in range(20)],
        "h": ["#news", "#life", "#tech", "#reading", "#writing", "#work", "#design", "#ideas"],
        "env": ["dev", "staging", "prod", "canary", "beta"],
        "module": ["auth", "billing", "search", "queue", "worker", "api", "cron", "ingest"],
        "flag": ["verbose", "legacy-mode", "cache-off", "beta", "strict", "trace", "silent", "retry"],
        "host": ["db-primary", "redis-01", "api-gateway", "cache-02", "queue-prod"],
        "carrier": ["UPS", "FedEx", "USPS", "DHL", "OnTrac"],
        "ext": ["tar.gz", "zip", "whl", "deb", "rpm"],
        "content": ["dashboard", "profile", "feed", "settings", "inbox", "cart", "history"],
        "link": ["<https://click.tracking.example>", "<here>", "<this link>"],
    }
    out: list[str] = []
    for pat in LOW_QUALITY_PATTERNS:
        for _ in range(12):
            s = pat
            for k, choices in fills.items():
                placeholder = "{" + k + "}"
                while placeholder in s:
                    s = s.replace(placeholder, rnd.choice(choices), 1)
            out.append(s)
    random.Random(SEED + 1).shuffle(out)
    return out[:220]


def load_ambiguous() -> list[str]:
    out: list[str] = list(AMBIGUOUS_SEEDS)
    # edge_cases subdir — whatever is there gets sliced (short windows)
    edge = CORPUS / "edge_cases"
    if edge.is_dir():
        for f in edge.rglob("*"):
            if f.is_file() and f.suffix.lower() in {".md", ".txt", ".json"}:
                text = f.read_text(errors="ignore")
                out.extend(slice_windows(text, max_chars=200, min_chars=30))
                out.extend(slice_windows(text, max_chars=400, min_chars=40))
    # emails subdir
    emails = CORPUS / "emails"
    if emails.is_dir():
        for f in emails.rglob("*"):
            if f.is_file():
                text = f.read_text(errors="ignore")
                out.extend(slice_windows(text, max_chars=300, min_chars=40))
    # chat JSONs — extract message texts
    for f in CORPUS.glob("*.json"):
        try:
            data = json.loads(f.read_text(errors="ignore"))
        except json.JSONDecodeError:
            continue
        msgs = data.get("messages") if isinstance(data, dict) else None
        if not isinstance(msgs, list):
            continue
        for m in msgs:
            if not isinstance(m, dict):
                continue
            txt = m.get("content") or m.get("text") or ""
            if isinstance(txt, list):
                txt = " ".join(x.get("text", "") for x in txt if isinstance(x, dict))
            if isinstance(txt, str) and 30 <= len(txt) <= 1000:
                out.append(txt)
    random.Random(SEED + 2).shuffle(out)
    return out[:200]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True, type=pathlib.Path)
    args = ap.parse_args()

    random.seed(SEED)
    rows: list[dict] = []
    for text in load_high_quality() + load_low_quality() + load_ambiguous():
        rid = sha_id(text)
        rows.append({"request_id": rid, "text": text[:1000]})

    # dedup
    seen = set()
    unique: list[dict] = []
    for r in rows:
        if r["request_id"] not in seen:
            seen.add(r["request_id"])
            unique.append(r)

    if len(unique) < TARGET:
        print(f"warn: only {len(unique)} unique rows; target was {TARGET}", file=sys.stderr)
    unique = unique[:TARGET]

    args.out.parent.mkdir(parents=True, exist_ok=True)
    with args.out.open("w") as f:
        for r in unique:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")

    print(f"wrote {len(unique)} rows → {args.out}")


if __name__ == "__main__":
    main()
