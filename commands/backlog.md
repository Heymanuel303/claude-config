---
description: Capture a raw idea as a date-prefixed backlog brief in docs/plans/backlog/ after a surface-level exploration. NOT an executable plan — just enough structure to feed a future /plan session.
model: opus
---

Turn the idea in `$ARGUMENTS` (or the topic in conversation history) into a short backlog brief at `docs/plans/backlog/{date}-{slug}-brief.md`. The date prefix makes `ls docs/plans/backlog/` sort oldest→newest.

This is **surface exploration only** — skim enough of the repo to write a credible problem/goal/sizing, then stop. Do NOT trace the full implementation, do NOT fan out a workflow, do NOT edit any code. A brief is input for a future `/plan`, never an executable plan itself.

## Resolve the idea

1. If `$ARGUMENTS` is non-empty → that's the idea.
2. Else → derive it from conversation history.
3. If still unclear → `AskUserQuestion` once with a concrete guess. Don't explore blind.

State the resolved idea in one line before exploring.

## Surface exploration (shallow, time-boxed)

Spend a handful of read-only tool calls — no more. Goal is orientation, not understanding. Discover the project's commands and structure first: read any agent guide (CLAUDE.md, AGENTS.md, .cursor/rules, README, CONTRIBUTING) and whatever build manifests are present (for example package.json scripts, Makefile, Cargo.toml, pyproject.toml / tox.ini / noxfile, go.mod, build.gradle / pom.xml, Gemfile, composer.json, melos.yaml / pubspec.yaml) to learn how THIS project lints, formats, tests, builds and generates code, and how its modules/packages/layers are laid out. Never assume a toolchain or directory layout — use what the repo actually declares.

- Discover the modules / packages / areas of the project (from the repo structure) to ground the `scope` / `theme` headers in what actually exists.
- A couple of `Grep`/`Glob` passes for the obvious symbols, files, or folders the idea names.
- Read at most 1–2 key files at a glance to confirm the problem is real and name the right paths.

Do NOT open every call-site, trace data flow end-to-end, or read whole large files. If you find yourself going deep, stop — that's `/plan`'s job. Prefer delegating a single `Explore` agent ("medium" breadth) over reading widely yourself if the idea spans many files.

## Write the brief

Capture the date first: `date +%F` → `{date}`. Slugify the idea into kebab-case → `{slug}`. Write exactly one file: `docs/plans/backlog/{date}-{slug}-brief.md` (the folder already exists). Write nothing else; edit no code.

Mirror any existing briefs in `docs/plans/backlog/`, if present: Status/Blocked-by header, then Problem / Goal / Design options / Constraints / Sizing. Prepend the measurable header block:

```markdown
# Brief: {Title Case idea}

- **theme:** {database | backend | ui | api | infra | tooling | testing | docs | ... — pick the closest}
- **scope:** {which module(s) / package(s) / area(s) this touches; `all`/shared if cross-cutting}
- **difficulty:** {trivial | solo | agent-team | workflow} — see scale below
- **effort:** {rough sizing, e.g. "1 phase, ~2h" | "3 phases, multi-day"}
- **blast-radius:** {files/modules likely touched, e.g. "one package only" | "all modules + migration"}

**Status:** backlog — input for a future `/plan` session. NOT an executable plan.
**Blocked by:** {prerequisite plan/brief, or "nothing"}

## Problem
{2–5 sentences. What's wrong / missing today, grounded in the real paths you skimmed. Cite `path:line` where it helps.}

## Goal
{1–3 sentences. What's true once this lands.}

## Design options (decide during planning)
1. **{Option}** — {one-line tradeoff}.
2. **{Option, preferred direction if any}** — {one-line tradeoff}. {Open sub-questions as nested bullets.}

## Constraints / invariants
- {schema/back-compat, no-visual-change, test safety nets, lint guards, perf — whatever the skim surfaced}

## Sizing guess
{1–3 sentences. Phase count, solo vs fan-out, what makes it grow.}
```

### difficulty scale (drives tooling + model for the eventual /plan + /execute)

- **trivial** — single-file edit / rename / one-liner. *Not really brief-worthy; tell the user it can just be done.* Solo, any model.
- **solo** — one focused area, a handful of files. One `/execute` session, solo. Sonnet/Opus.
- **agent-team** — parallelizable across a few independent files or layers, or wants adversarial verification. A workflow with modest fan-out. Opus.
- **workflow** — wide mechanical sweep, multi-layer in one shot, high-assurance (schema/money/auth), or discovery-then-act. A full `Workflow` fan-out with verify stage. Opus.

Set `difficulty` to the honest ceiling of what a sane implementation would need, since it's the signal `/plan` reads to decide solo vs workflow.

## Report

Surface: the created file path, the resolved `theme`/`scope`/`difficulty`, and one line on what to do next (`/plan` it when ready). No other chatter.

## Don'ts

- Don't go deep — surface skim only. Deep tracing is `/plan`'s job, not the brief's.
- Don't write an executable plan, phase breakdown, or step list — options + sizing only.
- Don't edit code or write outside `docs/plans/backlog/`.
- Don't run a `Workflow` — at most one `Explore` agent if the idea is broad.
- Don't ask follow-ups that don't change what gets written.

## Output style

- Brief. No preamble, no recap.
- Lead with the file path. Bullet points over prose.
