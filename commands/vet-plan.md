---
description: Fact-check a generated plan in docs/plans/ by running a workflow that fans out one read-only agent per phase. Each phase is verified against the real repo — paths, APIs, dependencies, scope — and reports what needs changing before execution. Read-only — no edits.
model: opus
---

Vet a **not-yet-executed plan** in `docs/plans/` (or the dir in `$ARGUMENTS`) before anyone runs `/execute` on it. Run a **single workflow** (the `Workflow` tool) that fans out one read-only `Explore` agent per phase — each fact-checks its phase against the actual repo in parallel and returns structured findings — then synthesize a verdict on what needs to change.

You orchestrate. The workflow does the parallel fan-out; you resolve the plan, run the workflow, then synthesize the consolidated verdict from its structured results.

This is NOT a code review (`/review` does that on committed work). Nothing is implemented yet. You are checking that the **plan is correct, executable, and grounded in reality** — that every file path exists (or is correctly marked new), every referenced API/symbol/data object is real, dependencies between phases hold, and no phase is built on a wrong assumption.

## Resolve the plan

1. If `$ARGUMENTS` names a plan dir → use `docs/plans/$ARGUMENTS/` (strip a leading `@`).
2. Else → `ls docs/plans/*/`. Folders are date-prefixed (`{YYYY-MM-DD}-{feature-name}/`), so a sorted listing runs oldest→newest — pick the **last (chronologically-newest) entry** deterministically rather than guessing by mtime. If multiple are plausible, `AskUserQuestion` once.
3. Read `00-overview.md` to extract the phase list + goal + constraints + acceptance criteria.

If the plan dir doesn't exist or has no phase files → `AskUserQuestion` once with concrete options. Don't run the workflow blind.

State the resolved plan in one line before running the workflow: plan path + phase count.

## Pre-flight (you, not the workflow)

The workflow agents start cold — gather the shared context here and interpolate every fact into the script as string literals; never write "see conversation".

- `ls docs/plans/<plan-slug>/` — enumerate phase files. `<plan-slug>` is the full dated folder name `{YYYY-MM-DD}-{feature-name}`.
- Read `00-overview.md` fully — goal, scope, out-of-scope, constraints, acceptance criteria, phase ordering + dependencies.
- Discover the project's commands and structure first: read any agent guide (CLAUDE.md, AGENTS.md, .cursor/rules, README, CONTRIBUTING) and whatever build manifests are present (for example package.json scripts, Makefile, Cargo.toml, pyproject.toml / tox.ini / noxfile, go.mod, build.gradle / pom.xml, Gemfile, composer.json, melos.yaml / pubspec.yaml) to learn how THIS project lints, formats, tests, builds and generates code, and how its modules/packages/layers are laid out. Never assume a toolchain or directory layout — use what the repo actually declares.
- Note the dependency chain (which phase depends on which) so each checker knows what its phase assumes already exists.

Interpolate the overview's goal + constraints + project facts + each phase's stated dependencies into the workflow prompts so the checkers don't re-derive them.

## Run the vetting workflow

Author **one** `Workflow` call inline. It runs a single phase that fans out one `Explore` agent per plan phase in parallel, each forced to return structured findings via schema. Interpolate the resolved plan slug, goal, constraints, project facts, and the `PHASES` array as literals.

Use this script template, filling the placeholders from the resolved plan:

```js
export const meta = {
  name: 'vet-{plan-slug}',
  description: 'Fact-check each phase of {plan-slug} against the real repo before execution',
  phases: [
    { title: 'Vet', detail: 'one read-only checker per phase, in parallel' },
  ],
}

const PLAN = '{docs/plans/YYYY-MM-DD-feature-name}'   // the dated plan folder
const GOAL = '{1-sentence goal from overview}'
const CONSTRAINTS = '{perf / schema / compat / deadline from overview}'
const PROJECT_FACTS = '{how this project lints/tests/builds/generates code + its module/package/layer layout, from pre-flight discovery}'

// One entry per phase, from the overview. dependsOn = the phases this one assumes already exist.
const PHASES = [
  { n: 1, slug: '{slug}', file: '{PLAN}/01-{slug}.md', dependsOn: 'none' },
  { n: 2, slug: '{slug}', file: '{PLAN}/02-{slug}.md', dependsOn: '01-{slug}.md' },
  // ...
]

const SAFETY = 'Schema/migration safety — applies ONLY if the project has database migrations that deploy independently of the clients using them (e.g. a server/DB migrates while older clients are still live). When it applies: every migration must stay backward-compatible with currently-deployed clients — use expand -> migrate -> contract (parallel-change): ship additive / nullable / defaulted changes and new versioned functions first; defer destructive changes (DROP, rename, NOT NULL, tightened constraints or types, changed function signatures, access-control tightening) to a LATER release, after old clients have drained. If the project has no database, or deploys schema and clients atomically, this does not apply — skip it.'

const VET_SCHEMA = {
  type: 'object',
  required: ['phase', 'verdict', 'findings', 'verifiedFine', 'openQuestions'],
  properties: {
    phase:   { type: 'integer' },
    verdict: { type: 'string', enum: ['READY', 'NEEDS-CHANGES', 'BLOCKED'] },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        required: ['label', 'section', 'evidence', 'suggestion'],
        properties: {
          label:      { type: 'string', enum: ['BROKEN', 'RISKY', 'MISSING', 'DEPENDENCY GAP'] },
          section:    { type: 'string' },  // phase-file section the finding is about
          evidence:   { type: 'string' },  // repo evidence: "path:line" or "grep found no X"
          suggestion: { type: 'string' },  // concrete suggested edit to the plan
        },
      },
    },
    verifiedFine:  { type: 'array', items: { type: 'string' } },  // what checked out
    openQuestions: { type: 'array', items: { type: 'string' } },  // unresolved read-only
  },
}

const vetPrompt = (p) =>
  `Fact-check phase ${p.n} of the plan at ${PLAN}/ against the REAL repo. NOTHING in this plan has been implemented yet — you are verifying the plan is correct and executable BEFORE anyone runs it.\n\n` +
  `Your phase file: ${p.file}\n\n` +
  `Plan goal: ${GOAL}\n` +
  `Constraints: ${CONSTRAINTS}\n` +
  `Project facts: ${PROJECT_FACTS}\n` +
  `This phase depends on: ${p.dependsOn} — assume their described end-state exists; do NOT re-check them.\n\n` +
  `Approach:\n` +
  `1. Read your phase file fully — understand its Objective, "Files to touch", "Steps", "Verification", "Acceptance".\n` +
  `2. For EVERY claim the phase makes, verify it against the repo as it exists today:\n` +
  `   - Files to touch: does each path exist? If the phase treats it as existing, confirm it does. If it should be new, confirm it doesn't already exist (and that its parent dir/module/package is right).\n` +
  `   - APIs / methods / classes / symbols referenced: grep and confirm they exist with the signature the phase assumes (functions, types, components, config keys — whatever the phase names). Follow the project's existing conventions; do not impose ones the repo doesn't use.\n` +
  `   - Data/schema objects: tables/columns/queries/stored procedures/migrations the phase reads or writes — confirm they exist (or are created by an earlier phase you depend on). If the project has a database and a way to inspect it (an MCP server, a CLI such as psql/mysql, etc.), use it; otherwise reason from the migration/schema files.\n` +
  `   - Verification commands: are they real commands this project actually defines (build/test/lint/codegen scripts in its manifests)?\n` +
  `3. Sanity-check the logic: do the Steps actually achieve the Objective? Are there missing steps, wrong ordering, or steps that contradict the constraints? Is anything out of this phase's scope leaking in?\n\n` +
  `${SAFETY}\n\n` +
  `Classify every finding as one of: BROKEN (factually wrong vs. the repo — path missing, signature differs, data object absent, command invalid; the phase will fail as written), RISKY (plausible but unverified, or likely to cause trouble — race, missing error path, untested edge), MISSING (a step/file/consideration the phase needs but omits to meet its Objective/Acceptance), DEPENDENCY GAP (this phase needs something a prior phase was supposed to produce but the plan never produces). Also record what checked out (verifiedFine) and anything you couldn't resolve read-only (openQuestions).\n\n` +
  `Set verdict = READY (no BROKEN/MISSING/DEPENDENCY GAP), NEEDS-CHANGES (has fixable findings), or BLOCKED (can't proceed). Ground EVERY finding in repo evidence (path:line or "grep found no X") — not vibes. Read-only: do NOT edit the plan or any code.`

phase('Vet')
const results = await parallel(PHASES.map(p => () =>
  agent(vetPrompt(p), { label: `vet:${p.slug}`, phase: 'Vet', agentType: 'Explore', schema: VET_SCHEMA })))

return PHASES.map((p, i) => ({ phase: p.n, slug: p.slug, ...(results[i] || { skipped: true }) }))
```

## Synthesis

When the workflow returns its structured results, write a single consolidated verdict (do NOT re-inspect the repo yourself — synthesize from the results):

1. **Scope** — plan slug, phase count, branch (one line).
2. **Overall verdict** — READY TO EXECUTE / NEEDS-CHANGES / BLOCKED. Lead with this. (BLOCKED if any phase is BLOCKED; NEEDS-CHANGES if any phase has BROKEN/MISSING/DEPENDENCY GAP findings; else READY.)
3. **Change list** — grouped by phase, only phases that need changes. Each item: label (BROKEN/RISKY/MISSING/DEPENDENCY GAP) + phase section + repo evidence + suggested edit to the plan. This is the actionable core — make it copy-pasteable into a plan revision.
4. **Cross-phase issues** — dependency gaps, ordering problems, or constraints violated across phases that no single checker owns (merge the `DEPENDENCY GAP` findings and reason across phases here).
5. **Verified fine** — short bullets per phase (from each result's `verifiedFine`), so the user knows what was actually validated.
6. **Open questions** — merge the `openQuestions` arrays; anything no checker could resolve read-only.
7. **Suggested next step** — e.g. "revise phases 2 and 4 per the change list, then re-run /vet-plan" or "plan is sound — run /execute phase 1".

If any phase came back null/skipped, say which and why.

## Rules

- **Plan, not code.** You vet the plan before execution. Nothing is implemented — don't look for it.
- **One workflow, parallel fan-out.** Don't spawn checkers one at a time — the workflow's `parallel()` runs all phase checkers concurrently. One checker per phase.
- **No edits.** Audit only. Revising the plan is a follow-up the user triggers (or a fresh `/plan` pass).
- **Ground every finding in repo evidence.** "Path doesn't exist", "grep found no such method", "table absent in schema" — not vibes. The schema requires an `evidence` field per finding.
- **Each checker owns one phase.** A checker assumes its declared dependency phases' end-state exists; it does not re-audit them.
- **BROKEN vs. RISKY discipline.** BROKEN = the phase will fail as written. Everything softer is RISKY/MISSING. Don't inflate.
- **Don't duplicate the checkers' work.** Synthesize from the structured results; don't re-grep what they covered.
- **One round of questions max** before running the workflow.

## Output style

- Brief. No preamble, no recap.
- Lead with the verdict.
- Bullets over prose.
- Phase section + repo evidence for every finding.
- No closing summary beyond the synthesis report.
