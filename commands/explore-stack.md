---
description: Run a workflow that investigates a topic across the project's layers (data, services, app, shared) in parallel. Read-only — no edits. Produces a synthesized cross-layer map.
model: opus
---

Investigate `$ARGUMENTS` (or the topic in conversation history if no argument given) by running a **single workflow** (the `Workflow` tool) that fans out one read-only `Explore` agent per layer in parallel, each returning structured findings. Read-only research only. The goal is a synthesized cross-layer map of how the topic shows up everywhere.

You orchestrate. The workflow does the parallel fan-out; you resolve the question, run the workflow, then synthesize the consolidated report from its structured results.

## Resolve the question

1. If `$ARGUMENTS` is non-empty → that's the topic.
2. Else → derive the topic from conversation history.
3. If still unclear (no argument, conversation doesn't pin a target) → `AskUserQuestion` once with concrete option(s). Don't run the workflow blind.

State the resolved question in one line before running the workflow.

## Layers & scopes

Discover the layers first, then cover each one with its own explorer. Skip a layer only if clearly irrelevant — note the skip in the synthesis.

**Discover the project's commands and structure first:** read any agent guide (CLAUDE.md, AGENTS.md, .cursor/rules, README, CONTRIBUTING) and whatever build manifests are present (for example package.json scripts, Makefile, Cargo.toml, pyproject.toml / tox.ini / noxfile, go.mod, build.gradle / pom.xml, Gemfile, composer.json, melos.yaml / pubspec.yaml) to learn how THIS project lints, formats, tests, builds and generates code, and how its modules/packages/layers are laid out. Never assume a toolchain or directory layout — use what the repo actually declares.

From that inspection, pick the **natural layers for THIS repo** and build one explorer per layer. Use whatever decomposition fits — e.g. frontend / backend / data (db) / infra / shared libraries / tests, OR the actual top-level modules of a monorepo, OR (in a single-package repo) the top-level source directories. Include a **database/migrations** layer **only if the repo actually has one**.

Typical layer shapes (adapt to what you find):

### data / db (only if the repo has a database)
**Scope:** the migrations/schema directory plus SQL or queries referenced from the rest of the code. If the project has a database and a way to inspect it (an MCP server, or a CLI such as `psql`/`mysql`, etc.), use it for the live schema; otherwise reason from the migration/schema files.
**Looking for:** tables, columns, access policies, stored procedures/RPCs, triggers, indexes, enums tied to the topic. Note migration/schema filenames where things were introduced or changed.

### services / backend
**Scope:** the server-side / API / function code (whatever the repo uses — HTTP handlers, serverless functions, background jobs, shared server utilities).
**Looking for:** endpoints, request/response shapes, env vars/config, external API calls, auth checks, quota/rate logic, error paths tied to the topic.

### app / client
**Scope:** the application module(s). In a monorepo, enumerate them from the repo structure (e.g. the apps directory) — never assume a fixed list; the set differs between branches and worktrees. In a single-package repo, this is the top-level source directory.
**Looking for:** screens, routes, state holders, repositories, view-models, feature flags, navigation, entitlement/paywall gates tied to the topic. Note which module(s) actually use it.

### shared
**Scope:** the shared/library packages or modules (enumerate them from the repo structure).
**Looking for:** domain models, DTOs, result/error types, API-client methods, shared UI components, theme/design tokens, in-app-purchase plumbing, error-tracking/observability wiring tied to the topic.

## Run the exploration workflow

Author **one** `Workflow` call inline. It runs a single phase that fans out one `Explore` agent per layer in parallel, each forced to return structured findings via schema. The workflow agents start cold — interpolate the resolved topic into the script as a string literal; never write "see conversation".

**Pre-flight:** do the discovery above first, then build the `LAYERS` array from the real, current layers/modules of this checkout — enumerate any monorepo app/package directories and interpolate their actual names into the scopes below. The script template's placeholder layers must be replaced with what actually exists in this repo. Include the db layer only if the repo has a database.

Use this script template, filling `TOPIC` with the resolved question and `LAYERS` with the discovered layers:

```js
export const meta = {
  name: 'explore-stack-{short-topic-slug}',
  description: 'Cross-layer read-only investigation of "{topic}"',
  phases: [
    { title: 'Explore', detail: 'one read-only explorer per layer, in parallel' },
  ],
}

const TOPIC = '{resolved topic}'

// Build this from the discovered layers/modules of THIS repo (pre-flight).
// Include a db layer only if the repo has a database. Replace every placeholder.
const LAYERS = [
  {
    key: 'db', // include only if the repo has a database
    scope: 'the migrations/schema directory plus SQL/queries referenced from the rest of the code. If a DB inspection tool exists (an MCP server, or a CLI such as psql/mysql), use it for live schema; otherwise reason from the migration/schema files.',
    find: 'tables, columns, access policies, RPCs/stored procedures, triggers, indexes, enums tied to the topic; migration/schema filenames where things were introduced or changed.',
  },
  {
    key: 'services',
    scope: '{the real server-side / API / function module(s) for this repo}.',
    find: 'endpoints, request/response shapes, env vars/config, external API calls, auth checks, quota/rate logic, error paths tied to the topic.',
  },
  {
    key: 'app',
    scope: '{the real app/client module(s), e.g. the enumerated apps directory entries}.',
    find: 'screens, routes, state holders, repositories, view-models, feature flags, navigation, entitlement/paywall gates tied to the topic; which module(s) actually use it.',
  },
  {
    key: 'shared',
    scope: '{the real shared/library packages or modules for this repo}.',
    find: 'domain models, DTOs, result/error types, API-client methods, shared UI components, theme/design tokens, IAP plumbing, error-tracking wiring tied to the topic.',
  },
]

const FINDINGS_SCHEMA = {
  type: 'object',
  required: ['files', 'findings', 'crossRefs', 'gaps', 'openQuestions'],
  properties: {
    files:         { type: 'array', items: { type: 'string' } }, // key files as "path:line — what"
    findings:      { type: 'array', items: { type: 'string' } }, // concrete names: tables/functions/classes/routes/etc.
    crossRefs:     { type: 'array', items: { type: 'string' } }, // pointers into OTHER layers
    gaps:          { type: 'array', items: { type: 'string' } }, // missing/inconsistent things
    openQuestions: { type: 'array', items: { type: 'string' } }, // unanswerable with read-only access
  },
}

phase('Explore')
const results = await parallel(LAYERS.map(layer => () =>
  agent(
    `Investigate "${TOPIC}" in the ${layer.key} layer of this project.\n\n` +
    `Scope strictly to: ${layer.scope}\n` +
    `Do NOT read outside that scope — other agents cover other layers.\n\n` +
    `Find: ${layer.find}\n\n` +
    `Follow the project's existing conventions; do not assume a toolchain. ` +
    `Return concrete paths (with line numbers), real symbol names, cross-references that point into other layers, ` +
    `gaps/inconsistencies, and open questions. Read-only — do not edit anything.`,
    { label: `explore:${layer.key}`, phase: 'Explore', agentType: 'Explore', schema: FINDINGS_SCHEMA }
  )))

return LAYERS.map((layer, i) => ({ layer: layer.key, ...(results[i] || { skipped: true }) }))
```

## Synthesis

When the workflow returns its structured results, write a single consolidated report:

1. **Topic** — one line.
2. **Cross-layer map** — short table or bullets showing the topic's footprint per layer (data tables → services → app screens → shared types).
3. **Key file paths** — grouped by layer, with `path:line` references (from each result's `files`).
4. **Inconsistencies / gaps** — merge the `gaps` arrays; call out where layers disagree or coverage is missing.
5. **Open questions** — merge the `openQuestions` arrays; anything unanswerable with read-only access.

If any layer came back null/skipped, say which and why.

## Rules

- **One workflow, parallel fan-out.** Don't spawn `Explore` agents one at a time — the workflow's `parallel()` runs them concurrently.
- **No edits.** This command is exploration only. If the user wants changes, they'll follow up separately.
- **Don't duplicate work.** Don't grep/read the same files yourself that the workflow covered — synthesize from its structured results.
- **Skip irrelevant layers loudly.** If you drop a layer from `LAYERS`, say which and why in the synthesis.
- **One round of questions max** before running the workflow — don't interrogate the user.

## Output style

- Brief. No preamble, no recap, no chatter.
- Bullet points over prose.
- Lead with the answer; cut everything that isn't actionable.
- Questions (if any): one line each, batched in a single `AskUserQuestion`.
- No closing summary beyond the synthesis report.
