# autoport/lib/common.sh - helpers sourced by autoport.sh and make-bundle.sh.

say()  { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
warn() { printf '[%s] WARN: %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
die()  { printf '[%s] ERROR: %s\n' "$(date +%H:%M:%S)" "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# sha256_is FILE SHA -> 0 when equal
sha256_is() { [ "$(sha256sum "$1" | cut -d' ' -f1)" = "$2" ]; }

# free space in GB on the filesystem holding $1 (created if missing)
free_gb() { mkdir -p "$1"; df -BG --output=avail "$1" | tail -1 | tr -dc 0-9; }

# filesystem type of $1
fs_type() { df --output=fstype "$1" | tail -1 | tr -d ' '; }
