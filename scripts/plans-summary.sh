#!/usr/bin/env bash
# Summarize docs/plans/: group every plan by status and show its date, name and
# phase count. A "plan" is a dated folder with a 00-* overview (or a nested
# sub-folder that has one, or a single dated .md file). Phase count = NN-*.md
# files, excluding the 00-* overview and any 99-* appendix.
#
#   plans-summary            # in progress + planned + other listed; completed = count only
#   plans-summary --active   # only in progress + planned
#   plans-summary completed  # one group: completed | in-progress | planned | other
#                            #   aliases: done=completed, wip=in-progress
#   PLANS_DIR=/path plans-summary   # override the plans dir (default: <repo>/docs/plans)
#
# Self-contained: depends only on bash + coreutils. Run from anywhere inside a
# repo (resolves the git root) or point PLANS_DIR at any plans directory.
set -euo pipefail
shopt -s nullglob

die() { printf 'plans-summary: %s\n' "$*" >&2; exit 1; }

usage() { sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; }

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PLANS_DIR="${PLANS_DIR:-$ROOT/docs/plans}"

# ---- args -------------------------------------------------------------------
FILTER=""   # "" = all groups, "active", or a single bucket key
case "${1:-}" in
  "")                          ;;
  --active)                    FILTER="active" ;;
  -h|--help)                   usage; exit 0 ;;
  done|completed)              FILTER="completed" ;;
  wip|in-progress|inprogress)  FILTER="in-progress" ;;
  planned)                     FILTER="planned" ;;
  other)                       FILTER="other" ;;
  *) die "unknown arg: $1 (use --active | completed | in-progress | planned | other)" ;;
esac
[[ -d "$PLANS_DIR" ]] || die "plans dir not found: $PLANS_DIR"

# ---- helpers ----------------------------------------------------------------
# Normalize a raw "**Status:**" value (e.g. "planned (DRAFT — …)") into a bucket.
bucket_of() {
  local s; s="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"
  s="${s%%[ (]*}"   # keep first token; drop a trailing " …" or "(…)" qualifier
  case "$s" in
    completed)   echo completed ;;
    in-progress) echo in-progress ;;
    planned)     echo planned ;;
    *)           echo other ;;
  esac
}

# First "**Field:**" value in a markdown file (Status, Created, …).
field() { # <file> <Field>
  grep -m1 -iE "^\*\*$2:\*\*" "$1" 2>/dev/null | sed -E "s/^\*\*$2:\*\* *//I" | tr -d '\r' || true
}

# Phase files in a dir: NN-*.md, excluding the 00-* overview and 99-* appendix.
count_phases() { # <dir>
  local f b n=0
  for f in "$1"/[0-9][0-9]-*.md; do
    b="$(basename "$f")"
    case "$b" in 00-*|99-*) continue ;; esac
    n=$((n + 1))
  done
  echo "$n"
}

# Overview file = first 00-*.md (overview, architecture, …). Fails if none.
overview_of() { local f; for f in "$1"/00-*.md; do echo "$f"; return 0; done; return 1; }

# Leading YYYY-MM-DD of a name, else empty.
date_prefix() { [[ "$1" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2}) ]] && echo "${BASH_REMATCH[1]}" || true; }

REC="$(mktemp)"; trap 'rm -f "$REC"' EXIT
emit() { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >>"$REC"; }  # bucket date phases name

# Record one plan directory (standard, variant-overview, nested-child or checklist).
process_plan_dir() { # <dir> <display-name> <fallback-date>
  local dir="$1" name="$2" fdate="$3" ov status="" date="" phases
  if ov="$(overview_of "$dir")"; then
    status="$(field "$ov" Status)"
    date="$(field "$ov" Created)"
  fi
  # No overview, or an overview without a Status line: scan any md in the dir.
  [[ -n "$status" ]] || status="$(grep -m1 -ihE '^\*\*Status:\*\*' "$dir"/*.md 2>/dev/null \
    | sed -E 's/^\*\*Status:\*\* *//I' | tr -d '\r' || true)"
  [[ -n "$date" ]] || date="$fdate"
  phases="$(count_phases "$dir")"
  emit "$(bucket_of "$status")" "${date:-0000-00-00}" "$phases" "$name"
}

# ---- discover plans ---------------------------------------------------------
for entry in "$PLANS_DIR"/*; do
  base="$(basename "$entry")"
  [[ "$base" == "backlog" ]] && continue

  # Top-level single-file plan: YYYY-MM-DD-slug.md
  if [[ -f "$entry" && "$base" == *.md ]]; then
    d="$(date_prefix "$base")"; name="${base%.md}"; name="${name#"${d}"-}"
    emit "$(bucket_of "$(field "$entry" Status)")" "${d:-0000-00-00}" "0" "$name"
    continue
  fi
  [[ -d "$entry" ]] || continue

  pdate="$(date_prefix "$base")"; pslug="${base#"${pdate}"-}"

  if overview_of "$entry" >/dev/null; then
    process_plan_dir "$entry" "$pslug" "$pdate"
    continue
  fi

  # No overview of its own: each child folder that has one is a separate plan.
  nested=0
  for sub in "$entry"/*/; do
    sub="${sub%/}"
    overview_of "$sub" >/dev/null || continue
    nested=1
    process_plan_dir "$sub" "$pslug/$(basename "$sub")" "$pdate"
  done
  # Otherwise it's a lone doc dir (e.g. a checklist) — record it best-effort.
  [[ "$nested" == 0 ]] && process_plan_dir "$entry" "$pslug" "$pdate"
done

# ---- render -----------------------------------------------------------------
phase_label() { case "$1" in 0) echo "—" ;; 1) echo "1 phase" ;; *) echo "$1 phases" ;; esac; }
bucket_count() { awk -F'\t' -v k="$1" '$1==k{n++} END{print n+0}' "$REC"; }

print_group() { # <bucket-key> <Heading>
  local rows; rows="$(awk -F'\t' -v k="$1" '$1==k' "$REC" | sort -t$'\t' -k2,2r -k4,4)"
  [[ -z "$rows" ]] && return
  printf '\n%s (%s)\n' "$2" "$(printf '%s\n' "$rows" | grep -c '')"
  while IFS=$'\t' read -r _ date phases name; do
    printf '  %-10s  %-46s  %s\n' "$date" "$name" "$(phase_label "$phases")"
  done <<<"$rows"
}

# Collapsed one-liner for a group we don't enumerate (completed in the default view).
print_collapsed() { # <bucket-key> <Heading> <hint>
  local n; n="$(bucket_count "$1")"
  [[ "$n" -eq 0 ]] && return
  printf '\n%s (%s) — not listed; run `%s` to see them\n' "$2" "$n" "$3"
}

total="$(grep -c '' "$REC" || true)"
printf 'docs/plans — %s plans  ·  %s in progress · %s planned · %s completed · %s other\n' \
  "$total" "$(bucket_count in-progress)" "$(bucket_count planned)" \
  "$(bucket_count completed)" "$(bucket_count other)"

case "$FILTER" in
  "")          print_group in-progress "IN PROGRESS"; print_group planned "PLANNED"
               print_group other "OTHER"
               print_collapsed completed "COMPLETED" "plans-summary completed" ;;
  active)      print_group in-progress "IN PROGRESS"; print_group planned "PLANNED" ;;
  in-progress) print_group in-progress "IN PROGRESS" ;;
  planned)     print_group planned "PLANNED" ;;
  completed)   print_group completed "COMPLETED" ;;
  other)       print_group other "OTHER" ;;
esac
