---
description: Complete an arbitrary task outside of any plan — typically finishing work the user started by hand. Reads the user's uncommitted edits as the statement of intent, completes the work in the same direction, verifies, and records a lightweight task file that /test and /commit pick up.
model: fable
---

Complete a task the user started manually. This is the human-in-the-middle path: the user writes code by hand — a signature, a stub, a pattern applied in one place, a half-wired feature — then invokes this command to finish the intention. Invoked like:

```
/task
/task wire the new repository into the settings screen
/task finish the validation I started in the parser
```

`$ARGUMENTS` is the stated intention (optional). The user's uncommitted edits are the other half of the spec — often the bigger half.

## Resolve the intention

1. Run in parallel: `git status` and `git diff` (staged + unstaged). Read the conversation for context.
2. **The user's manual edits are the primary signal.** Read them as a statement of direction: a new function signature awaiting a body, a `TODO`/`FIXME` marker, a pattern established in one call-site that plainly wants applying to the others, an import added but not yet used, a UI hook with no handler.
3. Fold in `$ARGUMENTS` as the user's own framing of that intent.
4. State the inferred intention in one line before touching anything:
   `Task: {one-line intention} — completing from {files the user edited}`
5. If the tree is clean AND `$ARGUMENTS` is empty → nothing to infer; stop and ask. If the edits honestly support two different readings → `AskUserQuestion` once with the concrete readings as options. Don't guess between divergent intentions.

If the intention turns out to be plan-sized (multi-phase, cross-layer, migration-bearing) → stop and recommend `/plan` instead. This command is for tasks that fit one session.

## Record the task

Before implementing, capture the task so `/test` and `/commit` can see it. `date +%F` → `{date}`; slugify the intention → `{slug}`. Write `docs/tasks/{date}-{slug}.md` (`mkdir -p docs/tasks` if needed):

```markdown
# Task: {Title Case intention}

**Status:** ongoing
**Intent:** {1–2 sentences: what the user wants done, in their terms}
**Started by hand:** {files/areas the user edited manually before invoking this}

## Completion scope
- {concrete things this command will do to finish the intention}

## Acceptance
- [ ] {verifiable criteria — what must be true when the intention is complete}

## Verification
- {the project's lint/format/test commands, discovered below}
```

Keep it lightweight — one file, no phases. This is a session record, not a plan.

## Respect the human's code

The user's manual edits are both the spec and the style guide:

- **Extend, don't rewrite.** Their names, their structure, their approach. Do not rename their variables, restructure their layering, or "improve" their edits while completing them.
- **Match the pattern they established.** If they applied a shape in one place and the task is to propagate it, propagate *their* shape — even if you'd have designed it differently.
- **If their approach has a genuine problem** (a bug, a contract violation, a dead end that can't meet the intent) → stop and surface it before proceeding. Human in the middle means they decide; don't silently steer the code in a different direction.

## Discover the toolchain

Read any agent guide (CLAUDE.md, AGENTS.md, .cursor/rules, README, CONTRIBUTING) and whatever build manifests are present (for example package.json scripts, Makefile, Cargo.toml, pyproject.toml / tox.ini / noxfile, go.mod, build.gradle / pom.xml, Gemfile, composer.json, melos.yaml / pubspec.yaml) to learn how THIS project lints, formats, tests, builds and generates code, and how its modules/packages/layers are laid out. Never assume a toolchain or directory layout — use what the repo actually declares. Record the real commands under the task file's "Verification".

## Execute

Solo, in this session — no `Workflow` fan-out. If the work genuinely wants fan-out, it was plan-sized; see above.

1. **Plan tasks.** `TaskCreate` mirroring the "Completion scope" list. Mark `in_progress` / `completed` as you go.
2. **Implement.** Stay within the stated intention. If completing it forces a small adjacent change to compile, make it — and flag it in the report. No "while I'm here" work.
3. **Hold the bar.** Every line you add satisfies the engineering principles: **SOLID** (one responsibility per unit), **KISS** (simplest construct that satisfies the task — no speculative generality), **DRY** (deduplicate genuine domain logic only), **PoLA** (code behaves as its name and signature imply; no buried side effects, no swallowed errors), **LoB** (keep a feature's logic understandable from one place; tolerate small repetition over distant indirection). These govern the code you write — not license to refactor the user's code or its surroundings.

## Verify

Run the project's verification commands as discovered — typically lint/static analysis, format check, and the test command for the touched module(s); codegen first if generated types changed. Fix failures before closing. Don't suppress lints or weaken checks to get green.

## Close the task record

When verification is green:

- Tick `- [ ]` → `- [x]` under "Acceptance" **only** for criteria actually met.
- Flip `**Status:**` to `completed`.

If blocked (see below), leave `Status: ongoing` and add a `**Blocked:** {reason}` line instead — `/commit` and `/test` handle both states.

## Hand off

Stop with an uncommitted working tree — the user reviews the completion before anything lands.

Do NOT commit. Do NOT push. Do NOT open a PR. Point the user at the next steps: `/test` (it scopes to this task record) and `/commit` (it detects the record, stages it with the work, and adds the `Task:` trailer).

## Blockers

Stop and surface — don't work around — when:

- The user's manual code contains a bug or contradiction that blocks the stated intent (their call to fix, not yours).
- The intention is ambiguous after one round of questions.
- The task reveals plan-sized scope mid-flight.
- Verification fails for a reason outside the task's scope.

## Report

End-of-turn summary (1–3 sentences):
- The intention completed + files touched.
- Verification status.
- The task record path + its final Status.
- Anything flagged (adjacent compile fixes, problems noticed in the user's approach, out-of-scope observations).

## Rules

- **The user's edits are the spec.** Infer intent from their code + `$ARGUMENTS`; complete it in their direction and style. Extend, never rewrite.
- **Outside plans only.** If the work belongs to an active plan phase, use `/execute`; if it's plan-sized, recommend `/plan`.
- **One task record per invocation.** `docs/tasks/{date}-{slug}.md`, Status `ongoing` → `completed` (or left `ongoing` + `Blocked:` on a blocker).
- **Solo execution.** No workflow fan-out.
- **No commit, no push, no PR.** Dirty tree back to the user; `/commit` closes the loop.
- **Problems in the user's code → surface, don't fix silently.** Human in the middle.
- **Hold the engineering principles** (SOLID, KISS, DRY, PoLA, LoB) for the code you add — not as license to touch code you didn't.

## Output style

- Brief. No preamble, no recap, no chatter.
- Bullet points over prose.
- Lead with the answer; cut everything that isn't actionable.
- Questions (if any): one line each, batched in a single `AskUserQuestion`.
- No closing summary beyond the 1–3 sentence "Report" step.
