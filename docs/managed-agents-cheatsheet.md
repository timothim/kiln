# Claude Managed Agents — Operating Cheatsheet

Compiled 2026-04-23 from authoritative sources on `claude.com` and `platform.claude.com`. Research conducted for the Kiln hackathon Distillation Orchestrator (Best Use of Managed Agents submission). All URLs re-verified during compilation.

Scope: this is a working reference for designing + deploying Kiln's agent. It is not a substitute for the docs — when in doubt, re-fetch.

---

## 1. What Managed Agents are — and what makes them different

> "Claude Managed Agents let you run Claude agents on long-running, multi-step jobs in Anthropic-hosted environments… you hand off a job — building a corpus, running evals overnight, triaging a backlog — and Claude handles the machine, the retries, the file I/O, and the session state." — [claude.com/blog/claude-managed-agents](https://claude.com/blog/claude-managed-agents)

**Four core concepts** (from [/docs/en/managed-agents/overview](https://platform.claude.com/docs/en/managed-agents/overview)):

| Concept | What it is |
|---|---|
| **Agent** | A versioned config blob: model, system prompt, tools, MCP servers, skills, description. |
| **Environment** | A cloud container template: OS, packages, networking policy. |
| **Session** | A live instantiation of `agent × environment` with mounted resources (files, repos) and credentials (vaults). |
| **Events** | The timeline inside a session — user messages, agent messages, thinking, tool use, status changes, token usage. |

**Beta header** (required on every API call):

```
anthropic-beta: managed-agents-2026-04-01
```

Official SDKs bundle it automatically when you use the `beta.agents` / `beta.sessions` namespaces.

---

## 2. API surface and auth

- Base URL: `https://api.anthropic.com`
- Auth: `x-api-key: $ANTHROPIC_API_KEY` (standard org key — no separate grant).
- Content-Type: `application/json`
- Idempotency: `anthropic-idempotency-key: <uuid>` supported on POSTs to /agents, /environments, /sessions.

**Rate limits** (org-wide, from overview page):
- 300 creates/min (agents, environments, sessions combined)
- 600 reads/min

**SDKs** with first-class support (as of April 2026 announcement): Python, TypeScript, Java, Go, C#, PHP, Ruby. Plus the `ant` CLI — `brew install anthropics/tap/ant`.

---

## 3. Agent configuration

Endpoint: `POST /v1/agents` — [/docs/en/managed-agents/agent-setup](https://platform.claude.com/docs/en/managed-agents/agent-setup)

Body fields:

```jsonc
{
  "name": "distillation-orchestrator",        // required
  "model": "claude-opus-4-7",                 // required; 4.5+ supported
  "system": "You are …",                      // system prompt
  "tools": [
    {"type": "agent_toolset_20260401"},       // bash+read+write+edit+glob+grep+web_fetch+web_search
    // custom tools: {"type": "custom", "name": "...", "description": "...", "input_schema": {...}}
  ],
  "mcp_servers": [
    {"type": "url", "name": "github", "url": "https://api.githubcopilot.com/mcp/"}
  ],
  "skills": [
    {"type": "anthropic", "skill_id": "xlsx"},                          // Anthropic-hosted
    {"type": "custom", "skill_id": "skill_01…", "version": "v1"}        // org-uploaded
  ],
  "callable_agents": [                                                  // Research Preview, access-gated
    {"type": "agent", "id": "agnt_01…", "version": 3}
  ],
  "description": "…",
  "metadata": {"project": "kiln"}
}
```

**Versioning:** agents are immutable per-version. `PATCH /v1/agents/{id}` bumps the version; existing sessions keep the pinned version; new sessions default to latest unless you pin `agent_version`.

**Tool group:** `agent_toolset_20260401` exposes `bash`, `read_file`, `write_file`, `edit_file`, `glob`, `grep`, `web_fetch`, `web_search`. Individual tools can be disabled by listing only the ones you want (see [/docs/en/managed-agents/tools](https://platform.claude.com/docs/en/managed-agents/tools)).

---

## 4. Environments

Endpoint: `POST /v1/environments` — [/docs/en/managed-agents/environments](https://platform.claude.com/docs/en/managed-agents/environments)

```jsonc
{
  "name": "kiln-distillation-env",
  "base_image": "anthropic/ubuntu:latest",    // default — Ubuntu 22.04, Python 3.11, node 20
  "packages": {
    "apt":  ["curl", "jq"],
    "pip":  ["anthropic>=0.40.0", "jsonlines"],
    "npm":  []
  },
  "environment_variables": {
    "PYTHONUNBUFFERED": "1"
  },
  "network_policy": {
    "mode": "allowlist",                       // "open" | "allowlist" | "none"
    "allowed_hosts": ["api.anthropic.com", "api.github.com"]
  },
  "timeout_minutes": 60                        // hard wall-clock cap
}
```

Environments are also versioned. Key operational note: `network_policy.mode: "none"` still allows `api.anthropic.com` implicitly — the agent must be able to reach Claude.

---

## 5. Sessions

Endpoint: `POST /v1/sessions` — [/docs/en/managed-agents/sessions](https://platform.claude.com/docs/en/managed-agents/sessions)

```jsonc
{
  "agent_id":       "agnt_01…",
  "agent_version":  3,                         // optional; latest if omitted
  "environment_id": "env_01…",
  "vault_ids":      ["vault_01…"],             // secrets, see §9
  "resources": [
    {"type": "file", "file_id": "file_01…", "mount_path": "/workspace/input.jsonl"},
    {"type": "github_repository",
     "url": "https://github.com/timtvn/kiln",
     "mount_path": "/workspace/kiln",
     "authorization_token": "ghp_…",          // PAT with repo scope
     "branch": "managed-agent/distillation-pilot"}
  ],
  "metadata": {"run": "quality-pilot-500"}
}
```

**Status lifecycle:** `idle → running → idle` per turn; terminal states `terminated`, `error`. Also `rescheduling` while the container is warming a fresh host.

**Streaming:** `GET /v1/sessions/{id}/stream` (SSE). Events are also persisted and can be paged via `GET /v1/sessions/{id}/events?limit=…`.

**Send input events:** `POST /v1/sessions/{id}/events` with a list of `user.*` events (`user.message`, `user.custom_tool_result`, `user.interrupt`, `user.tool_confirmation`).

**Archive vs delete:**
- `POST /v1/sessions/{id}/archive` — preserves history, tears down container.
- `DELETE /v1/sessions/{id}` — removes session + events + container.

**Interrupt** (for cancelling a run): send a `user.interrupt` event. The agent stops at its next tool call boundary.

---

## 6. Events and streaming

Source: [/docs/en/managed-agents/events-and-streaming](https://platform.claude.com/docs/en/managed-agents/events-and-streaming)

| Type | Direction | Meaning |
|---|---|---|
| `user.message` | in | Text prompt to the agent. |
| `user.custom_tool_result` | in | Return value for a pending custom tool. |
| `user.interrupt` | in | Cancel the current turn. |
| `user.tool_confirmation` | in | Approve a tool use that was gated. |
| `agent.message` | out | Assistant text. |
| `agent.thinking` | out | Extended-thinking trace (if enabled). |
| `agent.tool_use` | out | Agent invoking a built-in or custom tool. |
| `agent.mcp_tool_use` | out | Agent invoking an MCP tool. |
| `session.status_running` / `session.status_idle` | out | Status changes. |
| `session.error` | out | Unrecoverable error. |
| `span.model_request_end` | out | Carries `model_usage.input_tokens` / `output_tokens` / `cache_*`. |

Python SDK streaming pattern:

```python
with client.beta.sessions.events.stream(session.id) as stream:
    client.beta.sessions.events.send(session.id, events=[{"type": "user.message", "content": "go"}])
    for ev in stream:
        match ev.type:
            case "agent.message":        handle_text(ev)
            case "agent.tool_use":       handle_tool(ev)
            case "span.model_request_end": track_usage(ev)
            case "session.status_idle":  break
            case "session.error":        raise RuntimeError(ev)
```

---

## 7. Files

Source: [/docs/en/managed-agents/files](https://platform.claude.com/docs/en/managed-agents/files)

- Upload: `POST /v1/files` (multipart). Returns `file_id`.
- Mount in session via `resources: [{type: "file", file_id, mount_path}]`.
- **Mounted files are read-only copies.** The agent cannot modify them.
- Max **100 files per session**.
- List files scoped to a session: `GET /v1/files?scope_id={session_id}` — returns files the agent **wrote** (via `write_file` tool) that were saved under `/workspace/outputs/` or similar.
- Download: `GET /v1/files/{file_id}/content` → raw bytes.

Session-scoped file retrieval is how we pull the labelled JSONL back out after the pilot.

---

## 8. GitHub repositories

Source: [/docs/en/managed-agents/github](https://platform.claude.com/docs/en/managed-agents/github)

```jsonc
{
  "type": "github_repository",
  "url": "https://github.com/timtvn/kiln",
  "mount_path": "/workspace/kiln",
  "authorization_token": "ghp_<pat>",
  "branch": "managed-agent/distillation-pilot",
  "depth": 1
}
```

- PAT scopes needed: `repo` (full) to both clone private + push. `public_repo` is insufficient for pushing to a private fork.
- The agent gets a normal git working copy — it can `git add / commit / push` via the `bash` tool.
- Token rotation: `PATCH /v1/sessions/{id}/resources` with `{resource_index: N, authorization_token: "<new>"}`.
- Only one `github_repository` resource per session is permitted at time of writing (April 2026).

---

## 9. Vaults (secrets & MCP auth)

Source: [/docs/en/managed-agents/mcp-connector](https://platform.claude.com/docs/en/managed-agents/mcp-connector)

- `POST /v1/vaults` creates a named secret store.
- Secrets are keyed by MCP server `name` on the agent.
- When a session is created with `vault_ids: [...]`, any MCP server whose `name` has a matching key receives its auth header from the vault.
- Vaults are org-scoped and never exposed in event payloads — redacted as `<redacted:vault>`.

We don't need vaults for the quality-classifier pilot — Claude is the only model called, and its API key is session-wide via `x-api-key`.

---

## 10. Skills

Source: [/docs/en/managed-agents/skills](https://platform.claude.com/docs/en/managed-agents/skills)

- **Anthropic-hosted skills:** `{type: "anthropic", skill_id: "xlsx" | "pdf" | ...}` — no upload needed.
- **Custom skills:** authored like Claude Code skills (a folder with `SKILL.md` + resources), zipped, uploaded via `POST /v1/skills`, referenced as `{type: "custom", skill_id, version}`.
- Max **20 skills per session**.
- Skills are loaded lazily by the model — declaring one is cheap; the skill folder is only materialized into the container if the agent decides to activate it.

**Kiln note:** our `distillation-pipeline` skill is a Claude Code skill, not a Managed Agents skill. For the pilot we inline its §3.2 rubric into the agent's system prompt. Post-pilot, if the rubric grows, we upload it as a custom Managed Agents skill.

---

## 11. Multi-agent (callable_agents)

Source: [/docs/en/managed-agents/multi-agent](https://platform.claude.com/docs/en/managed-agents/multi-agent)

- **Research Preview** — access is gated via an access-request form. Assume we don't have it unless we've checked.
- Calls are **one level deep** — a callable agent cannot itself call other callable agents.
- Callable agents get their own session + environment; the parent pays for both.

For the pilot we use a single agent. No subagents.

---

## 12. Observability & tracing

Source: [/docs/en/managed-agents/observability](https://platform.claude.com/docs/en/managed-agents/observability) (page title: "Session tracing")

- **Claude Console** has a per-session timeline view at `console.claude.com/sessions/{id}` — Developers and Admins only.
- This is what we screenshot for the judge submission.
- Token usage per turn is in `span.model_request_end.model_usage`: `input_tokens`, `output_tokens`, `cache_read_input_tokens`, `cache_creation_input_tokens`.
- Cost is not exposed directly per session — we aggregate tokens × published rates.
- Errors surface as `session.error` events with a `code` and `message`.

---

## 13. Pricing

Source: [claude.com/blog/claude-managed-agents](https://claude.com/blog/claude-managed-agents)

> "Managed Agents is billed at **$0.08 per session-hour** for the container, plus standard Claude token rates for every `messages` call the agent makes."

- Session-hour meter starts on `session.status_running` and stops on `session.status_idle` (per turn).
- A session that's been created but has no running turn is not billed on the container side.
- The per-hour rate is prorated to the second.

For our 500-sample pilot (rough math, before running): ~500 × (800 in + 80 out tokens) × Opus-4.7 rates ≈ $6–10 in tokens; ~30–45 min container ≈ $0.04–0.06 session-hour cost. Total pilot budget: **< $15** all-in.

---

## 14. `ant` CLI quick reference

Install: `brew install anthropics/tap/ant`
Auth: `ant auth login` (uses your console API key).

| Action | Command |
|---|---|
| Create an agent from JSON | `ant beta:agents create -f agent.json` |
| List agents | `ant beta:agents list` |
| Create an environment | `ant beta:envs create -f env.json` |
| Create a session | `ant beta:sessions create -f session.json` |
| Send a user message | `ant beta:sessions events send <id> --type user.message --content "…"` |
| Stream events | `ant beta:sessions events stream <id>` |
| List events (paginated) | `ant beta:sessions events list <id> --format jsonl` |
| Interrupt a session | `ant beta:sessions events send <id> --type user.interrupt` |
| Upload a file | `ant beta:files upload input.jsonl` |
| Download a session-scoped file | `ant beta:files download <file_id> -o out.jsonl` |
| Delete a session | `ant beta:sessions delete <id>` |

The CLI is a thin wrapper over REST — anything you can do with `curl` you can do with `ant`.

---

## 15. Kiln-specific design notes (carry into the plan)

- **The existing `managed-agents/corpus-builder/agent.yaml` uses a Kubernetes-style `apiVersion: claude.com/v1` schema that does not match the real Managed Agents API.** It also references non-existent CLI commands (`claude agents deploy`). Rewrite required.
- **Scope conflict:** `CLAUDE_USAGE.md §6.1` documents `corpus-builder` as the MCP-puller agent (Gmail/Notion/GitHub/Slack → JSONL). Repurposing that name for the Distillation Orchestrator collides with that charter. **Recommendation:** create a new directory `managed-agents/distillation-orchestrator/` and leave `corpus-builder` as-is (pending a separate charter update in CLAUDE_USAGE.md at the end of the sprint).
- **Sidecar-to-Opus concurrency cap:** our distillation SKILL.md mandates 20 in-flight requests. The agent runs turn-by-turn, so we enforce concurrency at the bash script level inside the container, not at the session level.
- **Write-back strategy:** mount the repo as a `github_repository` resource on the branch `managed-agent/distillation-pilot`; the agent commits + pushes on completion. This preserves the Console timeline for judges *and* leaves an audit trail in the repo.
- **Token budget cap:** we set a hard cost cap in the agent's bash script (reads `$BUDGET_USD` env var, aborts if exceeded), in addition to the environment `timeout_minutes` wall clock.

---

## 16. URLs cross-reference (all verified 2026-04-23)

- [claude.com/blog/claude-managed-agents](https://claude.com/blog/claude-managed-agents) — announcement
- [/docs/en/managed-agents/overview](https://platform.claude.com/docs/en/managed-agents/overview)
- [/docs/en/managed-agents/quickstart](https://platform.claude.com/docs/en/managed-agents/quickstart)
- [/docs/en/managed-agents/agent-setup](https://platform.claude.com/docs/en/managed-agents/agent-setup)
- [/docs/en/managed-agents/environments](https://platform.claude.com/docs/en/managed-agents/environments)
- [/docs/en/managed-agents/sessions](https://platform.claude.com/docs/en/managed-agents/sessions)
- [/docs/en/managed-agents/events-and-streaming](https://platform.claude.com/docs/en/managed-agents/events-and-streaming)
- [/docs/en/managed-agents/tools](https://platform.claude.com/docs/en/managed-agents/tools)
- [/docs/en/managed-agents/skills](https://platform.claude.com/docs/en/managed-agents/skills)
- [/docs/en/managed-agents/files](https://platform.claude.com/docs/en/managed-agents/files)
- [/docs/en/managed-agents/github](https://platform.claude.com/docs/en/managed-agents/github)
- [/docs/en/managed-agents/mcp-connector](https://platform.claude.com/docs/en/managed-agents/mcp-connector)
- [/docs/en/managed-agents/observability](https://platform.claude.com/docs/en/managed-agents/observability)
- [/docs/en/managed-agents/multi-agent](https://platform.claude.com/docs/en/managed-agents/multi-agent)

Unrelated but checked for overlap:
- [claude.com/blog/the-advisor-strategy](https://claude.com/blog/the-advisor-strategy) — about the `advisor_20260301` tool on the Messages API, not Managed Agents.
