---
description: Run a workflow that fans out reviewers across the project's layers to validate the commits that implemented a plan in docs/plans/. Read-only — no edits. Runs in parallel so the user can keep testing meanwhile.
model: fable
---

Review the **committed work** that implemented a plan in `docs/plans/` (or the scope in `$ARGUMENTS`) by running a **single workflow** (the `Workflow` tool) that fans out one read-only `Explore` reviewer per layer in parallel, each returning structured findings. The goal: confirm the commits actually deliver what the plan specified, end-to-end, before release. The user may be testing in parallel — deliver a crisp go / no-go report with concrete findings tied back to plan phases.

You orchestrate. The workflow does the parallel fan-out; you resolve the plan + commit range, discover the layers, run the workflow, then synthesize the consolidated report from its structured results.

## Resolve the plan + commit range

1. If `$ARGUMENTS` is a plan dir name → use `docs/plans/$ARGUMENTS/` (the dated folder name `{YYYY-MM-DD}-{feature-name}`).
2. Else → list `docs/plans/*/`. Folders are date-prefixed (`{YYYY-MM-DD}-{feature-name}/`), so a sorted listing runs oldest→newest; pick the **last (newest) entry** of `ls docs/plans/*/` deterministically rather than relying on mtime. If multiple are plausible (e.g. same date, ambiguous which one was meant), `AskUserQuestion` once.
3. Identify the commit range that implemented the plan:
   - Try `git log --all --oneline --grep="<plan-slug>"` and `git log --all --oneline -- docs/plans/<plan-slug>/` (where `<plan-slug>` is the full dated folder name `{YYYY-MM-DD}-{feature-name}`).
   - Look for commits whose subjects reference the plan slug or its phase numbers (e.g. `phase 1`, `phase 2`).
   - Fall back to `git log main..HEAD --oneline` if the branch is dedicated to the plan.
4. Confirm scope in one line: plan path + commit SHAs (or SHA range) + branch.

If the plan dir doesn't exist or no commits map to it → `AskUserQuestion` once with concrete options. Don't run the workflow blind.

## Pre-flight (you, not the workflow)

The workflow agents start cold — gather the shared context here and interpolate every fact into the script as string literals; never write "see conversation".

- Plan files: `ls docs/plans/<plan-slug>/` — read the overview/index file to extract phases + acceptance criteria.
- Commit list: `git log --oneline <range>` — the commits under review.
- Touched files per commit: `git show --stat <sha>` for each, or `git diff --stat <base>..<head>` for the whole range.
- **Discover the project's layers and structure.** Read any agent guide (CLAUDE.md, AGENTS.md, .cursor/rules, README, CONTRIBUTING) and whatever build manifests are present (for example package.json scripts, Makefile, Cargo.toml, pyproject.toml / tox.ini / noxfile, go.mod, build.gradle / pom.xml, Gemfile, composer.json, melos.yaml / pubspec.yaml) to learn how THIS project lints, formats, tests, builds and generates code, and how its modules/packages/layers are laid out. Never assume a toolchain or directory layout — use what the repo actually declares. Enumerate the **real** layers of this project: pick the natural ones (e.g. frontend / backend / data / infra / shared libs / tests, OR the actual top-level modules of a monorepo; in a single-package repo the "modules" are the top-level source directories). Include a database/migrations layer **only if the repo has one**.
- Group the touched files by those discovered layers, **dropping any layer the commit range doesn't touch** (note the skipped ones in the synthesis). The surviving layers become the `LAYERS` array in the script.

## Layers & scopes

Build one `LAYERS` entry per discovered layer that the commit range touches. For each, scope it strictly to that layer's paths and give it layer-appropriate checks. Common layer shapes (adapt to the actual repo — these are illustrative, not required):

### data / migrations (only if the repo has a database)
**Scope:** the project's migration/schema files in the commit range, plus any SQL referenced from server/backend code. If the project has a database **and** a way to inspect it (an MCP server, a CLI such as `psql`/`mysql`, etc.), use it to verify the live schema matches the migrations; otherwise reason from the migration/schema files.
**Checks:** migration idempotency, access-control (e.g. row-level) policies cover new tables/columns, indexes for new query patterns, no destructive drops without backfill, enum/type changes backwards-compatible, schema/migration safety (see Rules), plan's data-phase acceptance criteria met.

### backend / service
**Scope:** changed server/service/function files in the commit range (plus any shared backend helpers).
**Checks:** auth/access enforcement, input validation, error handling + response shapes, config/secret usage, external-dependency failure paths, logging, contract alignment with the client(s), plan's backend-phase acceptance criteria met.

### app / client
**Scope:** changed files under the app/client module(s) within the commit range (enumerated from the repo structure in pre-flight — never assume a fixed list).
**Checks:** state wired correctly, data access uses the right client/repository methods, routes/navigation reachable, loading/error/empty states, feature-flag/gating honored, no leftover debug code, copy/strings, accessibility regressions, test coverage for new logic, plan's app-phase acceptance criteria met.

### shared library
**Scope:** changed files under shared/library module(s) within the commit range (enumerated in pre-flight — trust the listing).
**Checks:** data shapes/DTOs match backend/data shapes, client contract + implementation in sync, breaking changes flagged for downstream consumers, shared components follow the project's existing conventions, generated/codegen artifacts up to date, no unused exports left after a refactor, plan's shared-phase acceptance criteria met.

## Run the review workflow

Author **one** `Workflow` call inline. It runs a single phase that fans out one `Explore` reviewer per layer in parallel, each forced to return structured findings via schema. Interpolate the resolved plan slug, commit range, branch, the commit list, and the `LAYERS` array (with each layer's scope, checks, relevant plan phases, and filtered touched files) as literals.

Every `agent()` call in the script must include `model: 'claude-fable-5'` in its options object — subagents spawned by the workflow do not inherit this command's own `model:` frontmatter.

Use this script template:

```js
export const meta = {
  name: 'review-{plan-slug}',
  description: 'Pre-release review of the commits implementing {plan-slug}, one reviewer per layer',
  phases: [
    { title: 'Review', detail: 'one read-only reviewer per touched layer, in parallel' },
  ],
}

const PLAN = '{docs/plans/YYYY-MM-DD-feature-name}'
const RANGE = '{commit SHA range, e.g. abc123..def456}'
const BRANCH = '{branch}'
const COMMITS = `{git log --oneline of the range}`

// One entry per discovered layer the commit range touches. Drop untouched layers.
const LAYERS = [
  {
    key: '{layer name, e.g. backend}',
    scope: '{exact paths this reviewer owns}',
    checks: '{layer-appropriate checks from "Layers & scopes" above}',
    phases: `{plan phase headings + acceptance criteria relevant to this layer}`,
    files: `{filtered touched-file list for this layer}`,
  },
  // ...
]

const SAFETY = 'Schema/migration safety — applies ONLY if the project has database migrations that deploy independently of the clients using them (e.g. a server/DB migrates while older clients are still live). When it applies: every migration must stay backward-compatible with currently-deployed clients — use expand -> migrate -> contract (parallel-change): ship additive / nullable / defaulted changes and new versioned functions first; defer destructive changes (DROP, rename, NOT NULL, tightened constraints or types, changed function signatures, access-control tightening) to a LATER release, after old clients have drained. If the project has no database, or deploys schema and clients atomically, this does not apply — skip it.'

const REVIEW_SCHEMA = {
  type: 'object',
  required: ['layer', 'verdict', 'coverage', 'blockers', 'nits', 'good', 'openQuestions'],
  properties: {
    layer:   { type: 'string' },
    verdict: { type: 'string', enum: ['GO', 'GO-WITH-CAVEATS', 'NO-GO'] },
    coverage: {  // one entry per acceptance criterion for this layer
      type: 'array',
      items: {
        type: 'object',
        required: ['criterion', 'status'],
        properties: {
          criterion: { type: 'string' },
          status:    { type: 'string', enum: ['met', 'partial', 'missing'] },
        },
      },
    },
    blockers: {  // must fix before release
      type: 'array',
      items: {
        type: 'object',
        required: ['location', 'problem', 'fix', 'sha'],
        properties: {
          location: { type: 'string' },  // path:line
          problem:  { type: 'string' },
          fix:      { type: 'string' },  // concrete suggested fix
          sha:      { type: 'string' },  // linked commit SHA
        },
      },
    },
    nits: {
      type: 'array',
      items: {
        type: 'object',
        required: ['location', 'note'],
        properties: { location: { type: 'string' }, note: { type: 'string' } },
      },
    },
    good:          { type: 'array', items: { type: 'string' } },  // what looks good
    openQuestions: { type: 'array', items: { type: 'string' } },  // unresolved read-only
  },
}

const reviewPrompt = (l) =>
  `Review the COMMITTED work that implemented the plan at ${PLAN}/ in the ${l.key} layer of this project. ` +
  `Follow the project's existing conventions — discover them from the agent guide (CLAUDE.md/AGENTS.md/README/CONTRIBUTING) and build manifests; do not assume a toolchain.\n\n` +
  `Plan phases relevant to your layer:\n${l.phases}\n\n` +
  `Commits under review (range ${RANGE} on ${BRANCH}):\n${COMMITS}\n\n` +
  `Touched files in your layer (within this commit range):\n${l.files}\n\n` +
  `Scope strictly to: ${l.scope}\nDo NOT read outside that scope — other reviewers cover other layers.\n\n` +
  `Approach:\n` +
  `1. Read the plan phase(s) for your layer first — understand the intended behavior + acceptance criteria.\n` +
  `2. Read the commits that touched your layer: git show <sha> -- <your paths> or git log -p ${RANGE} -- <your paths>.\n` +
  `3. Read the resulting code in its current state to confirm it survived rebases/squashes intact.\n\n` +
  `Check for:\n- ${l.checks}\n` +
  `- Plan adherence: every acceptance criterion for your layer must be visibly satisfied — report each as met/partial/missing in "coverage".\n` +
  `- Correctness vs. intent (do the commits actually achieve what the plan says?)\n` +
  `- Regressions (did adjacent code break?)\n` +
  `- Drift between plan and implementation (intentional deviations vs. accidental gaps)\n\n` +
  `${SAFETY}\n\n` +
  `Return a structured verdict for your layer: GO (no blockers), GO-WITH-CAVEATS (only nits), or NO-GO (has blockers). ` +
  `A blocker breaks the release; everything softer is a nit — don't inflate. Anchor every finding to a path:line AND the commit SHA that introduced it. ` +
  `Read-only: do NOT edit anything.`

phase('Review')
const results = await parallel(LAYERS.map(l => () =>
  agent(reviewPrompt(l), { label: `review:${l.key}`, phase: 'Review', agentType: 'Explore', model: 'claude-fable-5', schema: REVIEW_SCHEMA })))

return LAYERS.map((l, i) => ({ layer: l.key, ...(results[i] || { skipped: true }) }))
```

## Synthesis

When the workflow returns its structured results, write a single consolidated report (don't re-inspect the repo — synthesize from the results):

1. **Scope** — plan slug, commit range, branch (one line).
2. **Overall verdict** — GO / GO-with-caveats / NO-GO. Lead with this. (NO-GO if any layer is NO-GO or any blocker exists; GO-with-caveats if only nits/caveats; else GO.)
3. **Plan coverage matrix** — table or bullets: phase/criterion → status (met / partial / missing) → layer (merge each result's `coverage`).
4. **Blockers** — grouped, with `path:line` + suggested fix + commit SHA (merge each result's `blockers`). Empty list = say "none".
5. **Nits** — bulleted, brief (merge `nits`).
6. **Drift from plan** — intentional deviations worth recording vs. accidental gaps.
7. **What was verified** — short bullets per layer (from each result's `good` + coverage).
8. **Open questions** — merge the `openQuestions` arrays; anything no reviewer could answer read-only.
9. **Suggested next step** — e.g. "fix blockers then re-run /review", or "ship it".

If any layer came back null/skipped, say which and why.

## Rules

- **One workflow, parallel fan-out.** Don't spawn reviewers one at a time — the workflow's `parallel()` runs all layer reviewers concurrently. One reviewer per touched layer.
- **No edits.** Review only. Fixes are a follow-up task.
- **Anchor everything to the plan.** Every finding should reference either a plan acceptance criterion or a commit SHA (ideally both) — the schema requires a SHA per blocker.
- **Don't duplicate work.** Synthesize from the structured results; don't re-grep files the reviewers covered.
- **Skip empty layers loudly.** If the commit range touches zero files in a layer, drop it from `LAYERS` and say so in the synthesis.
- **Blocker vs. nit discipline.** A blocker breaks the release; everything else is a nit. Don't inflate.
- **One round of questions max** before running the workflow.
- **Schema/migration safety** — applies ONLY if the project has database migrations that deploy independently of the clients using them (e.g. a server/DB migrates while older clients are still live). When it applies: every migration must stay backward-compatible with currently-deployed clients — use expand → migrate → contract (parallel-change): ship additive / nullable / defaulted changes and new versioned functions first; defer destructive changes (DROP, rename, NOT NULL, tightened constraints or types, changed function signatures, access-control tightening) to a LATER release, after old clients have drained. If the project has no database, or deploys schema and clients atomically, this does not apply — skip it.

## Output style

- Brief. No preamble, no recap.
- Lead with the verdict.
- Bullets over prose.
- `path:line` + commit SHA for every finding.
- No closing summary beyond the synthesis report.
