---
description: Answer a read-only "does this belong here / where should it go?" question about tagged files and uncommitted (incl. worktree) changes. No edits — produces a reasoned placement verdict with evidence.
model: opus
---

Answer a **placement / belonging** question about code the user tags (`@file`, `@dir`) and/or the current uncommitted changes. Typical case: mid-refactor, the user is unsure where some code should live and asks whether the changes in two files belong where they are. Goal is a **reasoned verdict + recommended home, backed by repo conventions and evidence**. Strictly read-only — no edits, no moves. The output is advice the user acts on (or doesn't).

You orchestrate: resolve the question, investigate read-only (fan out when there's breadth), then synthesize one verdict. Don't touch the working tree beyond reading it.

## Resolve the question

1. Collect the **tagged targets** — every `@file` / `@dir` in `$ARGUMENTS`, plus any path named in the question.
2. Resolve the **question itself**:
   - `$ARGUMENTS` non-empty → that's the question (e.g. "do these changes from `@a` and `@b` belong there?").
   - Else → derive from conversation history.
   - If still unclear (no tagged files, no nameable change, no question) → `AskUserQuestion` once: what code, and what's the doubt (belongs here? should move? should split? right layer?).
3. Capture **current change context** — read it, don't mutate:
   - `git status --short` and `git worktree list` — is this a worktree checkout? which branch?
   - `git diff` / `git diff --staged` on the tagged paths (or all changed paths if none tagged) — *what* actually changed, so the verdict is about the real edit, not the file at rest.

State in one line before investigating: the resolved question + the targets + whether they're committed, working-tree, or staged.

## Discover conventions first

Read any agent guide (CLAUDE.md, AGENTS.md, .cursor/rules, README, CONTRIBUTING) and the build manifests present (package.json, Makefile, Cargo.toml, pyproject.toml, go.mod, build.gradle / pom.xml, Gemfile, composer.json, melos.yaml / pubspec.yaml, etc.) to learn THIS repo's module/package/layer layout and any stated rules about where things live (layering, ownership, "no X imports Y", shared-vs-app boundaries). Never assume a layout — placement advice is only as good as the conventions you ground it in.

## Investigate (read-only)

Decide breadth from the question:

- **Narrow** (1–2 tagged files, one clear doubt) → investigate directly: read the targets, read the diff, find where sibling/analogous code already lives, check the import/dependency direction.
- **Broad** (several files, multiple candidate homes, or a cross-cutting refactor) → fan out **parallel `Agent` calls (one message, `subagent_type: "Explore"`)**, one per axis below. Skip an axis when irrelevant — say so.

What to establish, however you split it:

### What the code *is*
The actual responsibility of each tagged target and what the diff changes about it. Name the concrete symbols (functions, classes, types, routes). Is it domain logic, glue, UI, config, a shared util?

### Where its *kind* already lives
Find existing peers — other code of the same kind in this repo — and where they sit. Convention is the strongest signal for "where it belongs." Cite real `path:line` peers, not guesses.

### Boundary & dependency direction
What the target imports and what imports it. Does its current location respect the repo's layering (e.g. shared can't import app, data can't import services)? A placement that forces a backward dependency is the tell that it's in the wrong home.

### Worktree / change scope
Is the change isolated to the right module, or does it straddle boundaries? If this is one of several worktrees (`git worktree list`), note module sets differ per checkout — base advice on *this* tree. Flag anything uncommitted that the user may not have meant to include.

### Prompt template per fan-out agent

```
Read-only investigation for a code-placement question in this project.

QUESTION: {resolved question}
TARGETS: {tagged files/dirs}
CHANGE: {1-line summary of what the diff does, or "file at rest"}

Scope strictly to: {this axis — e.g. "find existing peers of this kind of code"}
Do NOT widen scope — other agents cover other axes.

Report (under 300 words):
- Findings with concrete `path:line` references and real symbol names
- For placement: where peers of this kind already live, and the import/dependency direction
- Whether the current location respects the repo's stated/observed layering
- Open questions you can't answer read-only

Read-only. No edits, no moves. Evidence-bound — no claim without a path:line.
```

## Synthesis — the verdict

When investigation returns, write one terse report:

```markdown
# Clarify: {one-line question}

**Targets:** {files} — {committed / working-tree / staged}{; worktree: branch if relevant}

## Verdict
{Belongs where it is / Should move to X / Should split / Wrong layer} — one sentence.

## Why
- {convention or boundary rule} — evidence: `path:line` (where peers live / dependency direction)
- {…}

## Recommended home
- `path` — {what goes here and why}; {if split: which part goes where}

## Watch-outs
- {imports that would break / invert, tests to move, callers to update — read-only observations only}

## Open questions
- {anything undecidable without the user's intent or that's unanswerable read-only}
```

If the evidence is genuinely split, say so and give the trade-off both ways rather than forcing a verdict.

## Rules

- **Read-only. No edits, no moves, no `git` mutations.** This command only *advises* where code should go. If the user wants the move done, that's a separate follow-up.
- **Ground every verdict in convention or a boundary rule**, with a `path:line`. No "feels like it belongs in shared" — show the peers or the dependency edge.
- **Judge the diff, not just the file.** Mid-refactor the change is the point — base the verdict on what actually changed.
- **Worktree-aware.** Module/package sets differ between branches and worktree checkouts; reason about the current tree and say when you're unsure which it is.
- **Fan out only when there's breadth.** A 1–2 file question doesn't need a workflow — investigate directly.
- **One round of questions max** before investigating.

## Output style

- Brief. No preamble, no recap, no chatter.
- Bullet points over prose.
- Lead with the verdict; cut everything that isn't actionable.
- Questions (if any): one line each, batched in a single `AskUserQuestion`.
- No closing summary beyond the report.
