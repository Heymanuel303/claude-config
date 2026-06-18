---
description: Write a detailed multi-phase implementation plan to docs/plans/{date}-{feature-name}/ based on the current conversation. A single workflow explores the repo and drafts every phase in parallel; each phase records whether /execute should run it solo or as a workflow.
model: opus
---

Generate a durable, executable plan from the in-flight conversation. Output goes to `docs/plans/{date}-{feature-name}/` (date-prefixed so `ls docs/plans/` sorts chronologically oldest→newest). Each phase file must stand alone — a fresh Claude session reading only that file plus the repo should be able to finish it end-to-end.

You orchestrate. A **single workflow** (the `Workflow` tool) does the heavy lifting: it fans out read-only explorers over the repo, then drafts every phase file in parallel from real paths/APIs. You confirm inputs, decide the phase list + per-phase execution strategy, run the workflow, then write the overview and stitch everything together.

Discover the project's commands and structure first: read any agent guide (CLAUDE.md, AGENTS.md, .cursor/rules, README, CONTRIBUTING) and whatever build manifests are present (for example package.json scripts, Makefile, Cargo.toml, pyproject.toml / tox.ini / noxfile, go.mod, build.gradle / pom.xml, Gemfile, composer.json, melos.yaml / pubspec.yaml) to learn how THIS project lints, formats, tests, builds and generates code, and how its modules/packages/layers are laid out. Never assume a toolchain or directory layout — use what the repo actually declares.

## Inputs to confirm before writing

Pull from conversation history first. If any of these are missing or ambiguous, ask the user with `AskUserQuestion` before running the workflow. Do not invent.

- **Feature name** — kebab-case descriptive slug; the on-disk folder name is `{date}-{feature-name}`
- **Goal / problem statement** — what changes when this lands
- **Scope** — which modules/packages/services/layers are touched
- **Out of scope** — explicit non-goals
- **Constraints** — perf, schema, backwards-compat, deadlines
- **Acceptance criteria** — observable done-signals
- **Phase breakdown** — if user already sketched one; otherwise propose

Ask only what's actually unclear. One round of questions max, then proceed.

## Folder layout

```
docs/plans/{date}-{feature-name}/
  00-overview.md
  01-{phase-slug}.md
  02-{phase-slug}.md
  ...
```

First capture today's date in the main session with `date +%F` (this gives `{date}` as `YYYY-MM-DD` — the workflow script can't compute it, see below), then form the folder name `docs/plans/{date}-{feature-name}` and `mkdir -p docs/plans/{date}-{feature-name}`.

## Decide the phase list AND each phase's execution strategy

Before running the workflow, draft the ordered phase list (slug + one-line objective each, using the sizing heuristics below). For **each phase**, also decide how `/execute` should later run it — this gets baked into the phase file as `**Execution:** solo` or `**Execution:** workflow`:

- **`solo`** — a focused change a single fresh `/execute` session can finish directly. Default. Use when the phase touches a handful of files in one area (one screen/flow, one module, a migration + its consuming code, a contained refactor).
- **`workflow`** — the phase has broad, parallelizable, or high-assurance surface that benefits from fan-out. Use when ANY of:
  - **Wide independent sweep** — the same mechanical change across many files/call-sites (rename of a widely-used symbol, codemod-style edits).
  - **Multi-layer in one phase** — independent work across the project's discovered layers (e.g. data + api + ui + shared libs) that can proceed in parallel.
  - **High-assurance** — security-sensitive, schema/migration correctness, or money/auth paths where adversarial verification of the result is worth the spend.
  - **Discovery-then-act** — the exact set of edit sites isn't known until the repo is searched (find all usages → transform each).

  A `workflow` phase MUST include an `## Execution strategy` section (template below) telling `/execute` what to fan out, what to verify, and whether worktree isolation is needed.

When unsure, prefer `solo` — workflows cost tokens; only mark `workflow` when the fan-out clearly pays for itself.

## Run the planning workflow

Author **one** `Workflow` call inline. It runs two phases: `Explore` (read-only fan-out, one explorer per planned phase) then `Draft` (one writer per planned phase, fed its explorer's findings). The workflow agents start cold — interpolate every confirmed input into the script as string literals; never write "see conversation".

The script **cannot** call `Date.now()` / `new Date()` (they throw in workflow scripts). Interpolate the `date +%F` value you captured earlier as a literal when authoring the script — bake it into the `FEATURE` constant so the folder carries the date prefix. Do not compute the date inside the script.

Use this script template, filling the placeholders from the confirmed inputs and your phase list:

```js
export const meta = {
  name: 'plan-{feature-name}',
  description: 'Explore the repo and draft phase files for {feature-name}',
  phases: [
    { title: 'Explore', detail: 'read-only sweep of each phase\'s touched area' },
    { title: 'Draft', detail: 'one writer per phase' },
  ],
}

const FEATURE = '{date}-{feature-name}'  // date from `date +%F`, interpolated as a literal — NEVER new Date() here
const GOAL = '{1-sentence goal}'
const SCOPE = '{modules/packages touched}'
const CONSTRAINTS = '{perf / schema / compat / deadline}'

// One entry per planned phase. exec is the strategy you decided above.
const PHASES = [
  { n: 1, slug: '{slug}', objective: '{one sentence}', dependsOn: 'none',          exec: 'solo' },
  { n: 2, slug: '{slug}', objective: '{one sentence}', dependsOn: '01-{slug}.md',  exec: 'workflow' },
  // ...
]

const EXPLORE_SCHEMA = {
  type: 'object',
  required: ['files', 'apis', 'patterns', 'gotchas'],
  properties: {
    files:    { type: 'array', items: { type: 'string' } },  // real paths to touch
    apis:     { type: 'array', items: { type: 'string' } },  // real signatures/symbols involved
    patterns: { type: 'array', items: { type: 'string' } },  // existing conventions to follow
    gotchas:  { type: 'array', items: { type: 'string' } },  // risks, edge cases, ordering constraints
  },
}

const pad = n => String(n).padStart(2, '0')

phase('Explore')
const findings = await parallel(PHASES.map(p => () =>
  agent(
    `Read-only exploration for phase ${p.n} of "${FEATURE}".\n` +
    `Feature goal: ${GOAL}\nScope: ${SCOPE}\nThis phase's objective: ${p.objective}\n\n` +
    `Find the REAL files this phase must touch (exact paths), the actual APIs/signatures/symbols involved, ` +
    `existing patterns to mirror, and any gotchas or ordering constraints. Return concrete paths and symbols — no guesses.`,
    { label: `explore:${p.slug}`, phase: 'Explore', agentType: 'Explore', schema: EXPLORE_SCHEMA }
  )))

phase('Draft')
const drafts = await parallel(PHASES.map((p, i) => () =>
  agent(draftPrompt(p, findings[i]), { label: `draft:${p.slug}`, phase: 'Draft' })))

return { drafts }

// draftPrompt embeds the phase-file template (below) + the explorer's findings, and
// instructs the writer to Write docs/plans/${FEATURE}/${pad(p.n)}-${p.slug}.md then
// (FEATURE already carries the {date}- prefix, so the folder is dated)
// return "{path} — {1-line summary}". Include the `**Execution:** ${p.exec}` field, and
// for exec==='workflow' require the `## Execution strategy` section.
```

Construct `draftPrompt(p, finding)` so each writer:
1. Gets the cold-start preamble (feature, goal, scope, constraints, this phase's objective, dependsOn).
2. Gets its explorer's `files`/`apis`/`patterns`/`gotchas` so `Files to touch` and `Steps` are concrete and real.
3. Is told to Write exactly `docs/plans/{date}-{feature-name}/{NN}-{slug}.md` and nothing else, no editing existing code.
4. Embeds the phase-file template verbatim, including `**Execution:** {p.exec}` and — when `p.exec === 'workflow'` — the `## Execution strategy` section.

### Phase-file template (embed in each writer's prompt)

```markdown
# Phase {N}: {title}

**Plan:** [{feature-name}](00-overview.md)
**Depends on:** {previous phase file or "none"}
**Execution:** {solo | workflow}

## Context
{2–4 sentences so a cold session understands why this phase exists. One-line feature goal recap.}

## Objective
{One sentence — what this phase delivers.}

## Files to touch
- `path/to/file` — {what changes}

## Steps
1. {Concrete action — file + change}
2. ...

## Execution strategy        ← include ONLY when Execution is `workflow`
{What /execute should fan out and how to structure the workflow:}
- **Fan-out unit:** {one agent per file / per call-site / per layer / per dimension}
- **Shape:** {pipeline (independent items) | parallel barrier (need all results) | find→transform→verify}
- **Isolation:** {none — agents edit distinct files in the shared tree | worktree — agents would otherwise conflict}
- **Verify stage:** {what each item's verifier checks; adversarial if high-assurance}

## Verification
- {the project's lint/format command, discovered from the repo}
- {the project's test command (or scoped subset)}
- {manual UI check if applicable}

## Acceptance
- [ ] {phase-specific observable signal}
```

Closing instruction for every writer: *Leave changes uncommitted; the user commits manually. Do NOT push or open a PR. Do NOT write any file outside `docs/plans/{date}-{feature-name}/`. Do NOT edit existing code — this is planning only.*

## After the workflow returns

1. Verify each phase file exists at its expected path (the workflow result lists what was written).
2. **You** write `00-overview.md` (don't delegate — you have the holistic view):

```markdown
# {Feature title}

**Slug:** `{feature-name}` (folder: `docs/plans/{date}-{feature-name}/`)
**Created:** {YYYY-MM-DD}
**Status:** planned

## Goal
{1–3 sentences.}

## Scope
- {module/package}: {what changes}

## Out of scope
- {explicit non-goal}

## Constraints
- {perf / schema / compat / deadline}

## Acceptance criteria
- [ ] {observable signal}

## Phases
1. [01-{slug}](01-{slug}.md) — {one-line summary} · _{solo | workflow}_
2. [02-{slug}](02-{slug}.md) — {one-line summary} · _{solo | workflow}_

## Open questions
- {unresolved item, or empty}
```

Note each phase's execution strategy in the overview's phase list so the reader sees at a glance which phases fan out.

## Report

Surface: created file paths, the per-phase `solo`/`workflow` split, and any open questions left in the overview. No other closing chatter.

## Phase sizing heuristics

- Schema/migration → own phase, isolated from consuming code.
- **Schema/migration safety** — applies ONLY if the project has database migrations that deploy independently of the clients using them (e.g. a server/DB migrates while older clients are still live). When it applies: every migration must stay backward-compatible with currently-deployed clients — use **expand → migrate → contract** (parallel-change): ship additive / nullable / defaulted changes and new versioned functions first (this expand ships with the consuming release); defer destructive changes (DROP, rename, `NOT NULL`, tightened constraints or types, changed function signatures, access-control tightening) to a **separate, later** phase, after old clients have drained. Each planned migration should state its phase tag (`expand`/`contract`) in the phase's Steps, and the contract phase's `Depends on` / Acceptance should record that the breaking-client floor is live. Migration phases are good `workflow` candidates when correctness verification is worth fanning out. If the project has no database, or deploys schema and clients atomically, this does not apply — skip it.
- New shared package code → phase before app code that consumes it.
- **Respect the existing module/package boundaries and placement conventions of the project.** Place new code where the repo's existing structure dictates (mirror how comparable code is already organized — shared vs. app-specific, per-module subfolders, etc.). Writer prompts run cold, so interpolate the relevant placement convention into every draft prompt for phases touching shared/multi-module code.
- UI work → group by screen/flow, not by widget.
- Tests live in the phase that adds the code they cover — no trailing "add tests" phase.
- Each phase ~1–4 hours of focused work, independently verifiable, ends at a green verification.

## Don'ts

- Don't write a plan for trivial work (single-file edit, rename, one-line fix) — skip the workflow entirely and tell the user it's not plan-worthy.
- Don't reference conversation context inside phase files or workflow prompts — both run cold.
- Don't add a "review" or "polish" phase — fold into prior phase's acceptance.
- Don't ask follow-ups that don't change plan structure.
- Don't let the workflow write outside `docs/plans/{date}-{feature-name}/`.
- Don't mark a phase `workflow` just because it's large — mark it `workflow` only when the fan-out (sweep / multi-layer / high-assurance / discovery) genuinely pays off.

## Output style

- Brief. No preamble, no recap, no chatter.
- Bullet points over prose.
- Lead with the answer; cut everything that isn't actionable.
- Questions (if any): one line each, batched in a single `AskUserQuestion`.
- No closing summary beyond the file-paths + execution-split report.
