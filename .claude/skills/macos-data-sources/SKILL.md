---
name: macos-data-sources
description: Recipes for ingesting personal data from macOS sources (Messages via chat.db, Apple Notes, Drafts, Obsidian) into Kiln's training corpus. Covers TCC Full Disk Access requirements, the SQL schema and queries for chat.db, AppleScript for Notes export, SQLite paths for Drafts, Obsidian vault detection with YAML frontmatter, and Swift NSOpenPanel / security-scoped bookmark patterns. Load this skill whenever Claude Code is writing ingest code, diagnosing permission failures, or adding a new corpus source.
---

# macOS data sources — the Kiln recipe

Kiln's ingest layer (`packages/KilnCore/Sources/KilnCore/Ingest/`) must pull the user's own text from the five macOS sources Kiln supports in v1: folder drop (generic), Messages (iMessage/SMS via `chat.db`), Apple Notes, Drafts, and Obsidian vaults. Each source has a different permission model and a different schema quirk. This file is the operational manual.

Reference files (load on demand):

- [chat-db-schema.sql](chat-db-schema.sql) — working queries to run directly against a copy of `chat.db`
- [apple-notes-export.applescript](apple-notes-export.applescript) — tested Notes export loop
- [permissions-patterns.swift](permissions-patterns.swift) — `NSOpenPanel`, security-scoped bookmarks, TCC probe, SQLite UDF

## 1. Permission model — one table to remember

| Source       | Path                                                                              | Permission mechanism                                   | User prompt                                                |
|--------------|-----------------------------------------------------------------------------------|--------------------------------------------------------|------------------------------------------------------------|
| Folder drop  | any                                                                               | `NSOpenPanel` grant only                               | Standard file picker                                       |
| Messages     | `~/Library/Messages/chat.db`                                                      | TCC Full Disk Access (system setting)                  | Settings → Privacy & Security → Full Disk Access           |
| Apple Notes  | `~/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite` (encrypted)  | TCC Automation → Notes (via AppleScript)               | Automation prompt on first AppleScript call                |
| Drafts       | `~/Library/Group Containers/group.com.agiletortoise.Drafts-macOS/Documents/`     | App sandbox container access via `NSOpenPanel`         | File picker                                                |
| Obsidian     | any                                                                               | `NSOpenPanel` + security-scoped bookmark               | File picker                                                |

**Do not open any of these files directly via `FileManager`.** `chat.db` requires a TCC grant; the Notes store is encrypted; Drafts lives in a sandboxed group container. Always ask the user to grant via the correct mechanism — detection code is in [permissions-patterns.swift](permissions-patterns.swift).

## 2. Messages (chat.db)

### 2.1 Locking

`chat.db` is a live SQLite database. Do NOT open it directly — Messages.app holds a WAL lock. Copy it first, along with the sidecar WAL/SHM files if present, then open the copy read-only:

```swift
let src = URL.homeDirectory.appending(path: "Library/Messages/chat.db")
let dst = FileManager.default.temporaryDirectory.appending(path: "chat-\(UUID().uuidString).db")
try FileManager.default.copyItem(at: src, to: dst)
// then open `dst` with SQLITE_OPEN_READONLY
```

Copy `chat.db-shm` and `chat.db-wal` alongside. Without them, recent messages (the last few hundred, still in the WAL) are missing from the read. SPEC §4.1 lists this as a required test case.

### 2.2 Schema subset we care about

`message`: one row per message.

- `rowid` INTEGER PK
- `guid` TEXT — stable message id; persists across Messages-in-iCloud rebuilds
- `text` TEXT — plain body; nullable for modern attachment-only or tapback rows
- `attributedBody` BLOB — `NSKeyedArchive` of `NSMutableAttributedString`; holds text when `text` is NULL (iOS 16+ writes here for messages with effects/reactions)
- `handle_id` INTEGER → `handle.rowid`
- `is_from_me` INTEGER 0/1
- `date` INTEGER — **Mac absolute time, nanoseconds** since 2001-01-01 UTC
- `service` TEXT — `iMessage` or `SMS`
- `expressive_send_style_id` TEXT — non-NULL for message-effect echoes; filter out

`chat`: `rowid`, `chat_identifier`, `display_name`.

`chat_message_join`: many-to-many `(chat_id, message_id)`.

`handle`: `rowid`, `id` (phone/email), `service`.

### 2.3 The single query that matters

Extract only **outbound** messages (we want the user's voice, not their contacts'):

```sql
SELECT
  m.guid,
  COALESCE(m.text, kiln_extract_attributedbody(m.attributedBody)) AS body,
  m.date / 1000000000 + strftime('%s', '2001-01-01') AS unix_ts,
  c.chat_identifier, c.display_name
FROM message m
JOIN chat_message_join cmj ON cmj.message_id = m.rowid
JOIN chat c                ON c.rowid       = cmj.chat_id
WHERE m.is_from_me = 1
  AND COALESCE(m.text, m.attributedBody) IS NOT NULL
  AND length(COALESCE(m.text, '')) > 0
ORDER BY m.date ASC;
```

`kiln_extract_attributedbody` is a user-defined function we register at SQLite open time — its body decodes `NSKeyedArchiver` and returns the embedded `NSString`. Implementation in [permissions-patterns.swift](permissions-patterns.swift) §4. Without it, ~30% of recent messages come back as empty strings.

See [chat-db-schema.sql](chat-db-schema.sql) for the canonical query including reaction filters, length clamps, and pre-2001 corruption guards.

### 2.4 Filter heuristics (apply in SQL, not Swift)

- Skip reactions: `text LIKE 'Liked "%'` or `'Loved "%'`, `'Laughed at "%'`, `'Emphasized "%'`, `'Questioned "%'`, `'Disliked "%'`, `'Removed a % reaction %'`.
- Skip message-effect echoes: `expressive_send_style_id IS NOT NULL AND length(text) < 20`.
- Length floor: 6 chars (reject "ok", "lol").
- Length ceiling: 4 000 chars (SPEC §1.2).

### 2.5 Date arithmetic

`m.date` is nanoseconds since 2001-01-01 UTC on iOS 13+ (seconds before that). Normalize once with `m.date / 1e9 + strftime('%s', '2001-01-01')`. Rows with `unix_ts < 978307200` are corrupt — skip, don't fail.

## 3. Apple Notes — AppleScript is the only sane path

The `NoteStore.sqlite` store is encrypted per-account on iOS 14+ and structurally inconsistent on macOS. Export via AppleScript is the only reliable path. First call prompts the user to grant Automation → Notes; after grant, subsequent runs are silent.

See [apple-notes-export.applescript](apple-notes-export.applescript) for the full loop. Gotchas:

- `body` returns **HTML**, not plain text. Strip with `NSAttributedString(data:options:[.documentType: .html])` **on the Swift side**, never inside AppleScript.
- First enumeration of iCloud-backed Notes can take 30+ s. Wrap `osascript` in a `Task` with a 120 s timeout; show a progress UI.
- Locked notes expose `password protected = true`. Filter with `every note whose password protected is false` — AppleScript can't unlock them, and the body reads as `"🔒 Locked"` garbage otherwise.
- Embedded images/PDFs add seconds per note and are useless for training. Strip `<img>`, `<object>`, `<embed>` tags before token counting.

## 4. Drafts — straightforward SQLite

Drafts stores documents in a plain SQLite at:

```
~/Library/Group Containers/group.com.agiletortoise.Drafts-macOS/Documents/drafts.sqlite
```

User must open the `Documents/` folder once via `NSOpenPanel`. Subsequent reads succeed via security-scoped bookmark (pattern in [permissions-patterns.swift](permissions-patterns.swift) §2).

Schema is stable: table `Draft` with columns `uuid TEXT`, `content TEXT`, `created_at REAL`, `modified_at REAL`, `flagged INTEGER`, `archived INTEGER`.

```sql
SELECT uuid, content, created_at, modified_at
FROM Draft
WHERE content IS NOT NULL AND length(content) > 0
  AND archived = 0
ORDER BY modified_at DESC;
```

Plain text already — no HTML, no BLOB. Fast path.

## 5. Obsidian — vault detection and frontmatter

User drops a vault root onto Kiln. Flow:

1. Detect whether it's a vault: `.obsidian/` subdirectory is the marker.
2. Enumerate all `.md` files recursively.
3. Strip YAML frontmatter (delimiters `^---\n` / `\n---\n`).
4. Strip Obsidian syntax: `[[wikilink]]` → `wikilink`, `![[embed]]` → remove, `^blockref` lines → remove, `%%comment%%` → remove.
5. Skip `.obsidian/`, `.trash/`, and `templates/` if conventionally named.

### 5.1 Frontmatter parsing

Frontmatter is authoritative metadata and the main way to filter out note templates:

```yaml
---
type: template
private: true
---
```

Rule: if frontmatter has `type: template` OR `private: true`, skip the note. Use `Yams` to parse (allowed dep for config — see SPEC §4.3). If Yams isn't available for some reason, fall back to line-by-line key/value splitting; frontmatter is usually shallow.

### 5.2 Block references

Drop `^blockid` lines entirely — they're anchors, not content. Strip with regex `/^\s*\^[a-zA-Z0-9]+\s*$/m`.

## 6. Swift plumbing — three patterns to copy from

All three are in [permissions-patterns.swift](permissions-patterns.swift). Summary of when to use each:

| Pattern                                 | When                                                                                          |
|-----------------------------------------|-----------------------------------------------------------------------------------------------|
| `NSOpenPanel` with `canChooseDirectories = true` | User picks a folder once (folder drop, Drafts container, Obsidian root).            |
| Security-scoped bookmark                | Remember the grant across launches so the user doesn't re-pick.                               |
| Full Disk Access probe (`open(TCC.db)`) | Detect FDA state **before** attempting `chat.db` copy; avoid cryptic "Operation not permitted". |

### 6.1 Detecting Full Disk Access

There's no public API to query TCC. The canonical probe is to try to open `/Library/Application Support/com.apple.TCC/TCC.db` read-only; if `open()` returns a valid fd, FDA is granted. If it returns `EPERM`, it isn't. Show a one-screen explanation and a button that opens System Settings at the correct pane:

```swift
NSWorkspace.shared.open(
  URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
)
```

### 6.2 Security-scoped bookmarks

After `NSOpenPanel` returns a URL, serialize a bookmark with `.withSecurityScope`, write to `~/.kiln/bookmarks/<key>.bookmark`. On relaunch, resolve with the same option. If `isStale == true`, re-prompt. This is common after macOS minor upgrades.

## 7. Known gotchas

- **TCC permission resets after macOS minor upgrade.** Any `.x.x` update can silently revoke FDA. Probe at launch; never fail silently on `chat.db` open.
- **Messages in iCloud.** When the user signs out/back in, `chat.db` rebuilds and `rowid` values change. Persist `guid` for stable dedup across ingests.
- **Emoji in `attributedBody`.** Rare rows encode emoji as `NSTextAttachment`. Decoder must fall through to `nil` on attachment-only messages and skip the row, not crash.
- **Notes attachments.** Rich-text notes embed `applewebdata://` URLs for images; these die when the note is shared. Strip with a URL-scheme allowlist before persisting extracted text.
- **Drafts "archived" flag.** Users dump many drafts into Archive. Default `archived = 0` but expose a UI toggle; some users flag-and-archive their best work.
- **Obsidian Markdown flavour.** Permits `==highlight==`, `%%comment%%`, LaTeX `$...$`. Drop `%%...%%` (author's private notes); keep highlights and math as plain text.
- **Locale in Notes/Messages.** Mixed-language content is common. Detect once with `NLLanguageRecognizer` per row; non-English rows are OK to include in training but should be flagged so the Dataset Doctor can warn if >20% of the corpus is non-English.

## 8. When to deviate

1. Log a row in `DECISIONS.md` with source name, mechanism, and reason.
2. Add a row to the SPEC.md source table.
3. Update this skill file in the same PR.

Never hard-code a new path or permission check inside ingest code without touching this file.
