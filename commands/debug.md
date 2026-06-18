---
description: Fan out parallel investigation agents across layers and observability sources to root-cause a bug described in $ARGUMENTS or conversation history. Read-only. Produces a debug report.
model: opus
---

Investigate a bug. Goal is **root cause + evidence** across all layers of the stack. Output is a debug report the user can act on.

Discover the project's commands and structure first: read any agent guide (CLAUDE.md, AGENTS.md, .cursor/rules, README, CONTRIBUTING) and whatever build manifests are present (for example package.json scripts, Makefile, Cargo.toml, pyproject.toml / tox.ini / noxfile, go.mod, build.gradle / pom.xml, Gemfile, composer.json, melos.yaml / pubspec.yaml) to learn how THIS project lints, formats, tests, builds and generates code, and how its modules/packages/layers are laid out. Never assume a toolchain or directory layout — use what the repo actually declares.

## Resolve the bug

1. If `$ARGUMENTS` non-empty → that's the symptom.
2. Else → derive from conversation history.
3. If unclear (no repro, no error message, no surface) → `AskUserQuestion` once. Ask for: symptom (what's wrong), surface (which module/screen/endpoint), repro steps, recent error/log snippet if any, when it started.

State the resolved bug in one line + suspected scope before fanning out.

## Fan out (parallel, one message)

During pre-flight, enumerate the natural layers for THIS repo from its structure (e.g. frontend / backend / data or db / infra / shared libs / tests, OR the actual top-level modules) — include a database/migrations layer only if the repo has one. Spawn relevant agents in a **single message with multiple `Agent` tool calls**. Use `subagent_type: "Explore"` for code layers. Skip a layer when clearly irrelevant — say so.

### 1. Recent-changes agent
**Scope:** `git log --since='14 days ago' --oneline`, `git diff` on suspect paths, `git blame` for lines named in stack traces.
**Looking for:** recent commits touching the symptom's surface, suspicious refactors, migration ordering, version bumps. Bugs almost always live in recent diffs — start here.

### 2. Per-layer agents (one per discovered layer)
**Scope:** enumerate the project's modules / packages / services / layers from the repo structure (in a monorepo these are the top-level apps/packages/services; in a single-package repo they are the top-level source directories) and brief one agent per relevant layer, narrowed to the surface in the bug report. List the directories before briefing each agent — never assume a fixed set; it differs between branches and worktree checkouts.
**Looking for:** error handling that swallows failures, wrong state transitions, stale cache, race conditions, navigation/route bugs, gating blocking unexpectedly, optimistic-update divergence, wrong data mapping, error paths dropped, a caller that disagrees with the callee it invokes, broken parsing, regressed shared code. Follow the project's existing conventions when judging what's wrong.

### 3. Database agent (only if the repo has a database)
**Scope:** the project's schema/migration files plus, if available, a way to inspect the live DB — an MCP server, a CLI such as `psql`/`mysql`, or similar. Target the environment where the bug occurs, using whatever inspection tooling is available, and pass that into the agent's brief. If no inspection tooling exists, reason from the migration/schema files alone.
**Looking for:** access policies denying the operation, missing/wrong column, broken stored procedure/function, trigger side-effects, recent migration that changed shape, advisor/lint warnings. Pull DB logs if the bug touches data and logs are reachable.

### 4. Observability / error-tracking agent (only if the project uses Sentry or a similar tool)
**Scope:** the project's error-tracking/observability tool, if it has one (e.g. its MCP server, dashboard, or query API) — search issues/events for the symptom string and analyze the most relevant one.
**Looking for:** stack trace, frequency, first-seen release, affected users, breadcrumbs, related issues. Pull the issue ID + a representative event.

## Prompt template per agent

Each agent starts cold. Self-contained brief:

```
Investigate this bug in the {layer} of this project.

BUG: {one-line symptom}
SURFACE: {module/screen/endpoint}
REPRO: {steps, or "unknown"}
ERROR: {stack trace or log snippet, or "none provided"}

Scope strictly to: {paths or inspection target for this layer}
Do NOT widen scope — other agents cover other layers.

Hunt for the root cause. Look at:
- {layer-specific bullets above}

Report (under 400 words):
- Top 1–3 hypotheses, ranked by likelihood
- Evidence for each (file:line, log line, commit SHA, query result)
- Counter-evidence / what would rule each out
- Cross-references into other layers
- What you'd need to confirm (a log query, a repro, a question for the user)

Read-only. No edits. No speculation without a file or log to back it.
```

## Synthesis

When all agents return, write a debug report — terse, evidence-first:

```markdown
# Debug: {one-line symptom}

**Surface:** {module/screen/endpoint}
**Repro:** {steps or "not reproduced"}
**First observed:** {commit/release/date if known}

## Top hypothesis
{One sentence — most likely root cause.}

**Evidence:**
- `path:line` — {what's there}
- {log line, commit SHA, query result}

**To confirm:** {specific check}

## Alternate hypotheses
1. {hypothesis} — evidence: …, ruled out by: …
2. {hypothesis} — evidence: …, ruled out by: …

## Cross-layer trace
{data row → service/endpoint → client → screen — where the failure propagates}

## Suggested fix surface
- `path:line` — {what likely needs to change}

## Open questions
- {anything no agent could answer read-only}
```

If the user wants the report persisted, write to `docs/debug/{YYYY-MM-DD}-{slug}.md` — but only if asked. Default is in-conversation only.

## Rules

- **Parallel only.** All `Agent` calls in one message.
- **No edits.** Investigation only.
- **Evidence-bound.** Every hypothesis needs a file:line, a log line, or a commit. No vibes.
- **Don't duplicate agent work.** Trust their reports; synthesize, don't re-grep.
- **Skip irrelevant layers loudly.** Say which and why.
- **One round of questions max** before fanning out.

## Output style

- Brief. No preamble, no recap, no chatter.
- Bullet points over prose.
- Lead with the answer; cut everything that isn't actionable.
- Questions (if any): one line each, batched in a single `AskUserQuestion`.
- No closing summary beyond what this command's report format requires.
