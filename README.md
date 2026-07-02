# claude-config

Versioned, **project-agnostic** Claude Code slash-commands. The original set was
written for one specific repo (a Flutter/Dart + Supabase monorepo); these are
rewritten so they work on **any** codebase — Python, Rust, Go, TypeScript, Java,
etc. — by *discovering* each project's build/test/lint commands and module layout
instead of hardcoding them.

## How it's wired

`commands/` is symlinked into the global Claude Code config:

```
~/.claude/commands  ->  ~/projects/claude-config/commands
```

So editing a file in `commands/` here is **immediately live** in every session,
and the whole set is version-controlled in this git repo.

### Install / re-link (e.g. on a new machine)

```bash
./install.sh          # symlinks commands/ + puts scripts/ on PATH (idempotent; honors $CLAUDE_CONFIG_DIR)
```

`install.sh` also symlinks every `scripts/*.sh` into `~/.local/bin` (sans `.sh`),
so the shipped tools run by name from any repo root (e.g. `plans-summary`). If
`~/.local/bin` isn't on your PATH it says so; the matching slash commands work
regardless. The script refuses to clobber a non-empty real `~/.claude/commands` —
move those files into `commands/` first if you have any.

## The commands

A coherent plan→execute→review system plus standalone investigators. All write
plans/reports under `docs/` in whatever repo you run them in.

| Command | What it does |
| --- | --- |
| `/plan` | Draft a durable multi-phase plan into `docs/plans/{date}-{feature}/` (workflow: explore + draft each phase in parallel). |
| `/vet-plan` | Fact-check a not-yet-executed plan against the real repo, one checker per phase. |
| `/execute` | Execute a single plan phase cold (solo or fan-out per the phase's `Execution:` field), verify, write tests. |
| `/execute-all` | Drive a whole plan end-to-end: execute → independent review → fix-loop → commit, per phase, autonomously. |
| `/task` | Complete an arbitrary task outside any plan — human-in-the-middle: you start the code by hand, it reads your uncommitted edits as the intent, finishes in your direction, and records `docs/tasks/{date}-{slug}.md` for `/test` + `/commit` to pick up. |
| `/review` | Pre-release review of the committed work that implemented a plan — one reviewer per discovered layer. |
| `/code-review` | Deep DX/quality scan of the codebase against five engineering principles (was `dart-review`; now language-agnostic, inline workflow). |
| `/debug` | Root-cause a bug by fanning out parallel read-only investigators across layers + observability sources. |
| `/clarify` | Read-only "does this belong here / where should it go?" verdict on tagged files + uncommitted (incl. worktree) changes. Grounds placement advice in repo conventions; no edits. |
| `/test` | Write tests for the current session's changes; run them in an isolated subagent. Tests only — never edits production code; halts and reports if a test exposes a genuine bug. |
| `/commit` | Stage + commit with a Conventional Commits message, including plan-phase and `/task`-record bookkeeping. |
| `/backlog` | Capture a raw idea as a date-prefixed brief in `docs/plans/backlog/` after a shallow skim. |
| `/explore-stack` | Read-only cross-layer investigation of a topic; synthesizes a map of where it shows up. |
| `/extract-shared` | Find code in multiple modules that should be extracted into a shared package/library. |
| `/tailor-commands` | Generate project-specialized versions of these commands into the current project's `.claude/commands/` — same goals, but with the project's real stack/commands/layers baked in. The inverse of the generic set. |
| `/plans` | Status summary of `docs/plans/` (in progress / planned / completed / other, with dates + phase counts). Thin wrapper over the `plans-summary` script. |

## Scripts / tools

Deterministic helpers in `scripts/`, shipped alongside the commands. Each has
**two entry points sharing one implementation**: run it from a terminal by name
(via the `~/.local/bin` symlink), or invoke the matching slash command inside
Claude (which just shells out to the same script — no duplicated logic).

| Script | Slash command | What it does |
| --- | --- | --- |
| `plans-summary` | `/plans` | Group `docs/plans/` by status with dates + phase counts. `plans-summary --active` / `completed` / `planned`; `PLANS_DIR=… ` to override. |

### Generic default ↔ tailored override

The commands here are the **universal default** for every project. For a project
you work in often, run `/tailor-commands` *inside it* to emit specialized copies
into that project's `.claude/commands/`. Because **project-scope commands shadow
user-scope ones of the same name**, the tailored `/plan` (etc.) runs there while
every other repo keeps the generic one. Specific→generic built this set;
`/tailor-commands` goes generic→specific on demand.

## Editing

Edit files in `commands/` directly — changes are live via the symlink. Commit
them here to version the change. Keep each command **toolchain-agnostic**: tell
the reader to discover the project's commands and structure rather than naming a
specific tool.
