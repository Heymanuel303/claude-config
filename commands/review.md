---
description: Fan out a team of reviewers across the project's layers to validate the commits that implemented a plan in docs/plans/. Read-only — no edits. Runs in parallel so the user can keep testing meanwhile.
model: fable
---

Review the **committed work** that implemented a plan in `docs/plans/` (or the scope in `$ARGUMENTS`) by spinning up an **agent team** — one read-only `Explore` reviewer per layer — that runs in parallel and coordinates through a shared task list. The goal: confirm the commits actually deliver what the plan specified, end-to-end, before release. The user may be testing in parallel — deliver a crisp go / no-go report with concrete findings tied back to plan phases.

## Resolve the plan + commit range

1. If `$ARGUMENTS` is a plan dir name → use `docs/plans/$ARGUMENTS/` (the dated folder name `{YYYY-MM-DD}-{feature-name}`).
2. Else → list `docs/plans/*/`. Folders are date-prefixed (`{YYYY-MM-DD}-{feature-name}/`), so a sorted listing runs oldest→newest; pick the **last (newest) entry** of `ls docs/plans/*/` deterministically rather than relying on mtime. If multiple are plausible (e.g. same date, ambiguous which one was meant), `AskUserQuestion` once.
3. Identify the commit range that implemented the plan:
   - Try `git log --all --oneline --grep="<plan-slug>"` and `git log --all --oneline -- docs/plans/<plan-slug>/` (where `<plan-slug>` is the full dated folder name `{YYYY-MM-DD}-{feature-name}`).
   - Look for commits whose subjects reference the plan slug or its phase numbers (e.g. `phase 1`, `phase 2`).
   - Fall back to `git log main..HEAD --oneline` if the branch is dedicated to the plan.
4. Confirm scope in one line: plan path + commit SHAs (or SHA range) + branch.

If the plan dir doesn't exist or no commits map to it → `AskUserQuestion` once with concrete options. Don't spawn the team blind.

## Pre-flight (you, not the team)

Before spawning, gather the shared context every reviewer needs:

- Plan files: `ls docs/plans/<plan-slug>/` (the dated folder, e.g. `docs/plans/2026-06-09-entitlements-generic/`) — read the overview/index file to extract phases + acceptance criteria.
- Commit list: `git log --oneline <range>` — the commits under review.
- Touched files per commit: `git show --stat <sha>` for each, or `git diff --stat <base>..<head>` for the whole range.
- **Discover the project's layers and structure.** Read any agent guide (CLAUDE.md, AGENTS.md, .cursor/rules, README, CONTRIBUTING) and whatever build manifests are present (for example package.json scripts, Makefile, Cargo.toml, pyproject.toml / tox.ini / noxfile, go.mod, build.gradle / pom.xml, Gemfile, composer.json, melos.yaml / pubspec.yaml) to learn how THIS project lints, formats, tests, builds and generates code, and how its modules/packages/layers are laid out. Never assume a toolchain or directory layout — use what the repo actually declares. Enumerate the **real** layers of this project: pick the natural ones (e.g. frontend / backend / data / infra / shared libs / tests, OR the actual top-level modules of a monorepo; in a single-package repo the "modules" are the top-level source directories). Include a database/migrations layer **only if the repo has one**.
- Group the touched files by those discovered layers so each reviewer gets a filtered list.

Pass plan phases + commit list + filtered touched files into each teammate prompt so they don't re-derive it.

## Team setup

1. **`TeamCreate`** with:
   - `team_name`: `review-{plan-slug}` (kebab-case)
   - `agent_type`: `orchestrator`
   - `description`: `Pre-release review of plan "{plan-slug}"`

2. **Create tasks** (one `TaskCreate` per layer in scope) before spawning teammates. Name each task after a real, discovered layer and the paths it owns, e.g.:
   - `<layer-a>: review {plan-slug} commits in <layer-a paths>`
   - `<layer-b>: review {plan-slug} commits in <layer-b paths>`
   - … one per layer the commit range actually touches …
   - `synthesis: produce go/no-go report` (owner = you, depends on the others)

   Skip a layer task if the commit range touches zero files there — note the skip in the synthesis.

3. **Spawn teammates in a single message** with multiple `Agent` calls (parallel). Each call uses:
   - `subagent_type: "Explore"` (read-only)
   - `team_name`: the team you just created
   - `name`: `<layer>-reviewer` (one per discovered layer in scope)
   - `prompt`: the layer-specific brief (template below)

4. After spawning, assign each layer task to its teammate via `TaskUpdate` (`owner: "<teammate-name>"`).

## Layers & scopes

Spin up one reviewer per discovered layer that the commit range touches. For each, scope it strictly to that layer's paths and give it layer-appropriate checks. Common layer shapes (adapt to the actual repo — these are illustrative, not required):

### data / migrations reviewer (only if the repo has a database)
**Scope:** the project's migration/schema files in the commit range, plus any SQL referenced from server/backend code. If the project has a database **and** a way to inspect it (an MCP server, a CLI such as `psql`/`mysql`, etc.), use it to verify the live schema matches the migrations; otherwise reason from the migration/schema files.
**Checks:** migration idempotency, access-control (e.g. row-level) policies cover new tables/columns, indexes for new query patterns, no destructive drops without backfill, enum/type changes backwards-compatible, schema/migration safety (see Rules), plan's data-phase acceptance criteria met.

### backend / service reviewer
**Scope:** changed server/service/function files in the commit range (plus any shared backend helpers).
**Checks:** auth/access enforcement, input validation, error handling + response shapes, config/secret usage, external-dependency failure paths, logging, contract alignment with the client(s), plan's backend-phase acceptance criteria met.

### app / client reviewer
**Scope:** changed files under the app/client module(s) within the commit range. Enumerate the modules from the repo structure during pre-flight — never assume a fixed list; the set can differ between branches and worktree checkouts.
**Checks:** state wired correctly, data access uses the right client/repository methods, routes/navigation reachable, loading/error/empty states, feature-flag/gating honored, no leftover debug code, copy/strings, accessibility regressions, test coverage for new logic, plan's app-phase acceptance criteria met.

### shared library reviewer
**Scope:** changed files under shared/library module(s) within the commit range. Enumerate them from the repo structure during pre-flight — trust the listing, not a hardcoded set.
**Checks:** data shapes/DTOs match backend/data shapes, client contract + implementation in sync, breaking changes flagged for downstream consumers, shared components follow the project's existing conventions, generated/codegen artifacts up to date, no unused exports left after a refactor, plan's shared-phase acceptance criteria met.

## Prompt template for each teammate

Each teammate starts cold. Brief them self-contained.

```
You are a teammate on the "{team_name}" team. Your name is "{teammate-name}".

Review the COMMITTED work that implemented the plan at docs/plans/{plan-slug}/ (a dated folder named {YYYY-MM-DD}-{feature-name}) in the {layer} of this project. Follow the project's existing conventions — discover them from the agent guide (CLAUDE.md/AGENTS.md/README/CONTRIBUTING) and build manifests; do not assume a toolchain.

Plan phases relevant to your layer:
{paste of plan phase headings + acceptance criteria for this layer}

Commits under review:
{git log --oneline of the range}

Touched files in your layer (within this commit range):
{filtered file list}

Scope strictly to: {paths for that layer}
Do NOT read outside that scope — other teammates cover other layers.

Approach:
1. Read the plan phase(s) for your layer first — understand the intended behavior + acceptance criteria.
2. Read the commits that touched your layer: `git show <sha> -- <your paths>` or `git log -p <range> -- <your paths>`.
3. Read the resulting code in its current state to confirm it survived rebases/squashes intact.

Check for:
- {layer-specific bullets from above}
- Plan adherence: every acceptance criterion for your layer must be visibly satisfied. Call out any that aren't.
- Correctness vs. intent (do the commits actually achieve what the plan says?)
- Regressions (did adjacent code break?)
- Drift between plan and implementation (intentional deviations vs. accidental gaps)
- Release blockers vs. nits — label each finding

Workflow:
1. Pick up your assigned task from the shared TaskList.
2. Do the review.
3. Reply to the team lead via SendMessage with your report (under 400 words):
   - Verdict: GO / GO-with-caveats / NO-GO for your layer
   - Plan-criteria coverage: each acceptance criterion → met / partial / missing (one line each)
   - Blockers (must fix before release): file:line + what's wrong + suggested fix + linked commit SHA
   - Nits: file:line + note
   - What looks good (one or two lines)
   - Open questions
4. Mark your task completed via TaskUpdate.

Read-only. Do not edit anything.
```

## Synthesis

When all teammate reports are in, write a single consolidated report:

1. **Scope** — plan slug, commit range, branch (one line).
2. **Overall verdict** — GO / GO-with-caveats / NO-GO. Lead with this.
3. **Plan coverage matrix** — table or bullets: phase → status (met / partial / missing) → reviewer.
4. **Blockers** — grouped, with `path:line` + suggested fix + commit SHA. Empty list = say "none".
5. **Nits** — bulleted, brief.
6. **Drift from plan** — intentional deviations worth recording vs. accidental gaps.
7. **What was verified** — short bullets per layer.
8. **Open questions** — anything no reviewer could answer read-only.
9. **Suggested next step** — e.g. "fix blockers then re-run /review", or "ship it".

Mark the `synthesis` task completed.

## Teardown

Once the synthesis is delivered:
1. `SendMessage` each teammate with `{type: "shutdown_request"}`.
2. After all teammates have shut down, call `TeamDelete`.

## Rules

- **Parallel only.** All teammate `Agent` calls in one message.
- **No edits.** Review only. Fixes are a follow-up task.
- **Anchor everything to the plan.** Every finding should reference either a plan acceptance criterion or a commit SHA (ideally both).
- **Don't duplicate work.** Don't re-grep files you delegated — trust the teammates.
- **Skip empty layers loudly.** If the commit range touches zero files in a layer, skip and say so.
- **Blocker vs. nit discipline.** A blocker breaks the release; everything else is a nit. Don't inflate.
- **One round of questions max** before spawning.
- **Be patient with idle teammates.** Idle ≠ done. Wait for their report.
- **Schema/migration safety** — applies ONLY if the project has database migrations that deploy independently of the clients using them (e.g. a server/DB migrates while older clients are still live). When it applies: every migration must stay backward-compatible with currently-deployed clients — use expand → migrate → contract (parallel-change): ship additive / nullable / defaulted changes and new versioned functions first; defer destructive changes (DROP, rename, NOT NULL, tightened constraints or types, changed function signatures, access-control tightening) to a LATER release, after old clients have drained. If the project has no database, or deploys schema and clients atomically, this does not apply — skip it.

## Output style

- Brief. No preamble, no recap.
- Lead with the verdict.
- Bullets over prose.
- `path:line` + commit SHA for every finding.
- No closing summary beyond the synthesis report.
