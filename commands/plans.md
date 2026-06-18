---
description: Summarize docs/plans/ — group every plan by status (in progress / planned / completed / other) with its date, name, and phase count. Runs the shipped plans-summary script; deterministic, no analysis.
model: haiku
---

Show a status summary of the repo's `docs/plans/`. This is a thin wrapper around the shipped `plans-summary` script (the same one you can run from a terminal) — run it and surface its output. Do not reimplement the summary yourself; the script is the source of truth.

`$ARGUMENTS` is passed straight through as the script's filter:

- (none) → in-progress + planned + other listed; completed collapsed to a count
- `--active` → only in-progress + planned
- `completed` (alias `done`) / `in-progress` (alias `wip`) / `planned` / `other` → just that group

## Run it

Locate the script via the commands symlink (falls back to PATH), then run it from the repo root with the passed-through args:

```bash
SCRIPT="$(dirname "$(readlink -f "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/commands")")/scripts/plans-summary.sh"
[ -x "$SCRIPT" ] || SCRIPT="$(command -v plans-summary || true)"
[ -n "$SCRIPT" ] || { echo "plans-summary not found — run claude-config/install.sh"; exit 1; }
"$SCRIPT" $ARGUMENTS
```

## Output

- Print the script's output verbatim in a fenced block — it's already formatted.
- If the script exits non-zero (e.g. "plans dir not found"), show its error and stop; don't guess.
- Add at most ONE optional line afterward only if it's useful (e.g. "Newest in-progress: <name> — `/execute-all` to drive it"). No other commentary.

## Rules

- **Run the script; don't reimplement.** The grouping/counting logic lives in `plans-summary.sh` so the terminal and this command stay identical.
- **Read-only.** Never edits plans or files.
- **No analysis unless asked.** This is a status readout, not a review.
