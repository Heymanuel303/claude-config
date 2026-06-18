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
