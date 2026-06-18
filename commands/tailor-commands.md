---
description: Generate a project-tailored set of slash-commands into THIS project's .claude/commands/ — same goals and structure as the global generic commands, but specialized to the project's real stack, layout, build commands, and conventions. Driven by $ARGUMENTS + repo discovery.
model: opus
---

Specialize the global generic commands for the current project. This is the **inverse** of the generic set: instead of "discover the project's test command at run time", each tailored command **bakes the project's real commands, paths, layers, and guardrails in as concrete defaults** — like a hand-written, project-specific command. The generic commands stay universal; these become this project's overrides.

Because **project-scope commands shadow user-scope ones of the same name**, writing `plan.md` (etc.) into this project's `.claude/commands/` makes `/plan` run the tailored version *here* while every other repo keeps the generic one. Same names in, project-specialized versions out.

`$ARGUMENTS` is optional guidance: stack hints the repo doesn't make obvious ("this talks to a Stripe webhook", "treat `infra/` as its own layer"), an emphasis ("be strict about the DB migration contract"), or a subset of commands to generate ("only plan, execute, commit"). Treat it as steering, not the whole spec — the repo is the source of truth.

**Re-runnable — designed to be run again.** Whenever the project changes (new stack, refactored/renamed folders, added modules) or the generic commands themselves improve, run it again. On a re-run it re-profiles the repo from scratch and **updates the existing tailored set in place** — reconciling each command rather than blindly overwriting it (see "First run vs update" and the reconcile rule in the workflow). So the normal way to refresh after a refactor is: just run `/tailor-commands` again.

## Locate the source templates

The generic commands are the **user-level** set. Resolve their directory and list them:

```bash
SRC="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/commands"; ls -1 "$SRC"/*.md
```

These `.md` files are the "same goals" source — read each one as the template to specialize. **Exclude `tailor-commands.md` itself** (don't tailor the tailoring command). If `$SRC` is missing or empty, stop and tell the user to install the global command set first.

## Resolve the target + which commands to generate

- **Target dir** — this project's command dir: `"$(git rev-parse --show-toplevel 2>/dev/null || pwd)/.claude/commands"`. `mkdir -p` it.
- **Command set** — default to every template in `$SRC` (minus `tailor-commands.md`). If `$ARGUMENTS` names a subset, generate only those.
- **First run vs update** — `ls "$TARGET"`. If tailored commands already exist there, this is an **update** run: each existing one is reconciled in place (structure refreshed from the generic template, values refreshed from the new profile, manual edits preserved where the new profile doesn't contradict them) rather than blindly overwritten. New templates not yet tailored are generated fresh; templates the project no longer wants stay as they are (this command never deletes). Say "first run" or "update (N existing)" in your summary line. The files are git-tracked, so the diff is the safety net — tell the user to review it.

## Profile the project (pre-flight — you, not the workflow)

Build a concrete **project profile** the specializers will bake in. Discover, don't assume — read any agent guide (CLAUDE.md, AGENTS.md, .cursor/rules, README, CONTRIBUTING) and the build manifests present (package.json scripts, Makefile, Cargo.toml, pyproject.toml / tox.ini / noxfile, go.mod, build.gradle / pom.xml, Gemfile, composer.json, etc.), and inspect the tree. Capture:

- **Stack** — languages, frameworks, runtime(s), package manager(s).
- **Exact commands** — the real lint, format / format-check, test (per module if they differ), build, and codegen invocations this repo defines. Quote them verbatim (e.g. `pnpm test`, `cargo test`, `make lint`, `./gradlew test`).
- **Layout / layers** — the real module/package/service/layer structure (e.g. `apps/web` + `services/api` + `packages/*`, or a single package's top-level source dirs). Name the natural review/investigation layers.
- **Database** — does it have one? Migrations dir? A way to inspect it (an MCP server, a CLI like `psql`/`mysql`)? Does schema deploy independently of clients (→ migration contract matters)?
- **Observability** — error tracking / logs tooling, if any (Sentry, etc.).
- **Conventions** — protected branches, commit style, where plans/docs live, naming rules, any repo-specific guardrails worth enforcing (the "single most important rule" type).
- **Today's date** via `date +%F` (the workflow script can't compute it).

Fold `$ARGUMENTS` into the profile. State the profile in a tight summary line before running the workflow. Use `AskUserQuestion` **once** only if something load-bearing is genuinely unresolvable (e.g. no test command found anywhere, or the user's instruction contradicts the repo) — otherwise proceed.

## Run the tailoring workflow

Author **one** `Workflow` call inline. The workflow agents start cold — interpolate the resolved `$SRC`, target dir, the full **project profile**, and `$ARGUMENTS` into the script as string literals; never write "see conversation". Shape: **Specialize → Verify → Fix** (a pipeline, one command per item).

```js
export const meta = {
  name: 'tailor-commands',
  description: 'Specialize the generic global commands for {project}',
  phases: [
    { title: 'Specialize', detail: 'one agent per command: read generic template, write project-tailored version' },
    { title: 'Verify', detail: 'each tailored command is concrete, correct, and coherent' },
    { title: 'Fix', detail: 'repair any that drifted or invented a command' },
  ],
}

const SRC = '{user-level commands dir, e.g. /home/you/.claude/commands}'
const DEST = '{repo-root}/.claude/commands'
const PROFILE = `{the full project profile from pre-flight: stack; the EXACT lint/format/test/build/codegen commands (quoted verbatim); module/layer layout; DB + how to inspect it + whether schema deploys independently of clients; observability tooling; protected branches; commit style; where plans/docs live; naming rules; any repo-specific guardrail}`
const INSTRUCTIONS = `{$ARGUMENTS verbatim, or "none"}`

// Templates to specialize — listed from SRC, excluding tailor-commands.md.
const COMMANDS = [ 'plan.md', 'execute.md', 'execute-all.md', 'review.md', 'code-review.md', 'debug.md', 'test.md', 'commit.md', 'backlog.md', 'explore-stack.md', 'extract-shared.md', 'vet-plan.md' ]

const SPEC = `You are SPECIALIZING one generic slash-command for a specific project. The generic template is written to discover the toolchain at run time; your job is to bake the project's REAL values in as the defaults so the command is concrete and ready to run here.

KEEP (do not change): the command's goal, section structure, orchestration logic (Workflow/parallel/pipeline shapes, schemas, fan-out, verify stages), frontmatter shape, and Output/Rules sections.

SPECIALIZE:
- Replace generic "discover the project's lint/test/build command" wording with the EXACT commands from the profile, quoted verbatim, as the defaults the command runs. Keep one short fallback line ("if these change, re-discover from the manifest") so the command survives repo drift — but lead with the concrete values.
- Replace generic "the project's modules/layers, discovered from the repo structure" with the project's ACTUAL layout and named layers from the profile (e.g. the real review/investigation layers, the real module list).
- Bake in project guardrails from the profile: the real protected branches, the real commit/scope style, the real plan/docs location, and — if the project has a database whose schema deploys independently of clients — the project's real migration-safety contract (expand→contract, any version-floor/force-update mechanism, phase tags) stated concretely rather than as a conditional aside. If the project has no DB, drop the migration sections entirely.
- Drop layers/sections that don't apply to this project (e.g. no database layer if there's no DB; no mobile/store concerns for a web service).
- You MAY tailor the frontmatter description to name the project's stack lightly. Keep the model: line.

HARD RULE: never invent a command, path, layer, table, or tool that isn't in the profile. If the profile doesn't establish something the template needs, keep the generic discover-it-at-runtime wording for that piece rather than fabricating a value. Concrete where known; honest "discover it" where not.

UPDATING (when a tailored version already exists at the destination): this is a 3-way reconcile, not a blind overwrite. Treat the GENERIC TEMPLATE as the source of structure + any new improvements, the CURRENT PROFILE as the source of fresh values (commands, paths, layers, guardrails — these supersede whatever the old tailored file had, so a renamed folder or swapped test command gets corrected), and the EXISTING TAILORED FILE as the source of intentional manual edits to preserve where the new profile doesn't contradict them. Net effect: stale values from a previous stack/layout are refreshed, generic-template improvements are pulled in, and hand-tuning survives.

User steering for this project: ${INSTRUCTIONS}`

const VERIFY_SCHEMA = {
  type: 'object',
  required: ['ok', 'problems', 'summary'],
  properties: {
    ok:       { type: 'boolean' },                          // true only if concrete, correct, coherent
    problems: { type: 'array', items: { type: 'string' } }, // invented commands/paths, leftover hand-waving where a value is known, broken structure
    summary:  { type: 'string' },
  },
}

const specializePrompt = (cmd) =>
  `Specialize ONE generic slash-command for this project.\n\n` +
  `READ the generic template (Read tool): ${SRC}/${cmd}\n` +
  `ALSO READ, if it exists, the existing tailored version at ${DEST}/${cmd} — if present, this is an UPDATE: reconcile per the UPDATING rule below (refresh values from the current profile, pull in template improvements, preserve intentional manual edits). If it does NOT exist, generate fresh from the template.\n` +
  `WRITE the project-tailored version (Write tool): ${DEST}/${cmd}\n\n` +
  `PROJECT PROFILE:\n${PROFILE}\n\n` +
  `${SPEC}\n\n` +
  `Read the template (and the existing tailored file if any) fully, specialize/reconcile per the rules using the profile, and Write the result to ${DEST}/${cmd}. ` +
  `Return JSON {changed:[the project-specific values you baked in or refreshed], notes:'anything the verifier should check'}.`

const verifyPrompt = (cmd) =>
  `Verify the project-tailored command at ${DEST}/${cmd} against this project profile:\n${PROFILE}\n\n` +
  `Check: (1) every command/path/layer/table/tool it names actually exists in the profile — flag anything INVENTED; ` +
  `(2) where the profile establishes a concrete value, the command USES it (not leftover "discover it" hand-waving); ` +
  `(3) where the profile does NOT establish a value, the command honestly keeps discover-at-runtime wording (not a fabricated value); ` +
  `(4) the command's goal, structure, and orchestration logic are preserved and coherent; ` +
  `(5) sections that don't apply to this project were dropped, not left dangling; ` +
  `(6) on an update, NO stale value from a previous stack/layout survives — every command/path/layer matches the CURRENT profile (flag leftovers like an old test command or a renamed folder). ` +
  `Return JSON {ok, problems:[concrete issues], summary}. Default ok=false if anything is invented, stale, or incoherent.`

const fixPrompt = (cmd, v) =>
  `The tailored command at ${DEST}/${cmd} failed verification. Problems:\n` +
  (v && v.problems && v.problems.length ? v.problems.map((p, i) => `${i + 1}. ${p}`).join('\n') : '(none listed)') +
  `\n\nProject profile:\n${PROFILE}\n\n${SPEC}\n\n` +
  `Read ${DEST}/${cmd}, fix every problem (use real profile values; revert any invented value to honest discover-at-runtime wording; restore structure), Write it back to ${DEST}/${cmd}, and return JSON {ok, problems:[remaining], summary}.`

const results = await pipeline(
  COMMANDS,
  (cmd) => agent(specializePrompt(cmd), { label: `tailor:${cmd}`, phase: 'Specialize' }).then(r => ({ cmd, r })),
  (prev, cmd) => agent(verifyPrompt(cmd), { label: `verify:${cmd}`, phase: 'Verify', schema: VERIFY_SCHEMA }).then(v => ({ ...prev, v })),
  (prev, cmd) => (prev.v && prev.v.ok)
    ? prev
    : agent(fixPrompt(cmd, prev.v), { label: `fix:${cmd}`, phase: 'Fix', schema: VERIFY_SCHEMA }).then(v2 => ({ ...prev, v: v2, fixed: true })),
)

return results.map((x, i) => x
  ? { cmd: x.cmd, ok: x.v ? x.v.ok : false, fixed: !!x.fixed, problems: x.v ? x.v.problems : ['agent died'], summary: x.v ? x.v.summary : 'died' }
  : { cmd: COMMANDS[i], ok: false, fixed: false, problems: ['pipeline dropped this item'], summary: 'dropped' })
```

## After the workflow returns

- Confirm each tailored file exists under the target `.claude/commands/`.
- Report (bullets): "first run" or "update (N existing)", the project profile in one line, the list of commands written (✓ ok / ⚠ needed fixes / ✗ failed), and any `problems` left unresolved.
- On an update, point the user at `git diff -- .claude/commands/` so they can see exactly what changed (refreshed values vs preserved edits) — the tracked diff is the safety net for the in-place reconcile.
- Remind the user: these are now this project's overrides (project scope shadows the global generic ones here), and the files are **uncommitted** — they should review the generated commands and commit them with the project's own convention. Don't commit or push yourself.

## Rules

- **Repo is the source of truth.** `$ARGUMENTS` steers; it never overrides what the repo actually declares. Never fabricate a command/path/layer that isn't in the profile.
- **Concrete where known, honest where not.** Bake in real values; keep discover-at-runtime wording only for what the profile didn't establish.
- **Same names, project scope.** Generated files reuse the generic command names so they cleanly shadow the globals in this project. Write only into this project's `.claude/commands/`.
- **Preserve goals + orchestration.** Specialize the inputs, not the strategy — keep each command's structure and fan-out logic intact.
- **Re-run = update, not clobber.** When a tailored file already exists, reconcile it (refresh profile-derived values, pull in template improvements, keep intentional manual edits) instead of overwriting blind. Never delete a tailored command the project no longer maps to — leave it for the user.
- **No commit, no push.** Hand back uncommitted files for the user to review.
- **One round of questions max** before running the workflow.

## Output style

- Brief. No preamble, no recap.
- Lead with the profile line and the written-commands list.
- Bullets over prose.
