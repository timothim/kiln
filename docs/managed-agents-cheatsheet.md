# Claude Managed Agents — Operating Cheatsheet

**Docs-grounded rewrite** — every non-trivial schema / endpoint / flag on this page is quoted verbatim from [platform.claude.com/docs/en/managed-agents/*](https://platform.claude.com/docs/en/managed-agents/overview) as fetched 2026-04-23. Items marked `⚠️ derived` are inferences required to close a doc gap; the reason is given inline. Earlier iterations of this doc contained fabricated fields (`base_image`, `environment_variables`, `network_policy.mode`, `timeout_minutes`, `agent_id` on session bodies, vault env-var injection, `github_repository` resource type) — all removed.

Scope: operating reference for the Kiln Distillation Orchestrator pilot (500-sample quality-label run, Opus 4.7 as teacher).

---

## 1. Four primitives

> "An agent is a reusable, versioned configuration that defines persona and capabilities. It bundles the model, system prompt, tools, MCP servers, and skills that shape how Claude behaves during a session." — [agent-setup](https://platform.claude.com/docs/en/managed-agents/agent-setup)
>
> "Environments define the container configuration where your agent runs. You create an environment once, then reference its ID each time you start a session. Multiple sessions can share the same environment, but each session gets its own isolated container instance." — [environments](https://platform.claude.com/docs/en/managed-agents/environments)
>
> "A session is a running agent instance within an environment. Each session references an agent and an environment (both created separately), and maintains conversation history across multiple interactions." — [sessions](https://platform.claude.com/docs/en/managed-agents/sessions)

| Primitive | Versioned? | Create endpoint |
|---|---|---|
| Agent | **Yes** (integer `version`, starts at 1, auto-increments on update) | `POST /v1/agents` |
| Environment | **No** ("Environments are not versioned.") | `POST /v1/environments` |
| Session | n/a (ephemeral; holds references) | `POST /v1/sessions` |
| Vault | n/a | `POST /v1/vaults` |

**Beta header — required on every call:**

```
anthropic-beta: managed-agents-2026-04-01
```

Official SDKs attach it automatically when you use the `client.beta.*` namespaces.

---

## 2. API surface

- Base URL: `https://api.anthropic.com`
- Auth: `x-api-key: $ANTHROPIC_API_KEY` (standard org key)
- Version: `anthropic-version: 2023-06-01`
- Content-Type: `application/json`
- SDKs with first-class support: Python, TypeScript, Java, Go, C#, PHP, Ruby
- CLI: `ant` — `brew install anthropics/tap/ant` then `xattr -d com.apple.quarantine "$(brew --prefix)/bin/ant"` on macOS. Auth: `ant auth login`.

---

## 3. Agent create — verbatim

Endpoint: `POST /v1/agents` — [agent-setup](https://platform.claude.com/docs/en/managed-agents/agent-setup)

```bash
curl -fsSL https://api.anthropic.com/v1/agents \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "anthropic-beta: managed-agents-2026-04-01" \
  -H "content-type: application/json" \
  -d '{
    "name": "Coding Assistant",
    "model": "claude-opus-4-7",
    "system": "You are a helpful coding agent.",
    "tools": [{"type": "agent_toolset_20260401"}]
  }'
```

### 3.1 All documented fields

| Field | Required | Notes |
|---|---|---|
| `name` | **yes** | Human-readable name. |
| `model` | **yes** | String (e.g. `"claude-opus-4-7"`) OR object `{"id": "claude-opus-4-6", "speed": "fast"}` for fast mode. "All Claude 4.5 and later models are supported." |
| `system` | no | System prompt. Clearable by passing `null`. |
| `tools` | no | Array. Combines pre-built, MCP, and custom tools. Array is fully replaced on update. |
| `mcp_servers` | no | Array; fully replaced on update. |
| `skills` | no | Array; max 20/session; fully replaced on update. |
| `callable_agents` | no | Research Preview (access-gated). One level deep. |
| `description` | no | Clearable by passing `null`. |
| `metadata` | no | Arbitrary k/v. Merged on update (empty string deletes a key). |

### 3.2 Update semantics (from [agent-setup](https://platform.claude.com/docs/en/managed-agents/agent-setup))

> "Omitted fields are preserved. … Array fields (tools, mcp_servers, skills, callable_agents) are fully replaced by the new array. To clear an array field entirely, pass null or an empty array. … Metadata is merged at the key level. … No-op detection. If the update produces no change relative to the current version, no new version is created and the existing version is returned."

Pass `version` to ensure you're updating from a known state (optimistic concurrency).

### 3.3 `ant` CLI form

```bash
ant beta:agents create \
  --name "Coding Assistant" \
  --model '{id: claude-opus-4-7}' \
  --system "You are a helpful coding agent." \
  --tool '{type: agent_toolset_20260401}'
```

---

## 4. Environment create — verbatim

Endpoint: `POST /v1/environments` — [environments](https://platform.claude.com/docs/en/managed-agents/environments)

```bash
curl -fsS https://api.anthropic.com/v1/environments \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "anthropic-beta: managed-agents-2026-04-01" \
  -H "content-type: application/json" \
  --data @- <<'EOF'
{
  "name": "data-analysis",
  "config": {
    "type": "cloud",
    "packages": {
      "pip": ["pandas", "numpy", "scikit-learn"],
      "npm": ["express"]
    },
    "networking": {"type": "unrestricted"}
  }
}
EOF
```

### 4.1 Top-level fields

- `name` — string, must be unique within the org + workspace.
- `config` — the only structural field. `config.type` must currently be `"cloud"`.

**There is no `base_image`, no `environment_variables`, no `timeout_minutes`, no top-level `network_policy`.** Any of those in older plans are fabricated.

### 4.2 Packages

> "When multiple package managers are specified, they run in alphabetical order (apt, cargo, gem, go, npm, pip). You can optionally pin specific versions; the default is latest."

Supported keys (each maps to a list of strings):

| Field | Manager | Example entry |
|---|---|---|
| `apt` | apt-get | `"ffmpeg"` |
| `cargo` | Rust | `"ripgrep@14.0.0"` |
| `gem` | Ruby | `"rails:7.1.0"` |
| `go` | Go modules | `"golang.org/x/tools/cmd/goimports@latest"` |
| `npm` | Node.js | `"express@4.18.0"` |
| `pip` | Python | `"pandas==2.2.0"` |

### 4.3 Networking

> "The `networking` field controls the container's outbound network access. It does not impact the `web_search` or `web_fetch` tools' allowed domains."

| Mode | Description |
|---|---|
| `unrestricted` | "Full outbound network access, except for a general safety blocklist. This is the default." |
| `limited` | "Restricts container network access to the `allowed_hosts` list. Further access is enabled via the `allow_package_managers` and `allow_mcp_servers` bool." |

For `limited`:
- `allowed_hosts` — list of domains. "These must be HTTPS-prefixed."
- `allow_mcp_servers` — bool, default `false`.
- `allow_package_managers` — bool, default `false`.

### 4.4 Environment variable injection — ❌ **NOT SUPPORTED**

The environment config has no field for setting container env vars. `ANTHROPIC_API_KEY` cannot be injected into the container via any documented mechanism. Plan accordingly: if the agent needs to call Claude, it must do so **via its own agent loop (it IS Opus)** — not by shelling out to the SDK.

### 4.5 Lifecycle

> "Environments are not versioned. If you frequently update your environments, you may want to log these updates on your side, to map environment state with sessions."

- Archive (read-only, existing sessions continue): `POST /v1/environments/{id}/archive`
- Delete (only if no sessions reference it): `DELETE /v1/environments/{id}`

### 4.6 `ant` CLI form

```bash
ant beta:environments create \
  --name "python-dev" \
  --config '{type: cloud, networking: {type: unrestricted}}'
```

---

## 5. Session create — verbatim

Endpoint: `POST /v1/sessions` — [sessions](https://platform.claude.com/docs/en/managed-agents/sessions)

```bash
curl -fsSL https://api.anthropic.com/v1/sessions \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "anthropic-beta: managed-agents-2026-04-01" \
  -H "content-type: application/json" \
  -d @- <<EOF
{
  "agent": "$AGENT_ID",
  "environment_id": "$ENVIRONMENT_ID"
}
EOF
```

### 5.1 Top-level fields

| Field | Required | Notes |
|---|---|---|
| `agent` | **yes** | String (= latest version) OR object `{"type": "agent", "id": "...", "version": N}` for pinning. **Not `agent_id`.** |
| `environment_id` | **yes** | Environment ID. |
| `vault_ids` | no | Array of vault IDs. Purpose: MCP credential injection (see §8). |
| `resources` | no | Array of mounted resources. |
| `metadata` | no | Arbitrary k/v. |

### 5.2 Resources — the only documented type is `file`

From [files](https://platform.claude.com/docs/en/managed-agents/files):

```json
{
  "resources": [
    {"type": "file", "file_id": "file_abc123", "mount_path": "/workspace/data.csv"}
  ]
}
```

- `mount_path` is optional; if omitted, the agent sees the file by its uploaded filename.
- "A maximum of 100 files is supported per session."
- **Mounted files are read-only copies.** "The agent can read them but cannot modify the original uploaded file. To work with modified versions, the agent writes to new paths within the container."

#### 5.2.1 `github_repository` resource type — ⚠️ not publicly documented

A `github_repository` variant appears in the Java SDK's `resources.list` response discriminator (`.asGitHubRepository()` on [files](https://platform.claude.com/docs/en/managed-agents/files) manage-section), but **no schema or example is documented** — [github-repositories](https://platform.claude.com/docs/en/managed-agents/github-repositories) returns 404. **Do not use for the pilot.**

### 5.3 Status lifecycle

From [sessions](https://platform.claude.com/docs/en/managed-agents/sessions):

| Status | Meaning |
|---|---|
| `idle` | "Agent is waiting for input, including user messages or tool confirmations. Sessions start in `idle`." |
| `running` | "Agent is actively executing." |
| `rescheduling` | "Transient error occurred, retrying automatically." |
| `terminated` | "Session has ended due to an unrecoverable error." |

> "Creating a session provisions the environment and agent but does not start any work. To delegate a task, send events to the session using a user event."

### 5.4 Send events (kick off work)

`POST /v1/sessions/{id}/events` — body has `events: [...]`. **`content` is an ARRAY of content blocks, not a string:**

```json
{
  "events": [
    {
      "type": "user.message",
      "content": [{"type": "text", "text": "List the files in the working directory."}]
    }
  ]
}
```

### 5.5 Interrupt / archive / delete

- Interrupt (stop the current turn): send a `user.interrupt` event.
- Archive: `POST /v1/sessions/{id}/archive` — "prevents new events from being sent while preserving its history".
- Delete: `DELETE /v1/sessions/{id}` — "A `running` session cannot be deleted; send an interrupt event if you need to delete it immediately."

### 5.6 `ant` CLI form (resources in YAML on stdin)

```bash
SESSION_ID=$(ant beta:sessions create \
  --agent "$AGENT_ID" \
  --environment-id "$ENVIRONMENT_ID" \
  --transform id --format yaml <<EOF
resources:
  - type: file
    file_id: $FILE_ID
    mount_path: /workspace/data.csv
EOF
)
```

---

## 6. Files (I/O across the session boundary)

Source: [files](https://platform.claude.com/docs/en/managed-agents/files)

### 6.1 Upload

```bash
FILE_ID=$(ant beta:files upload \
  --file data.csv \
  --transform id --format yaml)
```

Or curl:

```bash
file=$(curl --fail-with-body -sS -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "anthropic-beta: managed-agents-2026-04-01" \
  https://api.anthropic.com/v1/files \
  -F file=@data.csv)
```

### 6.2 List files scoped to a session

```bash
curl -fsSL "https://api.anthropic.com/v1/files?scope_id=sesn_abc123" \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "anthropic-beta: managed-agents-2026-04-01"
```

### 6.3 Download a file

```bash
curl -fsSL "https://api.anthropic.com/v1/files/$FILE_ID/content" \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "anthropic-beta: managed-agents-2026-04-01" \
  -o output.txt
```

### 6.4 Managing resources on a live session

- Add: `POST /v1/sessions/{id}/resources` — returns `{id: "sesrsc_01ABC..."}`.
- List: `GET /v1/sessions/{id}/resources`.
- Delete: `DELETE /v1/sessions/{id}/resources/{resource_id}`.

### 6.5 Recovering agent-generated output — ⚠️ derived

The files doc shows `scope_id=sesn_abc123` on `/v1/files` returns files associated with the session. It lists mounted input copies explicitly. It does **not** explicitly state whether files the agent writes inside the container (e.g. `/workspace/outputs/foo.jsonl`) are automatically scoped to the session and listable via the same endpoint.

**For the pilot we treat this as untested and use a guaranteed-to-work fallback: the agent emits its output as text in its final `agent.message`**, which we stream back and parse locally. If post-pilot testing confirms container-written files appear under `scope_id=sesn_...`, we switch to file-based retrieval for the full 10k run.

---

## 7. Events and streaming

Source: [events-and-streaming](https://platform.claude.com/docs/en/managed-agents/events-and-streaming)

### 7.1 Event types

| Direction | Type | Purpose |
|---|---|---|
| in | `user.message` | Text prompt. `content` is a list of content blocks. |
| in | `user.interrupt` | Cancel current turn. |
| in | `user.custom_tool_result` | Return value for a custom tool call. |
| in | `user.tool_confirmation` | Approve a gated tool use. |
| in | `user.define_outcome` | Define structured outcome for the session. |
| out | `agent.message` | Assistant text. |
| out | `agent.thinking` | Extended-thinking trace. |
| out | `agent.tool_use` | Agent invoking a built-in tool. |
| out | `agent.tool_result` | Tool output returned to the agent. |
| out | `agent.mcp_tool_use` | Agent invoking an MCP tool. |
| out | `agent.mcp_tool_result` | MCP tool output. |
| out | `agent.custom_tool_use` | Agent invoking a custom tool. |
| out | `span.model_request_end` | Carries `model_usage` with token counts. |

### 7.2 Stream vs. paginate

- Stream (SSE): `GET /v1/sessions/{id}/stream`
- Paginate: `GET /v1/sessions/{id}/events?limit=N&after=<sequence_number>`

Either way, the completion marker for "turn finished" is the session status transitioning back to `idle` — either via a status event or by re-reading session status (`GET /v1/sessions/{id}`).

---

## 8. Vaults — MCP credentials only

Source: [vaults](https://platform.claude.com/docs/en/managed-agents/vaults)

> "If your agent uses MCP tools that require authentication, pass `vault_ids` at session creation to reference a vault containing stored OAuth credentials. Anthropic manages token refresh on your behalf."

### 8.1 What a vault can hold

A vault stores **credentials bound to MCP server URLs**, not arbitrary secrets. Each credential has:
- `auth_type`: `mcp_oauth` (with refresh) **or** `static_bearer` (long-lived token).
- `mcp_server_url`: the MCP server the credential authenticates against.

Max 20 credentials per vault, one per `mcp_server_url`. Secrets are write-only after creation.

### 8.2 What a vault **cannot** do — ❌ scope-out

- Vaults cannot inject arbitrary environment variables into the container.
- There is **no mechanism** in any documented primitive for passing `ANTHROPIC_API_KEY` (or any non-MCP secret) into the container's shell env.
- Kiln's distillation pilot therefore does **not** use a vault — the managed agent itself is Opus 4.7 and does not need the SDK or an API key inside the container.

---

## 9. Tools — `agent_toolset_20260401`

Source: [tools](https://platform.claude.com/docs/en/managed-agents/tools)

Declaring `{"type": "agent_toolset_20260401"}` on the agent gives it:
- `bash` (run shell commands)
- `read` / `write` / `edit` (file I/O in the container)
- `glob` / `grep` (search)
- `web_fetch` / `web_search` (external content, independent of container networking)

Per-tool configs can be passed via `configs: {...}` or one `default_config: {...}` on the toolset entry. Default permission policy is `always_allow`.

---

## 10. Observability

Source: [observability](https://platform.claude.com/docs/en/managed-agents/observability) — page title *Session tracing*.

- Per-session timeline: `https://console.claude.com/sessions/{session_id}` (Developers and Admins only).
- This is what we screenshot for the judge submission.
- Token usage per model call: `span.model_request_end.model_usage` → `input_tokens`, `output_tokens`, `cache_read_input_tokens`, `cache_creation_input_tokens`.
- Cost is not reported directly — aggregate tokens × [published rates](https://www.anthropic.com/pricing) locally.
- Errors surface as `session` status transitions to `terminated` + any `session.error`-like events.

---

## 11. Pricing

From the Managed Agents announcement:

- **$0.08/session-hour** for the container.
- Standard Claude token rates apply to every model call the agent makes. Opus 4.7 as of 2026-04: $15/M input, $75/M output.
- Container meter: runs while the session is `running`; paused in `idle`. Prorated to the second.

---

## 12. Rate limits

Per-org, from the overview page:
- 300 create ops/min (agents + environments + sessions combined).
- 600 read ops/min.

Irrelevant for a single pilot session.

---

## 13. `ant` CLI quick reference

| Action | Command |
|---|---|
| Auth | `ant auth login` |
| Create agent | `ant beta:agents create --name N --model M --system S --tool T` |
| Update agent | `ant beta:agents update --agent-id ID --version V --system S` |
| List agent versions | `ant beta:agents:versions list --agent-id ID` |
| Archive agent | `ant beta:agents archive --agent-id ID` |
| Create environment | `ant beta:environments create --name N --config '{...}'` |
| Retrieve environment | `ant beta:environments retrieve --environment-id ID` |
| Archive environment | `ant beta:environments archive --environment-id ID` |
| Delete environment | `ant beta:environments delete --environment-id ID` |
| Create session | `ant beta:sessions create --agent ID --environment-id ID` (resources via `<<YAML` stdin) |
| Retrieve session | `ant beta:sessions retrieve --session-id ID` |
| Send user message | `ant beta:sessions:events send --session-id ID <<YAML ... YAML` |
| Interrupt session | `ant beta:sessions:events send --session-id ID --type user.interrupt` |
| List session resources | `ant beta:sessions:resources list --session-id ID` |
| Add session resource | `ant beta:sessions:resources create --session-id ID --type file --file-id FID` |
| Delete session resource | `ant beta:sessions:resources delete --session-id ID --resource-id RID` |
| Archive session | `ant beta:sessions archive --session-id ID` |
| Delete session | `ant beta:sessions delete --session-id ID` |
| Upload file | `ant beta:files upload --file PATH --transform id --format yaml` |
| List session-scoped files | `ant beta:files list --scope-id SID --beta managed-agents-2026-04-01` |
| Download file | `ant beta:files download --file-id FID --output PATH` |

`--transform id --format yaml` extracts just the `id` field — clean for shell variable capture.

---

## 14. URLs (verified 2026-04-23)

- [/overview](https://platform.claude.com/docs/en/managed-agents/overview)
- [/quickstart](https://platform.claude.com/docs/en/managed-agents/quickstart)
- [/agent-setup](https://platform.claude.com/docs/en/managed-agents/agent-setup)
- [/environments](https://platform.claude.com/docs/en/managed-agents/environments)
- [/sessions](https://platform.claude.com/docs/en/managed-agents/sessions)
- [/events-and-streaming](https://platform.claude.com/docs/en/managed-agents/events-and-streaming)
- [/tools](https://platform.claude.com/docs/en/managed-agents/tools)
- [/files](https://platform.claude.com/docs/en/managed-agents/files)
- [/vaults](https://platform.claude.com/docs/en/managed-agents/vaults)
- [/skills](https://platform.claude.com/docs/en/managed-agents/skills)
- [/mcp-connector](https://platform.claude.com/docs/en/managed-agents/mcp-connector)
- [/multi-agent](https://platform.claude.com/docs/en/managed-agents/multi-agent)
- [/observability](https://platform.claude.com/docs/en/managed-agents/observability)
- [/cloud-containers](https://platform.claude.com/docs/en/managed-agents/cloud-containers)

### Known 404 (for future reference — do not reference in live code)

- [/github-repositories](https://platform.claude.com/docs/en/managed-agents/github-repositories) → 404 as of 2026-04-23.

---

## 15. Kiln pilot design — grounded implications

1. **The managed agent IS Opus 4.7** — the agent loop itself does the labeling via `user.message` + its own inference. No Python subprocess, no in-container `anthropic` SDK call, no `ANTHROPIC_API_KEY` needed in the container.
2. **Input → file resource** — `pilot-500.jsonl` uploaded via Files API, mounted as `{type: "file", file_id, mount_path: "/workspace/input.jsonl"}`.
3. **Output → agent message text** — the agent emits the full `quality-labels.jsonl` contents as text in its final `agent.message`. The developer's monitor script parses and saves it locally. (We also have the agent `write` it to `/workspace/quality-labels.jsonl` as a belt-and-suspenders; if files scoped to `sesn_...` turn out to be listable post-run, we switch to that for the full 10k.)
4. **Git write-back happens on the developer's machine**, not from the container. After the session reaches `idle` with a complete run, `git checkout -b managed-agent/distillation-pilot && git add managed-agents/corpus-builder/runs/... && git commit && git push`.
5. **No vault needed** — per §8 we have no MCP servers and no non-MCP secret to inject.
6. **Environment is minimal** — `{name, config: {type: "cloud", networking: {type: "unrestricted"}}}`. No package pre-install required (the agent uses its `write` / `read` tools, which don't need pip deps). Networking is `unrestricted` because the agent's `bash` may be used for small utility work — tighten to `limited` after the pilot if audit required.
