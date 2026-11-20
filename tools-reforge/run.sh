#!/bin/bash
# tools-reforge/run.sh - run reforge stages (WSL, as root).
#   run.sh --list                 list stages
#   run.sh 00 [01 ...]            run the named stages (number prefix)
#   run.sh --all                  run every stage in order (stops at the first failure)
# Options (before the stages): --hash  full sha256 of the source files in preflight (slow, ~25 GB)
# Environment: LOS=baseline|next, WORK=..., OUT=...   (see config.env)
# Each stage logs to docs/logs/YYYY-MM-DD-reforge-<stage>.log (also on screen).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.env
. "$HERE/config.env"
# shellcheck source=lib/common.sh
. "$HERE/lib/common.sh"
export HERE PROJECT WORK OUT LOGDIR LOS
export HASH_MODE=0

stages=()
while [ $# -gt 0 ]; do
  case "$1" in
    --hash) HASH_MODE=1 ;;
    --list) ls "$HERE/stages" | sed 's/\.sh$//'; exit 0 ;;
    --all)  for f in "$HERE"/stages/*.sh; do stages+=("$(basename "$f" .sh | cut -d- -f1)"); done ;;
    -h|--help) sed -n 2,9p "$0"; exit 0 ;;
    [0-9][0-9]) stages+=("$1") ;;
    *) die "unknown argument '$1' (try --help)" ;;
  esac
  shift
done
[ "${#stages[@]}" -gt 0 ] || die "no stage given (try --list or --all)"
export HASH_MODE
mkdir -p "$LOGDIR"
for n in "${stages[@]}"; do
  script="$(ls "$HERE"/stages/"$n"-*.sh 2>/dev/null | head -1)"
  [ -n "$script" ] || die "no stage $n"
  name="$(basename "$script" .sh)"
  log="$LOGDIR/$TODAY-reforge-$name.log"
  say "=== stage $name (log: $log)"
  bash "$script" 2>&1 | tee "$log"
  rc=${PIPESTATUS[0]}
  [ "$rc" = 0 ] || die "stage $name failed (exit $rc), see $log"
done
say "all requested stages done"
