---
description: Stage and commit the current working tree with a Conventional Commits message. Functional, scannable, actionable — no co-author trailers, no fluff.
model: sonnet
---

Commit pending changes. Invoked like:

```
/commit
/commit scope hint: quota refactor
```

`$ARGUMENTS` is an optional hint (scope, framing, ticket id). Treat it as guidance, not the message itself.

## Inspect

Run in parallel:

- `git status` (no `-uall`)
- `git diff` (staged + unstaged)
- `git log -n 10 --oneline` to match this repo's commit style

If working tree is clean → stop, say so. Do not create empty commits.

## Group

If the diff spans unrelated concerns (e.g. a feature change *and* a dep bump *and* a docs edit) → propose splitting via `AskUserQuestion` with concrete groupings. Otherwise proceed with one commit.

Watch for files that should not be committed:
- `.env`, `*.key`, `*-service-key.json`, credential files
- Large binaries unrelated to the change
- Editor scratch files

If found → surface and ask before staging them.

## Detect phase work

Check whether this commit closes a plan phase before composing the message:

1. Look at the changed paths and the conversation. Was the work driven by a phase file under `docs/plans/{date}-{feature-name}/NN-*.md`?
2. If yes, identify:
   - The phase file (e.g. `docs/plans/2026-06-09-entitlements-generic/02-quota-wiring.md`).
   - The overview (`docs/plans/{date}-{feature-name}/00-overview.md`).
3. If ambiguous (multiple plans touched, or unclear which phase) → `AskUserQuestion` once to confirm or skip.
4. If no phase is involved, skip this section entirely and proceed to message composition.

When a phase is identified, follow this **exact procedure** before staging. Do not skip steps.

### Step A — Read current state on disk

`Read` the overview file and the phase file fresh. Do NOT rely on memory or assume status. From the overview, extract:

- `N_total` = total number of phase entries under the "Phases" heading.
- `N_done_before` = count of phase lines that **already** end with ` ✓`.
- `current_phase_number` = the phase this commit closes (e.g. `2` for `02-quota-wiring.md`).

### Step B — Update the phase file

- Flip its `Status:` (if present) to `completed`.
- Tick `- [ ]` → `- [x]` under "Acceptance" **only** for criteria actually met by the work in this commit. Leave others unticked.

### Step C — Update the overview

- Append ` ✓` to the line for `current_phase_number` in the "Phases" list. **Only that line.** Do not touch other phase lines.
- Update the overview's top-level `Status:` using this table — no other transitions allowed:

  | Before | Condition | After |
  | --- | --- | --- |
  | `planned` | this is the first phase closed (`N_done_before == 0`) | `in-progress` |
  | `in-progress` | more phases remain after this one | `in-progress` (no change) |
  | `in-progress` | `N_done_before + 1 == N_total` **AND** every plan-level acceptance box is genuinely met | `completed` |
  | `completed` | — | leave alone, flag to user (shouldn't be re-closing a done plan) |

- Tick plan-level `- [ ]` acceptance boxes **only** when transitioning to `completed`, and only those genuinely met.

### Step D — Sanity check before staging

State out loud (in one short line) what you changed:
`Phase {N}/{N_total} closed. Overview status: {before} → {after}.`

If `after` is `completed`, double-check: are all `N_total` phase lines now ✓? If not, you made a mistake — revert the status change before staging.

Never tick phase lines or acceptance boxes for phases not closed by **this** commit. Never pre-emptively mark future phases done. If acceptance criteria for the current phase are unmet but the user still wants to commit → ask once, do not silently tick boxes.

Stage these markdown edits as part of the same commit. They belong with the work they describe.

## Compose message

**Format (Conventional Commits):**

```
{type}({scope}): {subject} (phase {N})    ← " (phase {N})" only when this commit closes a plan phase

{body}

Plan: docs/plans/{date}-{feature-name}/NN-*.md
```

**Type** — pick the one that matches the dominant change:
- `feat` — new user-facing capability
- `fix` — bug fix
- `refactor` — internal restructure, no behavior change
- `perf` — performance improvement
- `chore` — tooling, deps, config, version bumps
- `docs` — documentation only
- `test` — tests only
- `build` / `ci` — build system or CI pipeline
- `style` — formatting only (rare; usually folded into another type)

**Scope** — derive in this priority order:

1. **Plan-driven work → the plan's `{feature-name}`.** When the "Detect phase work" section identified a plan under `docs/plans/{date}-{feature-name}/`, the scope is `{feature-name}` verbatim (the folder name with the date prefix stripped). Example: a commit closing `docs/plans/2026-06-15-custom-database/02-*.md` → `feat(custom-database): …`, `chore(custom-database): …`. This holds regardless of which modules/packages the diff touches — the plan is the unit of work.
2. **No plan → the module or area touched**, derived from the changed paths and the project's actual layout: the name of the touched package/module/service/layer (in a monorepo, the workspace member; in a single-package repo, the top-level source directory or area). Examples only — `api`, `auth`, `parser`, `ui`, `cli`, `db`, `ci` — never assume any of these exist; read them off the repo. Match recent log style — check `git log` for how this scope was written before. Multi-module → pick the most-impacted, or omit scope if truly cross-cutting.

**Subject** — imperative, lowercase, ≤72 chars, no trailing period. Describes *what changed*, scannable at a glance.
- Good: `wire url imports to dedicated quota counter`
- Bad: `Updated the quota logic to work better`

**Phase marker** — when this commit closes a single plan phase (the "Detect phase work" section identified phase `N`), append ` (phase N)` to the **end of the subject** so the log shows which phase landed at a glance:
- `feat(custom-database): wire url imports to quota counter (phase 2)`
- The marker counts toward the ≤72-char budget — trim the prose, not the marker.
- Use the phase number from the phase file name (`02-*.md` → `2`). Omit the marker when no single phase is closed (no plan involved, or an overview-only commit spanning the whole plan).
- This complements the `Plan:` trailer (which carries the exact file path); the marker is the human-scannable cue, the trailer is the greppable anchor.

**Plan trailer** — when this commit closes a plan phase (the "Detect phase work" section identified one), append a `Plan:` trailer as the **last line** of the message, after the body:

- One trailer per commit: `Plan: docs/plans/{date}-{feature-name}/NN-name.md` (e.g. `Plan: docs/plans/2026-06-09-entitlements-generic/02-quota-wiring.md`) — the exact phase file path on disk, using the real dated folder name, not a fabricated one.
- If the work spans the overview only (no single phase), use the overview path: `Plan: docs/plans/{date}-{feature-name}/00-overview.md`.
- Always the relative repo path (starts `docs/plans/`), never an absolute path.
- Omit entirely when no plan/phase is involved.

This makes history greppable: `git log --grep="docs/plans/2026-06-09-entitlements-generic"` finds every commit tied to a plan.

**Body** — include when *why* or *what* isn't obvious from the subject + diff. Omit when the subject already says it.

When present, body rules:
- Wrap at ~72 chars.
- Lead with motivation (why), then the mechanism (how), then any caller/migration notes.
- Bullet list (`- `) when there are >2 discrete changes. Plain prose for a single thread.
- Reference issue/PR ids if the user provided them.
- No marketing language. No "this commit ...". No restating the diff line-by-line.

**Forbidden:**
- `Co-Authored-By:` trailers
- `🤖 Generated with ...` lines
- "Signed-off-by" unless the user explicitly asked
- Emoji in subject or body (unless user explicitly asked)
- Vague subjects: `update code`, `fixes`, `misc changes`, `wip`

## Stage

Stage by explicit paths — never `git add -A` / `git add .` blindly. Build the path list from the diff inspection above, excluding anything flagged in the Group step.

If a file is partially relevant, stage the whole file (no interactive hunks). If the user wants partial staging they'll say so.

## Commit

Use a heredoc to preserve formatting:

```bash
git commit -m "$(cat <<'EOF'
{type}({scope}): {subject} (phase {N})

{body}

Plan: docs/plans/{date}-{feature-name}/NN-name.md
EOF
)"
```

(Drop the ` (phase {N})` marker and the `Plan:` line when no plan phase is involved.)

For subject-only commits, drop the heredoc:

```bash
git commit -m "{type}({scope}): {subject}"
```

If a pre-commit hook fails:
1. Read the hook output.
2. Fix the underlying issue (formatting, lint, test failure).
3. Re-stage the fix.
4. Create a **new** commit. Do not `--amend` — the original commit didn't land.
5. Never bypass with `--no-verify` unless the user explicitly asks.

After commit: run `git status` to confirm clean tree + show the new SHA.

## Report

End-of-turn summary (1 sentence): `{sha} {type}({scope}): {subject}`. Nothing else.

Do NOT push. Do NOT open a PR. Do NOT start follow-up work.

## Rules

- **Conventional Commits only.** Type + optional scope + subject. Body when it adds signal.
- **Scope = plan feature-name when plan-driven.** `{feature-name}` from `docs/plans/{date}-{feature-name}/` (date stripped); fall back to the touched module/package/area only when no plan is involved.
- **No co-author trailer.** No generator trailer. No emoji unless asked.
- **Imperative, lowercase subject.** ≤72 chars.
- **Explicit staging.** Path list, not `-A`.
- **No empty commits, no amends, no force pushes, no `--no-verify`.**
- **One concern per commit.** Split if the diff sprawls.
- **Phase bookkeeping in-band.** When closing a phase, plan-file edits ship in the same commit as the work.
- **Phase marker when plan-driven.** Append ` (phase N)` to the subject when this commit closes a single plan phase; omit for no-plan or overview-only commits. Stays within ≤72 chars.
- **Plan trailer when plan-driven.** Last line = `Plan: docs/plans/{date}-{feature-name}/NN-*.md` (exact path). Omit when no plan involved.
- **Never tick unmet acceptance.** Ask before lying about phase status.

## Output style

- Brief. No preamble, no recap, no chatter.
- Bullet points over prose.
- Lead with the answer; cut everything that isn't actionable.
- Questions (if any): one line each, batched in a single `AskUserQuestion`.
- No closing summary beyond the 1-sentence "Report" step.
