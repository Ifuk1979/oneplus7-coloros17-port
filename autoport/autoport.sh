#!/bin/bash
# OnePlus7Port AutoPort - turn a OnePlus PYB110 ColorOS 17 full OTA zip into a flash-ready OnePlus 7 Pro (GM1910) fastboot package.
#
#   sudo bash autoport.sh <PYB110 full OTA zip> [options]      (WSL: wsl -u root, then the same command)
#
# Options:
#   --firmware ZIP  the OnePlus 7 Pro OxygenOS 11 H.40 full OTA: its firmware goes into the package (else: no firmware)
#   --base DIR     where work files, tools and the release go (default /root/op7-autoport; must be ext4, not /mnt/c)
#   --rev N        rebuild counter in the version name (default 2: ColorOS17.0.1.201(los20261011-r2))
#   --from NN      restart at reforge stage NN (01 10 11 12 13 14 18 20 30) or "package"; earlier results are kept
#   --check        only check the host, install the toolchain and read the ROM; build nothing
#   --no-zip       leave the release as a folder (skip the 12 GB zip)
#   --no-apt       do not run apt (all packages in lib/bootstrap.sh must already be installed)
#
# Steps: host check -> toolchain (apt + secilc 3.11) -> read the ROM -> reforge stages 01-30 (the same scripts that built the
# published release) -> release folder + zip with installers. Takes about 1-2 hours and ~80 GB of free space.
set -euo pipefail
PORT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PORT_ROOT
. "$PORT_ROOT/autoport/lib/common.sh"
. "$PORT_ROOT/autoport/lib/bootstrap.sh"
. "$PORT_ROOT/autoport/lib/donor.sh"
. "$PORT_ROOT/autoport/lib/package.sh"
. "$PORT_ROOT/autoport/lib/firmware.sh"

STAGES="01 10 11 12 13 14 18 20 30"
ROM=""; FWZIP=""; BASE=/root/op7-autoport; REV=2; FROM=""; CHECK=0; NO_ZIP=0; NO_APT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --base) BASE=${2:?}; shift ;;
    --firmware) FWZIP=$(readlink -f "${2:?}"); shift ;;
    --rev) REV=${2:?}; shift ;;
    --from) FROM=${2:?}; shift ;;
    --check) CHECK=1 ;;
    --no-zip) NO_ZIP=1 ;;
    --no-apt) NO_APT=1 ;;
    -h|--help) sed -n 2,17p "$0"; exit 0 ;;
    -*) die "unknown option $1 (see --help)" ;;
    *) [ -z "$ROM" ] || die "only one ROM zip, got '$ROM' and '$1'"; ROM=$1 ;;
  esac
  shift
done
[ -n "$ROM" ] || { sed -n 2,17p "$0"; exit 1; }
ROM=$(readlink -f "$ROM")
case "$REV" in *[!0-9]*|"") die "--rev must be a number" ;; esac
if [ -n "$FROM" ] && [ "$FROM" != package ]; then case " $STAGES " in *" $FROM "*) ;; *) die "--from must be one of: $STAGES package" ;; esac; fi
export NO_ZIP NO_APT

WORK="$BASE/work"; OUT="$WORK/out"; TOOLS="$BASE/tools"; RELDIR="$BASE/release"
mkdir -p "$BASE" "$PORT_ROOT/docs/logs"
LOG="$PORT_ROOT/docs/logs/$(date +%F)-autoport.log"
exec > >(tee -a "$LOG") 2>&1
say "OnePlus7Port AutoPort  ($PORT_ROOT, log $LOG)"

# ---- 1. host + toolchain
host_check; loop_check
[ -d "$WORK/cache" ] && MIN_FREE_GB=${MIN_FREE_GB_RESUME:-30}   # resuming: the big extracts already exist
work_check "$BASE"
toolchain "$TOOLS"

# ---- 2. bundled inputs (made by make-bundle.sh; never the user's ROM)
say "checking the bundled inputs"
[ -f "$PORT_ROOT/BUNDLE-SHA256SUMS" ] || die "BUNDLE-SHA256SUMS missing: this is not an AutoPort bundle (in the repo, build one with autoport/make-bundle.sh)"
if [ ! -f "$BASE/.bundle-verified" ] || [ "$(cat "$BASE/.bundle-verified")" != "$(sha256sum < "$PORT_ROOT/BUNDLE-SHA256SUMS")" ]; then
  ( cd "$PORT_ROOT" && sha256sum -c --quiet BUNDLE-SHA256SUMS ) || die "bundle files are damaged or missing (re-extract the AutoPort archive)"
  sha256sum < "$PORT_ROOT/BUNDLE-SHA256SUMS" > "$BASE/.bundle-verified"
fi
say "bundle OK ($(wc -l < "$PORT_ROOT/BUNDLE-SHA256SUMS") files)"

# ---- 3. the ROM
mkdir -p "$WORK"
donor_prepare "$ROM"
mkdir -p "$WORK/avb"
if [ ! -s "$WORK/avb/port_key.pem" ]; then
  say "generating this build's own AVB signing key ($WORK/avb/port_key.pem)"
  openssl genrsa -out "$WORK/avb/port_key.pem" 4096 2>/dev/null; chmod 0600 "$WORK/avb/port_key.pem"
fi
cat >> "$WORK/autoport.env" <<EOF
WORK='$WORK'
OUT='$OUT'
AVB_KEY='$WORK/avb/port_key.pem'
MAGISK_APK='$PORT_ROOT/StockRom/Magisk/Magisk-v31.0.apk'
EOF
FIRMWARE_DIR=""
if [ -n "$FWZIP" ]; then firmware_prepare "$FWZIP" "$WORK/firmware"; FIRMWARE_DIR="$WORK/firmware"
else warn "no --firmware: the package will not contain firmware (the phone must already run OxygenOS 11 H.40)"; fi
[ "$CHECK" = 1 ] && { say "--check done: host, toolchain and ROM are fine. Run again without --check to build."; exit 0; }

# ---- 4. reforge stages
export AUTOPORT_ENV="$WORK/autoport.env" DONOR=pyb110 LOS=baseline REV WORK OUT
run=""; started=0
for s in $STAGES; do
  if [ -n "$FROM" ] && [ "$started" = 0 ] && [ "$s" != "$FROM" ]; then continue; fi
  started=1; run="$run $s"
done
[ "$FROM" = package ] && run=""
if [ -n "$run" ]; then
  say "reforge stages:$run"
  # shellcheck disable=SC2086
  bash "$PORT_ROOT/tools-reforge/run.sh" $run || die "a reforge stage failed (log in $PORT_ROOT/docs/logs). Fix the cause and resume with --from <stage>"
fi

# ---- 5. release
. "$WORK/autoport.env"
RELEASE_TAG=$(bash -c '. "$1" >/dev/null 2>&1; printf %s "$RELEASE_TAG"' _ "$PORT_ROOT/tools-reforge/config.env")
[ -n "$RELEASE_TAG" ] || die "cannot read RELEASE_TAG from tools-reforge/config.env"
package_release "$OUT/smoke" "$RELDIR"
say "done. Flash with the installer in $RELDIR/ColorOS$DONOR_COLOROS($RELEASE_TAG) (see its README.md)."
