---
name: code-review
description: Deep-scan every module and source layer of the project against five DX/quality principles via a workflow, and produce one report
model: opus
---

Run a **`code-review` workflow** to deep-scan every layer of the codebase. Author **one** `Workflow` call inline (mirroring how `/plan` and `/explore-stack` embed their scripts) — do not scan inline.

**Discover the project's commands and structure first:** read any agent guide (CLAUDE.md, AGENTS.md, .cursor/rules, README, CONTRIBUTING) and whatever build manifests are present (for example `package.json` scripts, Makefile, `Cargo.toml`, `pyproject.toml` / `tox.ini` / `noxfile`, `go.mod`, `build.gradle` / `pom.xml`, `Gemfile`, `composer.json`, `melos.yaml` / `pubspec.yaml`) to learn how THIS project lints, formats, tests, builds and generates code, and how its modules/packages/layers are laid out. Never assume a toolchain or directory layout — use what the repo actually declares. Interpolate the discovered lint and format-check commands, and the discovered module list, into the workflow script as string literals (workflow agents start cold).

The workflow runs three phases:

1. **Discover** — enumerates every scan target (the project's modules / packages / services / source directories, discovered from the repo structure — in a monorepo these are the natural top-level modules; in a single-package repo they are the top-level source directories) and runs the mechanical pass (the project's lint command + its format-check command, discovered) in parallel.
2. **Scan** — one deep-scan agent per target, each opening the real source files (skipping generated, build, and vendor artifacts), prioritising files flagged by the mechanical pass, judged against the five principles:
   1. Readability over cleverness
   2. Consistency with the project's own style guide and linter/formatter config
   3. Separation of concerns appropriate to the architecture of the project
   4. Self-documenting code & strong typing where the language supports it
   5. Testability & fast feedback (dependency-injection seams)
3. **Synthesize** — merges all findings into one Markdown report: grouped by file (path + line + principle + severity + fix), a per-principle summary table, and a prioritised top-10 highest-impact fixes.

## Run the review workflow

Author **one** `Workflow` call inline. Interpolate the discovered lint command, format-check command, and the project's known module layout into the script as string literals — the workflow agents start cold, so never write "see conversation" or assume a toolchain.

Every `agent()` call in the script must include `model: 'claude-opus-4-8'` in its options object — subagents spawned by the workflow do not inherit this command's own `model:` frontmatter.

Use this script template:

```js
export const meta = {
  name: 'code-review',
  description: 'Deep-scan every module and source layer against five DX/quality principles, produce one report',
  whenToUse: 'Run a DX/quality audit across all layers of the codebase',
  phases: [
    { title: 'Discover', detail: 'enumerate scan targets + run mechanical checks' },
    { title: 'Scan', detail: 'one deep-scan agent per module / package' },
    { title: 'Synthesize', detail: 'merge findings into one Markdown report' },
  ],
}

// ---------------------------------------------------------------------------
// The five principles every scanner applies. Kept in one place so every
// target is judged identically and the synthesis can group by principle.
// ---------------------------------------------------------------------------
const PRINCIPLES = `
Evaluate against these five principles:

1. Readability over cleverness — oversized functions/methods, deeply nested
   control flow, cryptic names, "smart" one-liners that should be extracted into
   named units.
2. Consistency with the project's own style — deviations from the project's
   documented style guide and its linter/formatter config (naming, import/order,
   formatting, idioms the rest of the codebase follows). Discover the project's
   conventions; do not impose external ones.
3. Separation of concerns appropriate to the architecture of the project —
   business logic, I/O, or data access leaking into the wrong layer for THIS
   project's chosen architecture. Follow the project's existing layering and
   conventions (discover them; do not prescribe a framework or pattern). Flag
   mixed responsibilities, god objects, and units that reach across layer
   boundaries they shouldn't.
4. Self-documenting code & strong typing — weak/loose types where the language
   supports stronger ones, values that should be non-nullable, comments restating
   WHAT instead of WHY, places where richer types (enums, sealed/union types,
   result types) would make invalid states unrepresentable.
5. Testability & fast feedback — hard-coded dependencies with no injection seam,
   untested core logic, tight coupling that blocks isolated testing. Prefer
   dependency injection through the project's existing seams.
`

const TARGET_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['targets'],
  properties: {
    targets: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['label', 'path', 'kind'],
        properties: {
          label: { type: 'string', description: 'short display name, e.g. "api/users" or "pkg/core"' },
          path: { type: 'string', description: 'directory to scan, relative to repo root' },
          kind: { type: 'string', description: 'natural layer for this repo, e.g. module / package / service / layer / source-dir' },
        },
      },
    },
  },
}

const FINDINGS_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['target', 'filesScanned', 'filesSkipped', 'findings'],
  properties: {
    target: { type: 'string' },
    filesScanned: { type: 'integer' },
    filesSkipped: { type: 'integer', description: 'eligible source files NOT opened due to scope; 0 if all covered' },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['file', 'line', 'principle', 'severity', 'description', 'fix'],
        properties: {
          file: { type: 'string', description: 'path relative to repo root' },
          line: { type: 'integer' },
          principle: { type: 'integer', enum: [1, 2, 3, 4, 5] },
          severity: { type: 'string', enum: ['high', 'medium', 'low'] },
          description: { type: 'string', description: 'one line' },
          fix: { type: 'string', description: 'concrete suggested fix, one line' },
        },
      },
    },
  },
}

// ---------------------------------------------------------------------------
// Phase 1 — Discover targets + run mechanical checks (in parallel).
// ---------------------------------------------------------------------------
phase('Discover')

const [discovery, mechanical] = await parallel([
  () =>
    agent(
      `Enumerate the deep-scan targets for a DX/quality review of this project.
First read any agent guide (CLAUDE.md, AGENTS.md, README, CONTRIBUTING) and build
manifests present (package.json, Makefile, Cargo.toml, pyproject.toml, go.mod,
build.gradle, pom.xml, Gemfile, composer.json, melos.yaml/pubspec.yaml, etc.) to
learn how the source is laid out. Then return one target per natural module of THIS
repo:
- in a monorepo / multi-package repo: each top-level module / package / service /
  app (one target each)
- in a single-package repo: each top-level source directory
Use 'ls' / actual repo inspection — do NOT guess. label like "api/users" or
"pkg/core"; path is the directory to scan; kind is the natural layer name for this
repo (module / package / service / layer / source-dir).`,
      { label: 'discover-targets', phase: 'Discover', model: 'claude-opus-4-8', schema: TARGET_SCHEMA, agentType: 'Explore' },
    ),
  () =>
    agent(
      `Run the project's mechanical checks from the repo root and report the worst
offenders so a deeper review can prioritise. Discover the project's lint command and
its format-check command first (from CLAUDE.md/AGENTS.md/README or the build manifest
— e.g. an npm/yarn script, a Makefile target, a Cargo/Go/Gradle task, ruff/flake8,
gofmt -l, prettier --check, etc.) and run them. Then summarise: which files have the
most lint warnings/errors (path + count + the rule names), and which files fail the
format check. Return a concise plain-text summary grouped by file path. If a command
fails or none exists, say so and include any error verbatim. Do NOT modify any files.`,
      { label: 'mechanical-checks', phase: 'Discover', model: 'claude-opus-4-8' },
    ),
])

const targets = (discovery?.targets ?? []).filter((t) => t && t.path)
if (targets.length === 0) throw new Error('code-review: no scan targets discovered')
log(`Discovered ${targets.length} targets. Mechanical checks done — fanning out scanners.`)

// ---------------------------------------------------------------------------
// Phase 2 — One deep-scan agent per target. Pipeline so each result is ready
// the moment its scan finishes (synthesis runs after the barrier below).
// ---------------------------------------------------------------------------
phase('Scan')

const scans = await parallel(
  targets.map((t) => () =>
    agent(
      `Deep-scan the source code under "${t.path}" (kind: ${t.kind}) for "${t.label}".

Scan every source file recursively under that path. SKIP generated, build, and
vendor artifacts (generated/codegen output, build/dist/out directories, vendored
third-party code, lockfiles). Open the files — prioritise the ones flagged by the
mechanical pass below — and read their real contents; do not infer from filenames.

${PRINCIPLES}

Mechanical pass results (use to prioritise; may cover the whole repo, focus on this path):
${typeof mechanical === 'string' ? mechanical.slice(0, 6000) : '(unavailable)'}

For every issue report: file path (relative to repo root) + line number, which principle
(1-5), severity (high/medium/low), a one-line description, and a concrete one-line fix.
Be precise and conservative — only real, actionable issues that respect the project's
existing conventions. Report filesScanned and, if you could not open every eligible
file, filesSkipped (else 0). Do NOT modify any files.`,
      { label: `scan:${t.label}`, phase: 'Scan', model: 'claude-opus-4-8', schema: FINDINGS_SCHEMA, agentType: 'Explore' },
    ),
  ),
)

const results = scans.filter(Boolean)
const allFindings = results.flatMap((r) => (r.findings ?? []).map((f) => ({ ...f, target: r.target })))
const skipped = results.filter((r) => (r.filesSkipped ?? 0) > 0)
if (skipped.length) {
  log(`Coverage note: ${skipped.map((r) => `${r.target}(${r.filesSkipped} files)`).join(', ')} not fully opened.`)
}
log(`Collected ${allFindings.length} findings across ${results.length} targets.`)

// ---------------------------------------------------------------------------
// Phase 3 — Synthesize into a single Markdown report.
// ---------------------------------------------------------------------------
phase('Synthesize')

const report = await agent(
  `Assemble a single Markdown DX/quality-review report from these findings (JSON):

${JSON.stringify(allFindings).slice(0, 120000)}

Coverage: ${results.length} targets scanned${
    skipped.length ? `; partial coverage on: ${skipped.map((r) => `${r.target} (${r.filesSkipped} files not opened)`).join(', ')}` : '; full coverage'
  }.

Principle legend: 1=Readability, 2=Consistency with project style, 3=Separation of
concerns, 4=Self-documenting & strong typing, 5=Testability.

Produce:
1. A short intro line with totals (findings, targets, coverage caveats if any).
2. Findings grouped by file (heading per file). Under each file, a bullet per issue:
   "L<line> — [P<principle> · <severity>] <description> → <fix>".
3. A summary table counting issues per principle (and a severity breakdown).
4. A prioritised "Top 10 highest-impact fixes" list (favour high severity + recurring
   patterns across targets).
Return ONLY the Markdown, no preamble.`,
  { label: 'synthesize-report', phase: 'Synthesize', model: 'claude-opus-4-8' },
)

return { report, totalFindings: allFindings.length, targets: results.length }
```

When the workflow returns, write its `report` to a timestamped file under `docs/reviews/code-review-<date>.md` (capture the date with `date +%F` in the main session) and show the summary table + top-10 inline.

The workflow does not modify any source files — it reports only.
