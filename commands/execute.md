---
description: Execute a single phase from a multi-phase plan in docs/plans/. Reads the phase file cold, runs it solo or as a workflow per the phase's Execution field, verifies, writes tests (via /test), and hands back a dirty tree.
model: opus
---

Execute one phase of a plan. Invoked like:

```
/execute phase 1 from docs/plans/{YYYY-MM-DD}-{feature}/00-overview.md
/execute phase 2 from @docs/plans/2026-06-09-some-feature/00-overview.md
/execute 3 docs/plans/{YYYY-MM-DD}-{feature}/00-overview.md
```

`$ARGUMENTS` carries the phase number and the overview path. Parse both.

Plan folders are dated: `docs/plans/{YYYY-MM-DD}-{feature-name}/` (e.g. `docs/plans/2026-06-09-some-feature/`), so a sorted listing runs oldest→newest. The `{feature}` placeholder below resolves to that full dated folder name.

## Resolve inputs

1. **Phase number** — first integer in `$ARGUMENTS`.
2. **Overview path** — first path matching `docs/plans/*/00-overview.md` (strip a leading `@` if present). If `$ARGUMENTS` names no overview, list `docs/plans/*/00-overview.md` and take the **chronologically-last** match — dated folders sort by date, so the last entry is the newest plan; prefer that over modified-time heuristics.
3. **Phase file** — read the overview, find the link for phase N, resolve relative to the overview's folder. Fallback: `docs/plans/{feature}/{NN}-*.md` where `{feature}` is the dated folder name and `NN` is the zero-padded phase number.

If either input is missing or ambiguous (no phase number, overview not found, phase file not found) → stop and ask the user with `AskUserQuestion`. Do NOT guess.

State what you resolved in one line before starting:
`Executing phase {N}: {phase title} — {phase-file-path}`

## Read the phase cold

This session is fresh by design. Read **only**:

- The phase file itself (full content).
- Files explicitly listed under "Files to touch" in the phase.
- Adjacent files needed to understand those (imports, callers) — pull as you go.

Do NOT read other phase files. Do NOT read the overview beyond resolving the phase link. The phase is self-contained by contract; if it isn't, surface that as a blocker rather than papering over it.

To run the phase you need to know how THIS project builds and tests. Discover the project's commands and structure first: read any agent guide (CLAUDE.md, AGENTS.md, .cursor/rules, README, CONTRIBUTING) and whatever build manifests are present (for example package.json scripts, Makefile, Cargo.toml, pyproject.toml / tox.ini / noxfile, go.mod, build.gradle / pom.xml, Gemfile, composer.json, melos.yaml / pubspec.yaml) to learn how THIS project lints, formats, tests, builds and generates code, and how its modules/packages/layers are laid out. Never assume a toolchain or directory layout — use what the repo actually declares.

## Choose execution mode

Read the phase's `**Execution:**` field:

- **`solo`** (or field absent) → run it yourself in this session: **Execute (solo)** below.
- **`workflow`** → the planner judged this phase worth fanning out. Run it via the `Workflow` tool following the phase's **## Execution strategy** section: **Execute (workflow)** below.

State which mode you're using in one line before starting.

## Execute (solo)

1. **Plan tasks.** Use `TaskCreate` to mirror the phase's "Steps" list. Mark each `in_progress` / `completed` as you go.
2. **Implement.** Edit files using `Edit` / `Write`. Stay within the phase's stated scope. If the phase says "do X in file Y" and you discover Y also needs Z to compile, do Z — but flag scope creep in the final report. Follow the project's existing conventions (state management, error handling, layering, naming) — discover them from neighboring code, don't impose new ones.
3. **Verify.** Run the commands under the phase's "Verification" section — the lint/format/test/build commands of the project, discovered as above. Typically:
   - the project's lint/static-analysis step
   - the project's formatter (or its check mode)
   - the project's test command
   - the project's codegen step, if codegen-affecting files were touched
   Fix failures before committing. Don't suppress lints to make verification pass.
4. **Check acceptance.** Walk the phase's "Acceptance" checklist. If a box can't be checked, stop and report — don't hand back a half-done phase.

## Execute (workflow)

The phase is marked `**Execution:** workflow`. Author **one** `Workflow` call inline that follows the phase's **## Execution strategy** section verbatim — it tells you the fan-out unit, shape, isolation, and verify stage. You own correctness; the workflow is your fan-out, not an excuse to skip the cold read.

1. **Pre-flight (in this session).** Cold-read the phase + its "Files to touch". If "Execution strategy" says edit sites must be discovered first, find them now (grep/Explore) so you can hand the workflow a concrete work-list — don't make the workflow guess scope.
2. **Author the script.** Translate "Execution strategy" into the script:
   - **Shape:** `pipeline(items, transform, verify)` for independent edit-sites/files (the default — each item flows transform→verify without a barrier). `parallel(...)` only when a stage genuinely needs all prior results together (cross-file dedup, all-or-nothing gate). `find → transform → verify` when sites were discovered in pre-flight.
   - **Fan-out unit:** one agent per file / call-site / layer / dimension, as the section states.
   - **Isolation:** `isolation: 'worktree'` ONLY if agents would edit the **same** file concurrently. If each agent owns a distinct file, omit it — they edit the shared tree without conflict (cheaper, no merge step).
   - **Cold prompts:** each agent starts fresh — embed the exact file path, the precise change, and the pattern to follow as string literals. Reference no conversation context. Tell each editor to stay strictly within its assigned file/scope and leave changes uncommitted.
   - **Verify stage:** have each item's verifier confirm its edit compiles/matches intent; for high-assurance phases, make verifiers adversarial (try to refute the edit) and use a `schema` so verdicts are structured.
3. **Run it**, then **reconcile in this session:** review the diff the workflow produced, run the phase's full "Verification" commands yourself (lint/format/test/build, discovered for this project) against the merged tree, and fix any cross-file breakage the per-item agents couldn't see. A green per-item verifier is not a green phase — you own the whole-tree verification.
4. **Check acceptance** exactly as in solo mode. If a box can't be checked, stop and report.

If mid-run the workflow reveals the phase's scope was wrong (sites that don't exist, a shape that doesn't fit), stop and surface it as a blocker — don't let the workflow paper over a bad phase.

## Write tests

Once verification is green and acceptance is met, cover the phase's changes with tests by running the `/test` command scoped to this phase:

1. **Scope to the phase.** Test only the behavior this phase introduced — the files under "Files to touch" and the new/changed functions, modules, services, or components. Don't backfill unrelated coverage.
2. **Write tests** following the `/test` command's rules: mirror the source path under the project's test directory, cover the contract not the implementation, one group per subject, arrange-act-assert. Run the project's codegen step first if the phase added generated types.
3. **Run tests in an isolated subagent** exactly as the `/test` command describes — delegate execution to a single `Agent` call (`subagent_type: "general-purpose"`) so output stays out of main context. Brief it self-contained with the scope + commands.
4. **Fix failures** per the `/test` command: test wrong → fix the test; code wrong (regression in this phase's scope) → fix the code. No skipped tests, no loosened asserts, no swallowed errors. Rerun fix → test until green or 3 cycles, then stop and ask.

If nothing testable changed (pure docs/config/generated code) → say so and skip. Don't fabricate tests.

## Hand off

When verification is green and acceptance is met, stop. Leave changes uncommitted in the working tree — the user commits manually at the end of their session.

Do NOT commit. Do NOT push. Do NOT open a PR. Do NOT start the next phase — that's a separate `/execute` invocation in a fresh session.

## Schema/migration safety

Applies ONLY if the project has database migrations that deploy independently of the clients using them (e.g. a server/DB migrates while older clients are still live). When it applies: every migration must stay backward-compatible with currently-deployed clients — use expand → migrate → contract (parallel-change). Ship additive / nullable / defaulted changes and new versioned functions first; defer destructive changes (DROP, rename, NOT NULL, tightened constraints or types, changed function signatures, access-control tightening) to a LATER release, after old clients have drained. Refuse destructive (contract) SQL unless the phase explicitly authorizes it — i.e. the phase confirms the minimum supported client version has been raised past every version using the old shape and that build has drained; if that gate is missing, treat it as a blocker and stop. If the project has no database, or deploys schema and clients atomically, this does not apply — skip it.

## Blockers

Stop and ask the user if:

- Phase file references something that doesn't exist (file, package/module, migration).
- A migration phase requires destructive/breaking schema changes but doesn't confirm the old clients have drained (would break a live client) — see Schema/migration safety.
- "Files to touch" conflicts with current repo state in a way the phase didn't anticipate.
- Verification fails for a reason outside the phase's scope.
- Acceptance criteria are ambiguous given the code you see.

Don't silently expand scope to fix upstream problems — surface them.

## Report

End-of-turn summary (1–3 sentences):
- What landed (files touched + one-line scope).
- Tests added (count + files) and final test status.
- Anything skipped or flagged for the next phase.
- Next phase to run, if any (just the pointer — don't auto-trigger).

## Rules

- **Cold read.** Treat the phase file as the spec. Don't lean on conversation context the planner had.
- **Single phase only.** No "while I'm here" work from other phases.
- **No commit, no push, no PR.** Hand back a dirty working tree; user commits manually.
- **No edits outside the phase scope** except minimum-needed compile fixes — and flag them.
- **Don't rewrite the plan.** If the phase is wrong, report it; user decides whether to revise the plan or push through.
- **Tests are part of the phase.** A phase isn't done until its changes are covered by tests (via the `/test` command) and green — unless nothing testable changed.

## Output style

- Brief. No preamble, no recap, no chatter.
- Bullet points over prose.
- Lead with the answer; cut everything that isn't actionable.
- Questions (if any): one line each, batched in a single `AskUserQuestion`.
- No closing summary beyond the 1–3 sentence "Report" step.
