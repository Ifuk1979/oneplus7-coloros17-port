#!/bin/bash
# tools-reforge/lib/common.sh - helpers sourced by run.sh and every stage.

TODAY="$(date +%F)"
say()  { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
warn() { printf '[%s] WARN: %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
die()  { printf '[%s] ERROR: %s\n' "$(date +%H:%M:%S)" "$*" >&2; exit 1; }

need_root() { [ "$(id -u)" = 0 ] || die "run as root in WSL (wsl -u root)"; }

# stamp files: a stage is skipped when its stamp holds the same input fingerprint
stamp_file() { echo "$WORK/stamps/$1.done"; }
stamp_ok()   { [ -f "$(stamp_file "$1")" ] && [ "$(cat "$(stamp_file "$1")")" = "$2" ]; }
stamp_set()  { mkdir -p "$WORK/stamps"; printf '%s' "$2" > "$(stamp_file "$1")"; }

# fingerprint = size+mtime of each input (cheap); full sha256 only in --hash mode
fingerprint() { for f in "$@"; do [ -e "$f" ] && stat -c '%n %s %Y' "$f"; done | sha256sum | cut -d' ' -f1; }

size_of() { stat -c %s "$1" 2>/dev/null; }

# check_sha FILE EXPECTED_SHA256 -> 0 ok
check_sha() {
  local got; got="$(sha256sum "$1" | cut -d' ' -f1)"
  [ "$got" = "$2" ] || { warn "sha256 mismatch for $1: got $got want $2"; return 1; }
}

have_tool() { command -v "$1" >/dev/null 2>&1; }

# every stage runs in its own mount namespace so loop mounts never collide with other sessions
# usage: in_ns <script> [args]   (stages call this for anything that mounts)
in_ns() { unshare --mount --propagation private "$@"; }
