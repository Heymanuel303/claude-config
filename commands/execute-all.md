---
description: Execute an entire multi-phase plan in docs/plans/ end-to-end. A single background workflow walks the phases in order — execute → independent review → fix-loop → commit — spawning a fresh agent for each step so the orchestrator stays context-thin and only sees pass/fail verdicts. Stops on the first blocker.
model: fable
---

Drive a whole plan to completion, one phase at a time, autonomously. This is the orchestrator over the `/execute` command — `/execute` runs **one** phase; `/execute-all` runs **all** of them in dependency order, with an independent review + fix loop and a checkpoint commit per green phase.

Invoked like:

```
/execute-all docs/plans/{YYYY-MM-DD}-{feature}/00-overview.md
/execute-all @docs/plans/2026-06-09-entitlements-generic/00-overview.md
/execute-all                          # defaults to the newest plan
/execute-all from 2 docs/plans/{...}/00-overview.md   # resume at phase 2
```

## Design contract

The orchestrator (this main session) must stay **context-thin** — it never reads phase diffs, file contents, or review output directly. All heavy work happens inside agents; only compact structured verdicts (`{pass, blocking}`) bubble back up. This is what lets one session drive an entire plan without context exhaustion. You author **one** `Workflow` call that owns the sequential loop, then report its returned summary. Do not execute, review, or commit phases yourself in the main session.

Per phase the workflow runs these agent roles, each in its own fresh context:
- **execute** — does the phase cold, following the `/execute` contract. **This step's shape depends on the phase's `**Execution:**` field:**
  - `solo` → a **single** execute agent implements, verifies, and writes tests for the phase. (Solo phases are small by definition; one agent is right.)
  - `workflow` → the execute step itself **fans out at the orchestrator level** (it cannot nest its own workflow — see "Why fan-out lives here" below): a cheap **scout** agent partitions the phase into disjoint-file work units → a `parallel()` of **implementer** agents (each owns distinct files on the shared tree, no conflict) → one **reconcile** agent runs whole-tree verification and writes tests. This spreads the heavy implement context across many agents instead of one, so no single agent balloons.
  
  Either way, the execute step leaves the tree dirty (the commit step owns committing).
- **review** — *independent* of the executor. Re-reads the phase as a spec and audits the executor's actual diff against it. Returns a structured `{pass, blocking[]}` verdict. The orchestrator advances only on `pass: true`.
- **fix** — *independent*. Runs only when review fails; applies the review's `blocking` findings, then review runs again. Capped at 2 fix→review cycles.
- **commit** — commits the green phase with a Conventional Commits message (per the `/commit` command), creating a per-phase checkpoint.

Phases run **strictly sequentially** in `Depends on:` order — a later phase reads the tree the earlier ones built, so they can never overlap. The first phase that stays red after the fix loop **halts** the run; nothing is piled on top of broken work.

**Why fan-out lives at the orchestrator level (not inside the execute agent).** Workflow nesting is **one level only** — an `agent()` subagent cannot author its own `Workflow`, and subagents don't get the Agent/Task tool. So a `workflow`-marked phase can't fan out *from inside* its execute agent; if it tried, the call would throw and the phase would silently run as one bloated agent. The execute fan-out (scout → parallel implementers → reconcile) is therefore expressed directly in this orchestrator workflow's loop, which is legal and is what keeps any single agent from ballooning. **Implementers must own disjoint files** so they edit the shared tree without conflict (no worktree/merge step); if the scout can't partition the phase into disjoint-file units, it returns a single unit and the phase runs as one execute agent — correct, just not parallel.

## Resolve inputs (in this session, before the workflow)

1. **Overview path** — first path in `$ARGUMENTS` matching `docs/plans/*/00-overview.md` (strip a leading `@`). If none given, list `docs/plans/*/00-overview.md` and take the **chronologically-last** match (dated folders sort oldest→newest, so the last is newest).
2. **Start phase** — if `$ARGUMENTS` says `from {N}` / `resume {N}` / `start {N}`, begin at phase N (skip already-committed phases). Default: phase 1.
3. **Phase list** — read the overview, parse the ordered `## Phases` list into `{n, slug, file}` (resolve each file relative to the overview's folder; fallback `docs/plans/{feature}/{NN}-*.md`). For each phase file, read **only** its `**Execution:**` field (`solo` | `workflow`) — you need it to brief the execute agent; do not read the rest of the phase body in the main session.

If the overview is missing, names no phases, or any phase file can't be resolved → stop and ask with `AskUserQuestion`. Do NOT guess.

State what you resolved in one line before starting:
`Executing plan {feature} — phases {start}–{last} ({count} phases), checkpoint-commit per phase.`

## Pre-flight checks

Before launching, confirm in this session (cheap shell, no heavy reads). Discover the project's commands and structure first: read any agent guide (CLAUDE.md, AGENTS.md, .cursor/rules, README, CONTRIBUTING) and whatever build manifests are present (for example package.json scripts, Makefile, Cargo.toml, pyproject.toml / tox.ini / noxfile, go.mod, build.gradle / pom.xml, Gemfile, composer.json, melos.yaml / pubspec.yaml) to learn how THIS project lints, formats, tests, builds and generates code, and how its modules/packages/layers are laid out. Never assume a toolchain or directory layout — use what the repo actually declares. Then:
- Working tree is **clean** (`git status --porcelain`). A per-phase commit strategy needs a clean base — if the tree is dirty, stop and ask the user to commit/stash first (the accumulated changes would land in the first phase's checkpoint commit).
- Current branch is not a protected branch. Refuse to run on whatever this repo protects (default to `main`/`master`/`release`; honor any branch-protection rules the agent guide declares). If it is protected, stop and ask.

## Author the workflow

One `Workflow` call. Interpolate the resolved overview path, folder, branch, and the `PHASES` array (with each phase's `n`, `slug`, `file`, `exec`) as **string literals** — the workflow script can't read your session state and its agents start cold. Sequential `for` loop, not `parallel()` — phases are dependent.

Every `agent()` call in the script must include `model: 'claude-fable-5'` in its options object — subagents spawned by the workflow do not inherit this command's own `model:` frontmatter.

```js
export const meta = {
  name: 'execute-all-{feature}',
  description: 'Execute, review, fix, and commit every phase of {feature} in order',
  phases: [
    { title: 'Execute' },
    { title: 'Review' },
    { title: 'Fix' },
    { title: 'Commit' },
  ],
}

const OVERVIEW = '{docs/plans/.../00-overview.md}'
const PHASES = [
  { n: 1, slug: '{slug}', file: '{docs/plans/.../01-slug.md}', exec: 'solo' },
  { n: 2, slug: '{slug}', file: '{docs/plans/.../02-slug.md}', exec: 'workflow' },
  // ... from the resolved start phase onward
]

const VERDICT_SCHEMA = {
  type: 'object',
  required: ['pass', 'summary', 'blocking'],
  properties: {
    pass:     { type: 'boolean' },                        // true ONLY if the phase fully meets its spec + verification is green
    summary:  { type: 'string' },                         // one line, what landed / what's wrong
    blocking: { type: 'array', items: { type: 'string' } }, // concrete defects the fix agent must resolve (empty when pass)
  },
}

// Scout output for workflow-phase fan-out. Units MUST touch disjoint file sets.
const WORKLIST_SCHEMA = {
  type: 'object',
  required: ['units'],
  properties: {
    units: {
      type: 'array',
      items: {
        type: 'object',
        required: ['label', 'instruction', 'files'],
        properties: {
          label:       { type: 'string' },                        // short slug for the unit
          instruction: { type: 'string' },                        // exactly what to implement, self-contained
          files:       { type: 'array', items: { type: 'string' } }, // the disjoint file set this unit owns
        },
      },
    },
  },
}

const results = []

for (const p of PHASES) {
  // 1. EXECUTE — cold, follows the /execute contract. Solo phases run one agent;
  //    workflow phases fan out HERE (a subagent can't nest its own workflow). Leaves tree dirty.
  phase('Execute')
  if (p.exec === 'workflow') {
    // 1a. Scout: partition the phase into disjoint-file units (discovery happens here too).
    const plan = await agent(
      `Read-only SCOUT for phase ${p.n} of the plan at ${OVERVIEW}.\nPhase file: ${p.file}\n\n` +
      `Read the phase file (especially its "Files to touch" and "## Execution strategy") and partition its ` +
      `implementation into INDEPENDENT work units that each own a DISJOINT set of files — no two units may edit the ` +
      `same file, so they can run in parallel on the shared tree with zero conflict. If the phase needs edit-sites ` +
      `discovered first (grep/Explore), do that discovery NOW and bake concrete paths into each unit's "files". ` +
      `Each unit's "instruction" must be self-contained (a cold agent will implement it from that text + the named files alone). ` +
      `Do NOT edit anything. If the work genuinely can't be split into disjoint-file units, return a SINGLE unit covering the whole phase.`,
      { label: `scout:${p.slug}`, phase: 'Execute', model: 'claude-fable-5', schema: WORKLIST_SCHEMA }
    )
    const units = (plan && plan.units && plan.units.length)
      ? plan.units
      : [{ label: p.slug, instruction: `Implement all of phase ${p.n} per ${p.file}.`, files: [] }]

    // 1b. Implement: one agent per unit, in parallel, each confined to its files.
    await parallel(units.map(u => () =>
      agent(
        `Implement ONE unit of phase ${p.n} (spec: ${p.file}). Edit ONLY these files: ${u.files.length ? u.files.join(', ') : '(as the unit describes)'}.\n\n` +
        `Unit: ${u.instruction}\n\n` +
        `Follow the phase's intent and the surrounding repo conventions. Do NOT touch any file outside your unit. ` +
        `Do NOT run repo-wide verification, do NOT write tests, do NOT commit — the reconcile stage owns that. Leave changes uncommitted.`,
        { label: `impl:${p.slug}:${u.label}`, phase: 'Execute', model: 'claude-fable-5' }
      )))

    // 1c. Reconcile: whole-tree verification + tests across the merged units.
    await agent(
      `The parallel implementation of phase ${p.n} (spec: ${p.file}) is on the working tree. ` +
      `Run the phase's FULL Verification against the merged tree (the project's lint / format / test / build commands as the phase lists) and fix any ` +
      `cross-unit breakage the per-unit agents couldn't see. Then write tests for this phase's changes per the /test command. ` +
      `Do NOT loosen tests or suppress lints. Leave the tree dirty and uncommitted — a later agent commits.`,
      { label: `reconcile:${p.slug}`, phase: 'Execute', model: 'claude-fable-5' }
    )
  } else {
    // solo — one agent does the whole phase per /execute.
    await agent(
      `Execute phase ${p.n} of the plan at ${OVERVIEW}.\n` +
      `Phase file: ${p.file}  (Execution: solo)\n\n` +
      `Follow the /execute command EXACTLY for this single phase: read the phase file cold + only its ` +
      `"Files to touch", implement within scope, run its Verification commands (the project's lint / format / test / build commands ` +
      `as listed), and write tests per the /test command for what this phase changed. ` +
      `Leave ALL changes UNCOMMITTED — a later agent commits. Do NOT push or open a PR. Do NOT touch other phases. ` +
      `If the phase references something that doesn't exist, or a migration needs a destructive/breaking change without a safe rollout gate, ` +
      `STOP and report it as a blocker instead of papering over it.`,
      { label: `execute:${p.slug}`, phase: 'Execute', model: 'claude-fable-5' }
    )
  }

  // 2. REVIEW → FIX loop. Independent agents; orchestrator sees only the verdict.
  let verdict, cycle = 0
  phase('Review')
  verdict = await agent(reviewPrompt(p), { label: `review:${p.slug}`, phase: 'Review', model: 'claude-fable-5', schema: VERDICT_SCHEMA })

  while (verdict && !verdict.pass && cycle < 2) {
    cycle++
    phase('Fix')
    await agent(
      `Independent fix pass for phase ${p.n} (${p.file}). A review found these BLOCKING defects:\n` +
      verdict.blocking.map((b, i) => `${i + 1}. ${b}`).join('\n') + `\n\n` +
      `Resolve every one, staying within the phase's scope. Re-run the phase's Verification commands until green ` +
      `(the project's lint / format / test / build commands). Do NOT loosen tests, suppress lints, or commit. Leave the tree dirty.`,
      { label: `fix:${p.slug}#${cycle}`, phase: 'Fix', model: 'claude-fable-5' }
    )
    phase('Review')
    verdict = await agent(reviewPrompt(p), { label: `reverify:${p.slug}#${cycle}`, phase: 'Review', model: 'claude-fable-5', schema: VERDICT_SCHEMA })
  }

  if (!verdict || !verdict.pass) {
    results.push({ phase: p.n, slug: p.slug, status: 'blocked', detail: verdict ? verdict.summary : 'review agent died', blocking: verdict ? verdict.blocking : [] })
    break  // halt the whole run — do not build on broken work
  }

  // 3. COMMIT — checkpoint the green phase.
  phase('Commit')
  const sha = await agent(
    `Commit the working-tree changes for phase ${p.n} (${p.slug}) of the plan. ` +
    `Follow the /commit command: stage the tree and write ONE Conventional Commits message scoped to what this phase delivered ` +
    `(summary: "${verdict.summary}"). Append the phase marker to the subject as the /commit command specifies, e.g. "feat(scope): ... (phase ${p.n})". ` +
    `Do NOT push, do NOT open a PR. Return ONLY the resulting commit SHA (git rev-parse --short HEAD).`,
    { label: `commit:${p.slug}`, phase: 'Commit', model: 'claude-fable-5' }
  )
  results.push({ phase: p.n, slug: p.slug, status: 'committed', summary: verdict.summary, sha: (sha || '').trim() })
}

return results

// reviewPrompt — independent, adversarial reviewer. Re-reads the phase as the spec.
function reviewPrompt(p) {
  return (
    `Independently REVIEW phase ${p.n} of the plan at ${OVERVIEW}.\n` +
    `Phase spec: ${p.file}\n\n` +
    `You did NOT write this code. Read the phase file as the contract, then inspect the ACTUAL working-tree diff ` +
    `(git diff, git status, and read the touched files). Judge whether the implementation truly satisfies the phase's ` +
    `Objective, Steps, and Acceptance, and that its Verification commands pass — RUN them yourself ` +
    `(the project's lint / format / test / build commands as the phase lists). Confirm tests for this phase's changes exist and pass. ` +
    `For migration phases, verify backward-compatibility per the schema/migration safety guardrail (no breaking change to currently-deployed clients). ` +
    `Set pass=true ONLY if everything holds. Otherwise pass=false with each defect as a concrete, actionable item in "blocking" ` +
    `(file + what's wrong + what's expected). Be strict; a half-met acceptance box is a fail.`
  )
}
```

The orchestrator must not duplicate the per-phase logic — the agents own it via the referenced commands. Keep the prompts as literals; the script can't see your conversation.

## After the workflow returns

The workflow result is the `results` array — a compact list of `{phase, status, summary, sha}` (and a trailing `blocked` entry if it halted). Read it; do not re-inspect the diffs.

Report (bullets, no chatter):
- One line per phase: `✓ {N} {slug} — {summary} ({sha})` for committed, `✗ {N} {slug} — blocked: {detail}` for the halt.
- If halted: list the blocking findings and name the phase to resume at — `Resume with: /execute-all from {N} {overview}`. Do NOT attempt to fix it in the main session (that's a fresh `/execute` or a re-run).
- If all green: state the phase count, the commit range (`{first-sha}..{last-sha}`), and that the plan is fully executed and committed on `{branch}`.

## Rules

- **Orchestrator stays thin.** Never read phase diffs/files/review output in the main session. Decisions come from the schema'd verdicts only. If you find yourself reading source, you're doing an agent's job.
- **Sequential phases, parallel within a phase.** Never parallelize *phases* — each builds on the prior tree. *Within* a `workflow` phase, implementers run in parallel but only over **disjoint file sets** (the scout guarantees this); they share the tree without conflict, so no worktree/merge step. A phase that can't be partitioned runs as a single execute agent — that's fine.
- **Execute fan-out lives in this workflow, never nested.** A subagent can't author its own workflow; if a phase needs fan-out, it happens at the orchestrator loop level (scout → parallel impl → reconcile). Don't tell the execute agent to "run a workflow."
- **Independent review.** The reviewer is a different agent than the executor, by contract — that's the whole point. Never let the executing agent self-certify.
- **Stop on red.** First phase that can't go green after 2 fix cycles halts the run. Don't skip it and continue.
- **Commit per green phase only.** A phase commits only after review passes. No partial-phase commits, no squashing across phases, no push, no PR.
- **No protected branches.** Refuse to run on the project's protected branches (default `main`/`master`/`release`; honor whatever this repo protects).
- **Migration safety carries through.** Schema/migration safety — applies ONLY if the project has database migrations that deploy independently of the clients using them (e.g. a server/DB migrates while older clients are still live). When it applies: both execute and review agents enforce backward-compatibility via expand → migrate → contract (parallel-change) — ship additive / nullable / defaulted changes and new versioned functions first; defer destructive changes (DROP, rename, NOT NULL, tightened constraints or types, changed function signatures, access-control tightening) to a LATER release, after old clients have drained. A contract-phase change without a drained safe rollout floor is a blocker, not something to push through. If the project has no database, or deploys schema and clients atomically, this does not apply — skip it.

## Output style

- Brief. No preamble, no recap. Lead with the resolved-inputs line, end with the per-phase report.
- Questions (if any): one `AskUserQuestion`, batched.
