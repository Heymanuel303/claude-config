---
description: Fact-check a generated plan in docs/plans/ by fanning out one read-only subagent per phase. Each phase is verified against the real repo — paths, APIs, dependencies, scope — and reports what needs changing before execution. Read-only — no edits.
model: opus
---

Vet a **not-yet-executed plan** in `docs/plans/` (or the dir in `$ARGUMENTS`) before anyone runs `/execute` on it. Spin up an **agent team** — one read-only `Explore` teammate per phase — that fact-checks each phase against the actual repo in parallel, then synthesize a verdict on what needs to change.

This is NOT a code review (`/review` does that on committed work). Nothing is implemented yet. You are checking that the **plan is correct, executable, and grounded in reality** — that every file path exists (or is correctly marked new), every referenced API/symbol/data object is real, dependencies between phases hold, and no phase is built on a wrong assumption.

## Resolve the plan

1. If `$ARGUMENTS` names a plan dir → use `docs/plans/$ARGUMENTS/` (strip a leading `@`).
2. Else → `ls docs/plans/*/`. Folders are date-prefixed (`{YYYY-MM-DD}-{feature-name}/`), so a sorted listing runs oldest→newest — pick the **last (chronologically-newest) entry** deterministically rather than guessing by mtime. If multiple are plausible, `AskUserQuestion` once.
3. Read `00-overview.md` to extract the phase list + goal + constraints + acceptance criteria.

If the plan dir doesn't exist or has no phase files → `AskUserQuestion` once with concrete options. Don't spawn the team blind.

State the resolved plan in one line before creating the team: plan path + phase count.

## Pre-flight (you, not the team)

Before spawning, gather shared context every teammate needs:

- `ls docs/plans/<plan-slug>/` — enumerate phase files. `<plan-slug>` is the full dated folder name `{YYYY-MM-DD}-{feature-name}`.
- Read `00-overview.md` fully — goal, scope, out-of-scope, constraints, acceptance criteria, phase ordering + dependencies.
- Discover the project's commands and structure first: read any agent guide (CLAUDE.md, AGENTS.md, .cursor/rules, README, CONTRIBUTING) and whatever build manifests are present (for example package.json scripts, Makefile, Cargo.toml, pyproject.toml / tox.ini / noxfile, go.mod, build.gradle / pom.xml, Gemfile, composer.json, melos.yaml / pubspec.yaml) to learn how THIS project lints, formats, tests, builds and generates code, and how its modules/packages/layers are laid out. Never assume a toolchain or directory layout — use what the repo actually declares. Pass the relevant facts to each teammate so they don't re-derive them.
- Note the dependency chain (which phase depends on which) so each teammate knows what its phase assumes already exists.

Pass the overview's goal + constraints + this phase's stated dependencies into each teammate prompt so they don't re-derive it.

## Team setup

1. **`TeamCreate`** with:
   - `team_name`: `vet-{plan-slug}` (kebab-case)
   - `agent_type`: `orchestrator`
   - `description`: `Fact-check plan "{plan-slug}" before execution`

2. **Create tasks** (one `TaskCreate` per phase) before spawning teammates:
   - `phase-NN: fact-check {NN}-{slug}.md against the repo` for each phase
   - `synthesis: produce change-list verdict` (owner = you, depends on the others)

3. **Spawn teammates in a single message** with multiple `Agent` calls (parallel). Each call uses:
   - `subagent_type: "Explore"` (read-only — correct for fact-checking)
   - `team_name`: the team you just created
   - `name`: `phase-NN-checker` (e.g. `phase-01-checker`)
   - `prompt`: the per-phase brief (template below)

4. After spawning, assign each `phase-NN` task to its checker via `TaskUpdate` (`owner: "phase-NN-checker"`).

## Per-phase teammate prompt template

Each teammate starts cold. Brief them self-contained — one phase each.

```
You are a teammate on the "{team_name}" team. Your name is "{teammate-name}".

Fact-check phase {N} of the plan at docs/plans/{plan-slug}/ against the REAL repo. NOTHING in this plan has been implemented yet — you are verifying the plan is correct and executable BEFORE anyone runs it.

Your phase file: docs/plans/{plan-slug}/{NN}-{slug}.md   (here {plan-slug} is the dated folder name {YYYY-MM-DD}-{feature-name})

Plan goal: {1-sentence recap from overview}
Constraints: {perf/schema/compat/deadline from overview}
Project facts: {how this project lints/tests/builds/generates code + its module/package/layer layout, from pre-flight discovery}
This phase depends on: {dependency phases or "none"} — assume their described end-state exists; do NOT re-check them.

Approach:
1. Read your phase file fully — understand its objective, "Files to touch", "Steps", "Verification", "Acceptance".
2. For EVERY claim the phase makes, verify it against the repo as it exists today:
   - Files to touch: does each path exist? If the phase treats it as existing, confirm it does. If it should be new, confirm it doesn't already exist (and that its parent dir/module/package is right).
   - APIs / methods / classes / symbols referenced: grep and confirm they exist with the signature the phase assumes (functions, types, components, config keys — whatever the phase names). Follow the project's existing conventions; do not impose ones the repo doesn't use.
   - Data/schema objects: tables/columns/queries/stored procedures/migrations the phase reads or writes — confirm they exist (or are created by an earlier phase you depend on). If the project has a database and a way to inspect it (an MCP server, a CLI such as psql/mysql, etc.), use it; otherwise reason from the migration/schema files.
   - Verification commands: are they real commands this project actually defines (build/test/lint/codegen scripts in its manifests)?
3. Sanity-check the logic: do the Steps actually achieve the Objective? Are there missing steps, wrong ordering, or steps that contradict the constraints? Is anything out of this phase's scope leaking in?

Schema/migration safety — applies ONLY if the project has database migrations that deploy independently of the clients using them (e.g. a server/DB migrates while older clients are still live). When it applies: every migration must stay backward-compatible with currently-deployed clients — use expand -> migrate -> contract (parallel-change): ship additive / nullable / defaulted changes and new versioned functions first; defer destructive changes (DROP, rename, NOT NULL, tightened constraints or types, changed function signatures, access-control tightening) to a LATER release, after old clients have drained. If the project has no database, or deploys schema and clients atomically, this does not apply — skip it.

Check for and report:
- BROKEN: a claim that is factually wrong vs. the repo (path doesn't exist, method signature differs, data object missing, command invalid). This must be fixed or the phase will fail on execution.
- RISKY: an assumption that's plausible but unverified, or a step likely to cause trouble (race, missing error path, untested edge).
- MISSING: a step/file/consideration the phase needs but omits to meet its own Objective or Acceptance.
- DEPENDENCY GAP: this phase needs something a prior phase was supposed to produce but the plan never actually produces it.
- FINE-AS-IS: confirm the parts that check out, briefly — so the synthesis knows what was verified, not just what's wrong.

Workflow:
1. Pick up your assigned task from the shared TaskList.
2. Do the fact-check.
3. Reply to the team lead via SendMessage with your report (under 400 words):
   - Verdict for this phase: READY / NEEDS-CHANGES / BLOCKED
   - Findings, each labeled BROKEN / RISKY / MISSING / DEPENDENCY GAP, with: phase-file section + repo evidence (path:line or "grep found no X") + concrete suggested change.
   - Verified-fine: one or two lines on what checked out.
   - Open questions you couldn't resolve read-only.
4. Mark your task completed via TaskUpdate.

Read-only. Do NOT edit the plan or any code. You are auditing, not fixing.
```

## Synthesis

When all teammate reports are in, write a single consolidated verdict:

1. **Scope** — plan slug, phase count, branch (one line).
2. **Overall verdict** — READY TO EXECUTE / NEEDS-CHANGES / BLOCKED. Lead with this.
3. **Change list** — grouped by phase, only phases that need changes. Each item: label (BROKEN/RISKY/MISSING/DEPENDENCY GAP) + phase section + repo evidence + suggested edit to the plan. This is the actionable core — make it copy-pasteable into a plan revision.
4. **Cross-phase issues** — dependency gaps, ordering problems, or constraints violated across phases that no single checker owns.
5. **Verified fine** — short bullets per phase on what checked out, so the user knows what was actually validated.
6. **Open questions** — anything no teammate could resolve read-only.
7. **Suggested next step** — e.g. "revise phases 2 and 4 per the change list, then re-run /vet-plan" or "plan is sound — run /execute phase 1".

Mark the `synthesis` task completed.

## Teardown

Once the synthesis is delivered:
1. `SendMessage` each teammate with `{type: "shutdown_request"}`.
2. After all teammates have shut down, call `TeamDelete`.

## Rules

- **Plan, not code.** You vet the plan before execution. Nothing is implemented — don't look for it.
- **Parallel only.** All teammate `Agent` calls in one message. One checker per phase.
- **No edits.** Audit only. Revising the plan is a follow-up the user triggers (or a fresh `/plan` pass).
- **Ground every finding in repo evidence.** "Path doesn't exist", "grep found no such method", "table absent in schema" — not vibes.
- **Each checker owns one phase.** A checker assumes its declared dependency phases' end-state exists; it does not re-audit them.
- **BROKEN vs. RISKY discipline.** BROKEN = the phase will fail as written. Everything softer is RISKY/MISSING. Don't inflate.
- **One round of questions max** before spawning.
- **Be patient with idle teammates.** Idle ≠ done. Wait for the report.

## Output style

- Brief. No preamble, no recap.
- Lead with the verdict.
- Bullets over prose.
- Phase section + repo evidence for every finding.
- No closing summary beyond the synthesis report.
