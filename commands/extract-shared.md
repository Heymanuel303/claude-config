---
description: Run a workflow across all of the project's modules (including worktree checkouts) to detect duplicated or generic code that could be extracted into a shared/common library and reused. Read-only — produces an extraction-proposal report.
model: opus
---

Find code living inside one module that belongs in a shared/common library. Invoked like:

```
/extract-shared
/extract-shared focus on UI widgets
/extract-shared modules/web vs .worktrees/feature/modules/mobile
```

`$ARGUMENTS` is an optional focus hint (a code category, or specific module paths to compare). If empty, scan everything.

This is read-only analysis. No code moves, no edits — the output is a report of extraction candidates the user can turn into a `/plan`.

## Pre-flight (you, not the workflow)

The workflow script has no filesystem access — discover the scan targets yourself and interpolate them as literals. Discover the project's commands and structure first: read any agent guide (CLAUDE.md, AGENTS.md, .cursor/rules, README, CONTRIBUTING) and whatever build manifests are present (for example package.json scripts, Makefile, Cargo.toml, pyproject.toml / tox.ini / noxfile, go.mod, build.gradle / pom.xml, Gemfile, composer.json, melos.yaml / pubspec.yaml) to learn how THIS project lints, formats, tests, builds and generates code, and how its modules/packages/layers are laid out. Never assume a toolchain or directory layout — use what the repo actually declares.

1. **Enumerate modules** — list the project's packages / modules / services / libraries from the repo structure (the directories the build manifests declare; in a single-package repo the "modules" are the top-level source directories) **plus** the equivalent under `.worktrees/*/` for modules being built in worktrees that aren't merged yet. Deduplicate: if the same module exists in both, prefer the worktree copy only when it's clearly ahead (newer work); otherwise use this checkout's copy. Record each as `{ name, path }`.
2. **Identify the shared library** — find the project's existing shared/common library or module(s) the others depend on (discovered from the manifests / dependency graph). Record each as `{ name, path }`.
3. **Capture today's date** — `date +%F` (the script can't compute it).
4. If fewer than 2 modules exist anywhere, say so and stop — cross-module duplication needs at least two modules. (A single-module scan for "obviously generic" code is still allowed if the user asked explicitly.)

State the resolved target set in one line before running the workflow: modules (with paths), shared libraries, focus hint.

## Run the workflow

Author **one** `Workflow` call inline. Interpolate the module list, shared-library list, date, and focus hint as literals — agents start cold.

Shape: **Inventory (parallel barrier) → Match (you, in-script) → Verify (pipeline) → Synthesize.** The barrier after Inventory is genuinely needed: matching requires every module's inventory plus the shared-library inventory together.

```js
export const meta = {
  name: 'extract-shared',
  description: 'Detect module code extractable into a shared/common library',
  phases: [
    { title: 'Inventory', detail: 'one agent per module + one per shared library' },
    { title: 'Match', detail: 'cross-module duplicate + library-overlap matching' },
    { title: 'Verify', detail: 'adversarial check per candidate' },
    { title: 'Synthesize', detail: 'one report' },
  ],
}

const DATE = '{date +%F}'           // interpolated literal
const FOCUS = '{focus hint or "none"}'
const MODULES = [ /* { name: 'web', path: 'modules/web' }, { name: 'mobile', path: '.worktrees/feature/modules/mobile' }, ... */ ]
const LIBS = [ /* { name: 'common', path: 'libs/common' }, ... */ ]

const INVENTORY_SCHEMA = {
  type: 'object',
  required: ['items'],
  properties: {
    items: {
      type: 'array',
      items: {
        type: 'object',
        required: ['kind', 'name', 'path', 'summary', 'appSpecific'],
        properties: {
          kind:        { type: 'string' },  // widget/component | util | extension | service | repository-pattern | model | theme | validator | formatter | state-pattern
          name:        { type: 'string' },  // class/function name
          path:        { type: 'string' },  // file path (line range ok)
          summary:     { type: 'string' },  // what it does, 1 line
          appSpecific: { type: 'boolean' }, // true if coupled to this module's domain
        },
      },
    },
  },
}

const VERDICT_SCHEMA = {
  type: 'object',
  required: ['extract', 'targetLibrary', 'effort', 'reasoning', 'proposedApi'],
  properties: {
    extract:       { type: 'boolean' },
    targetLibrary: { type: 'string' },  // existing shared-library name, or 'NEW: <name>'
    effort:        { type: 'string' },  // S | M | L
    reasoning:     { type: 'string' },
    proposedApi:   { type: 'string' },  // 1-3 line sketch of the extracted public API
  },
}

phase('Inventory')
const inventories = await parallel([
  ...MODULES.map(m => () => agent(
    `Inventory potentially-reusable code in the module at ${m.path} (module "${m.name}").\n` +
    `Focus hint: ${FOCUS}.\n` +
    `Walk the module's source directories, skipping generated / build / vendor / dependency artifacts. Catalog every component, ` +
    `utility, extension, formatter, validator, service wrapper, state pattern, or model that is NOT inherently tied to this ` +
    `module's business domain — i.e. could plausibly serve another module. Also include borderline items but mark appSpecific=true. ` +
    `Be concrete: real names, real paths. Read-only.`,
    { label: `inventory:${m.name}`, phase: 'Inventory', agentType: 'Explore', schema: INVENTORY_SCHEMA }
  )),
  ...LIBS.map(l => () => agent(
    `Inventory the PUBLIC API of the shared library at ${l.path} ("${l.name}").\n` +
    `Catalog every exported component, class, utility, extension, and theme/design token — kind + name + path + 1-line summary. ` +
    `Set appSpecific=false for all. This is used to detect when module code duplicates something the library already offers. Read-only.`,
    { label: `inventory:${l.name}`, phase: 'Inventory', agentType: 'Explore', schema: INVENTORY_SCHEMA }
  )),
])

const modInv = MODULES.map((m, i) => ({ module: m.name, items: (inventories[i]?.items || []) }))
const libInv = LIBS.map((l, i) => ({ lib: l.name, items: (inventories[MODULES.length + i]?.items || []) }))

phase('Match')
const matcher = await agent(
  `You are matching inventories from a multi-module repo to find extraction candidates.\n\n` +
  `MODULE INVENTORIES:\n${JSON.stringify(modInv)}\n\nSHARED-LIBRARY INVENTORIES (already shared):\n${JSON.stringify(libInv)}\n\n` +
  `Produce candidates in three buckets:\n` +
  `1. DUPLICATE: near-identical code in 2+ modules (same purpose, similar shape).\n` +
  `2. LIBRARY-OVERLAP: module code that reimplements something a shared library already exports (fix = use the library, not extract).\n` +
  `3. GENERIC-SINGLE: code in one module that is clearly domain-free and likely needed by future modules (be conservative here).\n` +
  `For each candidate list the involved items (module + path + name) and a 1-line rationale. Skip anything marked appSpecific=true unless it appears in 2+ modules.`,
  { label: 'match', phase: 'Match', schema: {
      type: 'object', required: ['candidates'],
      properties: { candidates: { type: 'array', items: {
        type: 'object', required: ['bucket', 'title', 'items', 'rationale'],
        properties: {
          bucket:    { type: 'string' },
          title:     { type: 'string' },
          items:     { type: 'array', items: { type: 'string' } }, // "module:path — name"
          rationale: { type: 'string' },
        } } } },
    } }
)

phase('Verify')
const verified = await pipeline(
  matcher.candidates,
  (c) => agent(
    `Adversarially verify this extraction candidate in a multi-module repo. Default to extract=false if coupling is real.\n\n` +
    `Candidate (${c.bucket}): ${c.title}\nItems: ${c.items.join('; ')}\nRationale: ${c.rationale}\n\n` +
    `Open the actual files. Check: hidden coupling to module-specific models/state/strings/i18n, divergent behavior between ` +
    `the copies (are they really the same?), whether an existing shared library (${LIBS.map(l => l.name).join(', ')}) is the right home ` +
    `vs. a new library, and rough effort (S/M/L). For LIBRARY-OVERLAP, verify the library export actually covers the module's use ` +
    `and set targetLibrary to the existing library. Propose the extracted public API in 1-3 lines. Read-only.`,
    { label: `verify:${c.title.slice(0, 30)}`, phase: 'Verify', schema: VERDICT_SCHEMA }
  ).then(v => ({ ...c, verdict: v }))
)

phase('Synthesize')
const confirmed = verified.filter(Boolean).filter(c => c.verdict?.extract)
const rejected = verified.filter(Boolean).filter(c => c.verdict && !c.verdict.extract)
return { confirmed, rejected, date: DATE }
```

## After the workflow returns

Write the report to `docs/reviews/extract-shared-{date}.md` and show the summary inline:

```markdown
# Shared-code extraction candidates — {date}

**Modules scanned:** {names + paths, noting worktree copies}
**Shared libraries indexed:** {names}
**Focus:** {hint or "full scan"}

## Confirmed candidates
### {title}  ·  {bucket}  ·  → `{targetLibrary}`  ·  effort {S/M/L}
- Involved: {module:path — name, per item}
- Why: {rationale + verifier reasoning}
- Proposed API: {sketch}

## Use-existing-library fixes (LIBRARY-OVERLAP)
- {module:path} reimplements `{library}` export `{name}` — switch to the library.

## Rejected (and why)
- {title} — {verifier reasoning, 1 line}
```

End with a one-line pointer: the user can turn confirmed candidates into a `/plan` (extraction phases: shared-library code first, then per-module migration — per the /plan command's sizing heuristics).

## Rules

- **Read-only.** No edits, no file moves. The report is the deliverable.
- **Worktree-aware.** Modules under `.worktrees/*/` count — that's where new modules incubate.
- **Conservative on GENERIC-SINGLE.** One module's "generic" code is speculation; require the verifier to argue actual future reuse, not "could be reused".
- **LIBRARY-OVERLAP beats extraction.** If a shared library already covers it, the fix is adoption, not a new extraction.
- **Evidence-bound.** Every candidate cites real paths in 2+ places (or 1 place + an existing library export).

## Output style

- Brief. No preamble, no recap, no chatter.
- Lead with the count of confirmed candidates and the report path.
- Bullets over prose.
