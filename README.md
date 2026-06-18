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
./install.sh          # creates the symlink (idempotent; honors $CLAUDE_CONFIG_DIR)
```

The script refuses to clobber a non-empty real `~/.claude/commands` — move those
files into `commands/` first if you have any.

## The commands

A coherent plan→execute→review system plus standalone investigators. All write
plans/reports under `docs/` in whatever repo you run them in.

| Command | What it does |
| --- | --- |
| `/plan` | Draft a durable multi-phase plan into `docs/plans/{date}-{feature}/` (workflow: explore + draft each phase in parallel). |
| `/vet-plan` | Fact-check a not-yet-executed plan against the real repo, one checker per phase. |
| `/execute` | Execute a single plan phase cold (solo or fan-out per the phase's `Execution:` field), verify, write tests. |
| `/execute-all` | Drive a whole plan end-to-end: execute → independent review → fix-loop → commit, per phase, autonomously. |
| `/review` | Pre-release review of the committed work that implemented a plan — one reviewer per discovered layer. |
| `/code-review` | Deep DX/quality scan of the codebase against five engineering principles (was `dart-review`; now language-agnostic, inline workflow). |
| `/debug` | Root-cause a bug by fanning out parallel read-only investigators across layers + observability sources. |
| `/test` | Write tests for the current session's changes; run them in an isolated subagent; fix until green. |
| `/commit` | Stage + commit with a Conventional Commits message, including plan-phase bookkeeping. |
| `/backlog` | Capture a raw idea as a date-prefixed brief in `docs/plans/backlog/` after a shallow skim. |
| `/explore-stack` | Read-only cross-layer investigation of a topic; synthesizes a map of where it shows up. |
| `/extract-shared` | Find code in multiple modules that should be extracted into a shared package/library. |

## Editing

Edit files in `commands/` directly — changes are live via the symlink. Commit
them here to version the change. Keep each command **toolchain-agnostic**: tell
the reader to discover the project's commands and structure rather than naming a
specific tool.
