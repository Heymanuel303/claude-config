#!/usr/bin/env bash
# Link this repo's commands into the global Claude Code config so that
# editing the versioned files here is reflected everywhere immediately.
#
# Usage:  ./install.sh
# Honors CLAUDE_CONFIG_DIR if set (defaults to ~/.claude).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$REPO_DIR/commands"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
TARGET="$CLAUDE_DIR/commands"

[ -d "$SRC" ] || { echo "ERROR: $SRC does not exist" >&2; exit 1; }

if [ -L "$TARGET" ]; then
  echo "Replacing existing symlink at $TARGET"
  rm "$TARGET"
elif [ -d "$TARGET" ]; then
  if [ -z "$(ls -A "$TARGET" 2>/dev/null)" ]; then
    echo "Removing empty directory at $TARGET"
    rmdir "$TARGET"
  else
    echo "ERROR: $TARGET is a non-empty real directory." >&2
    echo "       Move its contents into $SRC, then re-run this script." >&2
    exit 1
  fi
elif [ -e "$TARGET" ]; then
  echo "ERROR: $TARGET exists and is not a directory/symlink. Remove it manually." >&2
  exit 1
fi

mkdir -p "$CLAUDE_DIR"
ln -s "$SRC" "$TARGET"
echo "Linked $TARGET -> $SRC"

# ---- shipped scripts onto PATH ---------------------------------------------
# Symlink each executable in scripts/ into ~/.local/bin (sans .sh) so they run
# from any repo root, e.g. `plans-summary`. The /plans slash command runs the
# same script, so terminal and Claude share one implementation.
BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
if [ -d "$REPO_DIR/scripts" ]; then
  mkdir -p "$BIN_DIR"
  for f in "$REPO_DIR"/scripts/*.sh; do
    [ -e "$f" ] || continue
    name="$(basename "$f" .sh)"
    ln -sf "$f" "$BIN_DIR/$name"
    echo "Linked $BIN_DIR/$name -> $f"
  done
  case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) echo "NOTE: $BIN_DIR is not on your PATH — add it to use the scripts by name (the /plans command works regardless)." ;;
  esac
fi
