---
name: kiln-demo-recording
description: Everything needed to record the 3-minute Kiln demo video for the hackathon submission — shot-by-shot script, voice-over, technical recording requirements, pre-flight checklist, the three fixed Growing Model prompts, and failure-mode recovery plans. Load whenever Claude Code is planning, rehearsing, recording, or editing the demo video, or when the `/demo-check` command runs.
---

# Kiln — Demo video runbook

Hackathon grading weights: Impact 30%, Demo 25%, Opus 4.7 Use 25%, Depth 20%. The demo carries a quarter of the grade, but more importantly it is the artifact that projects Impact and the Opus-as-teacher story into the judges' heads. **The demo is the product, for judging purposes.**

Target length: **2:45–3:00**. Hard cap at 3:00. If we hit 3:01 we fail submission rules.

## 1. Shot-by-shot script

### 0:00-0:15 — Hook

- Full screen: the slogan in SF Pro Display 120pt on black. *"Opus taught the teacher. Your Mac does the work."*
- Fade to desktop. Finder open to `~/Documents/notes`. Kiln dock icon bouncing once.
- VO opens.

### 0:15-0:40 — Problem + promise

- Split screen: on the left, generic Qwen2.5-3B answering "What did you do this morning?" with dry generic prose. On the right, the same prompt from a real person. Caption: *"This is you. This is a base model. They are not the same person."*
- Cut to Kiln launching. The drop zone pulses amber.
- VO: *Kiln takes a folder of your writing and teaches a local model to sound like you. Fully on your Mac. Zero APIs at runtime.*

### 0:40-1:15 — Dataset Doctor + Style Profile

- Drag a folder onto Kiln. Drop zone fills with amber. Dataset Doctor appears.
- Metrics animate up: `3,214 chunks -> 2,487 kept`. Sparkline draws. Three example kept/dropped snippets flash past.
- Cut to Style Profile card: *"You write in short, declarative sentences. You use semicolons twice as often as average. You hedge rarely."* — three bullets, one at a time.
- VO: *The quality filter was taught by Opus 4.7 — one-time, offline. The style profile too. None of this calls out at runtime.*

### 1:15-2:00 — Training + Growing Model (the emotional peak)

- Click *Teach your model*. Progress bar pulses amber.
- Growing Model panel fills the right half of the screen. Three prompts. Responses stream in. Every 30 seconds (compressed in the edit), the responses update: generic -> generic-with-a-hint -> distinctly the user.
- On-screen time-lapse indicator in the corner.
- VO: *Every 50 iterations, Kiln checkpoints and answers three fixed prompts. You watch the model become you in real time.*

### 2:00-2:30 — Before/After + chat

- Split pane. Same prompt, base vs fine-tuned. Type one prompt: *"Quick take on the deploy?"*. Both answer. The left is generic-helpful. The right is the user's voice — short, direct, opinionated.
- Cursor hovers the fine-tuned side. Caption: *"Same prompt. Same model family. Different voice."*

### 2:30-2:50 — Ollama export

- Click *Export to Ollama*. Terminal animation: `fuse -> convert -> quantize -> ollama create kiln-timothee`. Each step ticks green.
- Terminal opens live: `ollama run kiln-timothee`. Type `what should I work on tonight?`. The model replies in the user's voice.

### 2:50-3:00 — Punchline

- Cut to the slogan again. *"Opus taught the teacher. Your Mac does the work."*
- Small footer: *"Built during Built with Opus 4.7. Kiln is open source."*
- End card.

## 2. Voice-over script (time-stamped, ~420 words for ~3:00)

```
(0:05)  Every chat model sounds like a stranger.
(0:10)  Kiln turns that stranger into you — on your Mac, from a folder.
(0:20)  Drop your notes, your journal, your email, your code.
(0:28)  Kiln parses, deduplicates, and filters for quality.
(0:35)  The quality filter was taught by Opus 4.7, once, offline.
(0:42)  Now it runs locally. Forever.
(0:52)  Kiln extracts your style. Short sentences. Semicolons. No hedging.
(1:05)  It configures a LoRA fine-tune in MLX — Apple Silicon native.
(1:18)  As training runs, three fixed prompts rerun every checkpoint.
(1:28)  You watch the model become you.
(1:45)  (no VO — let the growing model panel breathe)
(2:00)  Same prompt, base versus fine-tuned. Same model family, different voice.
(2:20)  One click — fuse, GGUF, Ollama create.
(2:35)  Terminal opens. Your model answers in your voice.
(2:50)  Opus taught the teacher. Your Mac does the work.
```

Read it aloud at least twice on the recording day. Voice-over takes more time than you think.

## 3. Technical recording requirements

- **Resolution:** 1920x1080 minimum, 2560x1440 preferred. 60 fps recording, 30 fps export.
- **Audio:** 48 kHz, 16-bit, peak -6 dBFS, mean -18 dBFS. Mic: anything directional in a quiet room. Kill HVAC before recording.
- **Screen capture:** `ScreenStudio` or `CleanShot X`. Native macOS screen recording for raw, ScreenStudio for the zooms. Turn off notifications (`Do Not Disturb` -> "Until tomorrow").
- **Terminal font:** SF Mono 22pt. Background dark grey `#1C1C1E`. Window 1200x600. Zoom in on the terminal during `ollama create` shot.
- **Cursor:** large cursor on, click highlight on.
- **Recording computer:** 32 GB M-series Mac. Close every other app. Plug in power.

## 4. The three fixed Growing Model prompts

Locked. These appear in three places: the SwiftUI panel, the sidecar config, and this skill file. They must match exactly.

```
P1: What did you do this morning?
P2: Quick take on the deploy?
P3: Write a short note to a friend you haven't seen in a year.
```

Rationale: P1 tests mundane voice (where fine-tuning shines). P2 tests opinionated short-form. P3 tests warmth, length control, and hedging rate.

## 5. Pre-flight checklist (run at least 2 hours before the final take)

- [ ] Corpus folder pre-staged at `~/Documents/kiln-demo-corpus` with ~500 files of your own writing.
- [ ] Base model pre-downloaded: `mlx-community/Qwen2.5-3B-Instruct-4bit` in `~/.cache/huggingface/`.
- [ ] Distilled artifacts present in `distilled/*/model.*`. Missing ones fall back cleanly but look worse.
- [ ] Ollama running: `ollama serve` in a background terminal. Confirm `ollama list` responds.
- [ ] Kiln build is the `main` build, not a debug build with log spew.
- [ ] Screen Recording permission granted.
- [ ] `Do Not Disturb` on.
- [ ] Battery > 80% or plugged in.
- [ ] Test run end-to-end at least once today. Discard the output but keep the fact that it worked.
- [ ] Rehearse voice-over at least twice.
- [ ] Clock: hackathon submission is Sunday 8 PM EST. Final video export done by 6 PM.

## 6. Failure modes and backup plans

| Failure | Detection | Recovery |
|---|---|---|
| Training takes longer than budget on the day | stopwatch during rehearsal | pre-record the training segment and cut to the finish |
| Ollama isn't running | demo blocks on export | have a terminal pre-opened with `ollama serve` and checked |
| Model output is generic (corpus wrong size) | rehearsal | pre-select a corpus known to produce strong voice |
| Screen recording drops frames | visible in playback | re-record; close Xcode; disable GPU-heavy apps |
| VO clips | audio waveform | re-record VO; separate track, don't re-capture screen |
| Kiln crashes mid-demo | obvious | rehearse the recovery: launch, skip to cached run, keep going |

If anything goes wrong on recording day past 4 PM, cut to the pre-recorded fallback. Do not re-shoot from scratch inside the last 2 hours.

## 7. Edit discipline

- No jump cuts. Use cross-fades (200 ms) between scenes.
- No stock music. If music at all, it is ambient, under -20 dBFS, fades out during VO.
- Captions on for accessibility — they also help judges skimming.
- End on a single beat of silence, then the slogan.

## 8. What to avoid

- "Hi, I'm X and this is Kiln." The product is the intro.
- Any on-screen UI that shouldn't ship (debug panels, seed values, log windows).
- Typing too fast to read. 3 chars/sec for the terminal, 4 chars/sec for chat input.
- Showing the Finder path with your real `/Users/<name>`. Either use `~/` or blur.
- Claiming a capability the app doesn't have.

## 9. Submission checklist (does not replace `/ship`)

- [ ] Video <= 3:00 exported as H.264 MP4, <= 200 MB.
- [ ] Video uploaded to YouTube (unlisted) and/or attached to the submission form.
- [ ] Thumbnail still picked (the Growing Model panel mid-transformation is the best frame).
- [ ] Captions file (`.vtt`) generated.
