#!/usr/bin/env bash
# OnePlus 7 Pro (GM1910, guacamole) ColorOS 17.0.1.201(los20261011-r2) - complete fastboot package installer (Linux/macOS/Git Bash).
#
# Complete package: every partition the port needs is in images/ (firmware, dtbo, vbmeta, boot, vendor, system) plus
# my_stock-pyb201.img, which the port mounts from /data/port. No earlier port package is needed.
#
#   bash ./install.sh                 NoRoot install (asks the WIPE question after flashing)
#   bash ./install.sh --magisk        Magisk v31.0 install (Magisk-patched boot + Magisk app)
#   bash ./install.sh --dry-run       check images, phone, slot, root and free space; change nothing
#   bash ./install.sh --wipe          clean install: wipe /data without asking (needed when coming from another ROM)
#   bash ./install.sh --no-wipe       keep /data without asking (upgrade of this port)
#   bash ./install.sh --confirm-device  accept a fastboot product other than msmnile without asking
#
# Start with the phone either booted into this port with USB debugging on (upgrade, keeps data), or in fastboot mode
# (bootloader). Only the ACTIVE slot is written. Requires an unlocked bootloader and platform-tools (adb, fastboot) on PATH.
set -euo pipefail
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*'   # Git Bash: keep /data/... phone paths as they are

RELEASE='ColorOS17.0.1.201(los20261011-r2)'
MYSTOCK_NAME=my_stock-pyb201.img
FIRMWARE="abl aop bluetooth cmnlib cmnlib64 devcfg dsp hyp keymaster modem qupfw storsec tz xbl xbl_config"   # OxygenOS 11 H.40 firmware (LOGO not touched)
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
say() { printf '%s\n' "$*"; }
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd); cd "$SCRIPT_DIR"
FASTBOOT=${FASTBOOT:-fastboot}; ADB=${ADB:-adb}
VARIANT=noroot; DRY=0; WIPE_MODE=ask; CONFIRM_DEVICE=0
for arg in "$@"; do
  case "$arg" in
    --magisk) VARIANT=magisk ;;
    --dry-run) DRY=1 ;;
    --wipe) [[ $WIPE_MODE != no ]] || die '--wipe and --no-wipe cannot be combined.'; WIPE_MODE=yes ;;
    --no-wipe) [[ $WIPE_MODE != yes ]] || die '--wipe and --no-wipe cannot be combined.'; WIPE_MODE=no ;;
    --confirm-device) CONFIRM_DEVICE=1 ;;
    *) die "Unknown option '$arg' (known: --magisk --dry-run --wipe --no-wipe --confirm-device)." ;;
  esac
done
command -v "$FASTBOOT" >/dev/null 2>&1 || die 'fastboot is not on PATH (install Android platform-tools).'
command -v "$ADB" >/dev/null 2>&1 || die 'adb is not on PATH (install Android platform-tools).'
if [[ $VARIANT == magisk ]]; then BOOT_IMG=images/boot-magisk31.img; else BOOT_IMG=images/boot.img; fi

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print tolower($1)}'
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print tolower($1)}'
  else die 'Install sha256sum (Linux) or shasum (macOS) first.'; fi
}
expected() { awk -v f="$1" '$2==f || $2=="*"f {print tolower($1)}' images/SHA256SUMS; }
check_image() {
  local f=$1 exp act
  [[ -f "images/$f" ]] || die "Missing image: images/$f"
  exp=$(expected "$f"); [[ -n "$exp" ]] || die "images/SHA256SUMS has no entry for $f"
  printf 'Checking %-26s ' "$f"; act=$(sha256 "images/$f")
  [[ "$act" == "$exp" ]] || { echo; die "SHA-256 mismatch for images/$f: $act"; }; echo OK
}
say "== $RELEASE, $VARIANT install =="
for f in $(printf 'firmware/%s.img ' $FIRMWARE) dtbo.img vbmeta.img "$(basename "$BOOT_IMG")" vendor.img system.img "$MYSTOCK_NAME"; do check_image "$f"; done
[[ $VARIANT != magisk ]] || check_image Magisk-v31.0.apk
MYSTOCK_SHA=$(expected "$MYSTOCK_NAME"); MYSTOCK_SIZE=$(wc -c < "images/$MYSTOCK_NAME" | tr -d ' ')

ash() { "$ADB" shell "$@" | tr -d '\r'; }
ROOT=''   # command prefix that gives root on the phone ('' = adb root shell, 'su -c' = Magisk)
detect_root() {
  if [[ "$(ash id -u 2>/dev/null)" == 0 ]]; then ROOT=''; return 0; fi
  "$ADB" root >/dev/null 2>&1 || true; sleep 3; "$ADB" wait-for-device
  if [[ "$(ash id -u 2>/dev/null)" == 0 ]]; then ROOT=''; return 0; fi
  if [[ "$(ash su -c id -u 2>/dev/null)" == 0 ]]; then ROOT=su; return 0; fi
  return 1
}
rsh() { if [[ -z "$ROOT" ]]; then ash "$1"; else ash su -c "$1"; fi; }
# Copy my_stock into /data/port: push as .new, check the SHA-256 on the phone, keep the old image as -prev, swap.
stage_mystock() {
  local free
  rsh "mkdir -p /data/port && chmod 0750 /data/port"
  if [[ "$(rsh "[ -f /data/port/$MYSTOCK_NAME ] && sha256sum /data/port/$MYSTOCK_NAME" | awk '{print $1}')" == "$MYSTOCK_SHA" ]]; then
    say "/data/port/$MYSTOCK_NAME is already this release's my_stock; not copied again."; COPIED=0; return 0
  fi
  free=$(rsh "df -k /data | tail -1" | awk '{print $4}')
  (( free * 1024 > MYSTOCK_SIZE + 1073741824 )) || die "Not enough free space in /data for my_stock ($MYSTOCK_SIZE bytes + 1 GiB)."
  say "Pushing $MYSTOCK_NAME (about $((MYSTOCK_SIZE / 1048576)) MiB) to /data/local/tmp ..."
  "$ADB" push "images/$MYSTOCK_NAME" "/data/local/tmp/$MYSTOCK_NAME.new"
  rsh "mv /data/local/tmp/$MYSTOCK_NAME.new /data/port/$MYSTOCK_NAME.new"
  say "Checking the copy on the phone ..."
  [[ "$(rsh "sha256sum /data/port/$MYSTOCK_NAME.new" | awk '{print $1}')" == "$MYSTOCK_SHA" ]] || die "my_stock copy on the phone is corrupt; nothing was flashed."
  rsh "cd /data/port && { [ ! -f $MYSTOCK_NAME ] || mv -f $MYSTOCK_NAME ${MYSTOCK_NAME%.img}-prev.img; } && mv $MYSTOCK_NAME.new $MYSTOCK_NAME && chown 0:0 $MYSTOCK_NAME && chmod 0644 $MYSTOCK_NAME && chcon u:object_r:system_file:s0 $MYSTOCK_NAME && sync"
  COPIED=1
  say "my_stock staged in /data/port/$MYSTOCK_NAME (previous one kept as ${MYSTOCK_NAME%.img}-prev.img)."
}

STAGED=0; FROM_PORT=0; COPIED=0
if "$ADB" get-state 2>/dev/null | grep -q device; then
  dev=$(ash getprop ro.product.device); code=$(ash getprop ro.boot.project_codename)
  [[ "$dev" == guacamole || "$code" == guacamole || "$dev" == OnePlus7Pro ]] || die "This is not a OnePlus 7 Pro (device '$dev', codename '$code')."
  shown=$(ash getprop ro.build.display.id.show); say "Phone runs: ${shown:-unknown}"
  if [[ "$shown" == GM1910_17.* ]] && detect_root; then
    FROM_PORT=1; say "Installed port with root found: upgrade, my_stock is staged now (data kept)."
    if (( DRY )); then say "DRY RUN: would stage my_stock, reboot to fastboot and flash. Nothing changed."; exit 0; fi
    stage_mystock; STAGED=1
  else
    say "No rooted ColorOS 17 port running: the phone will be flashed from fastboot and my_stock staged on the first boot."
    say "Coming from another ROM (OxygenOS, LineageOS, ...) needs a WIPE (its encrypted /data cannot be read by this port)."
    (( DRY )) && { say "DRY RUN: nothing changed."; exit 0; }
  fi
  "$ADB" reboot bootloader
fi
say "Waiting for fastboot ..."; for _ in $(seq 1 60); do "$FASTBOOT" devices | grep -q fastboot && break; sleep 2; done
"$FASTBOOT" devices | grep -q fastboot || die 'No phone in fastboot mode.'
product=$("$FASTBOOT" getvar product 2>&1 | awk -F': *' '/^product:/ {print $2}' | tr -d '\r')
if [[ "$product" != msmnile ]]; then
  say "WARNING: fastboot product is '$product', expected 'msmnile' (OnePlus 7 Pro)."
  (( CONFIRM_DEVICE )) || { read -r -p "Type YES to continue anyway: " a || a=''; [[ "$a" == YES ]] || die 'Stopped.'; }
fi
slot=$("$FASTBOOT" getvar current-slot 2>&1 | awk -F': *' '/^current-slot:/ {print $2}' | tr -d '\r'); [[ "$slot" == a || "$slot" == b ]] || die "Unknown active slot '$slot'."
(( DRY )) && { say "DRY RUN: would flash slot $slot. Nothing changed."; "$FASTBOOT" reboot; exit 0; }
say "Flashing the active slot _$slot ..."
# Firmware = OxygenOS 11 H.40 (what the OnePlus 7 Pro must run under this port). Bootloaders without
# `fastboot flashing unlock_critical` refuse the critical ones (abl, xbl, ...): those are skipped with a warning; a phone that
# already runs H.40 firmware (any OxygenOS 11.0.x / LineageOS install made from H.40) loses nothing.
SKIPPED_FW=''
for p in $FIRMWARE; do
  if out=$("$FASTBOOT" flash "${p}_$slot" "images/firmware/$p.img" 2>&1); then printf '%s\n' "$out" | tail -1
  elif printf '%s' "$out" | grep -qi 'critical'; then SKIPPED_FW="$SKIPPED_FW $p"; say "WARNING: ${p}_$slot is a critical partition the bootloader refuses (not unlocked): skipped."
  else printf '%s\n' "$out"; die "fastboot flash ${p}_$slot failed."; fi
done
[[ -z "$SKIPPED_FW" ]] || say "Skipped critical firmware:$SKIPPED_FW. Fine if the phone already has OxygenOS 11 H.40 firmware; otherwise run 'fastboot flashing unlock_critical' and install again."
"$FASTBOOT" flash "dtbo_$slot" images/dtbo.img
"$FASTBOOT" flash "vbmeta_$slot" images/vbmeta.img
"$FASTBOOT" flash "boot_$slot" "$BOOT_IMG"
"$FASTBOOT" flash "vendor_$slot" images/vendor.img
"$FASTBOOT" flash "system_$slot" images/system.img
WIPED=0
case $WIPE_MODE in
  yes) "$FASTBOOT" -w; WIPED=1 ;;
  no) ;;
  ask) say "Wipe /data now? Required when coming from another ROM; erases ALL apps, data and files on the phone."
       read -r -p "Type WIPE to wipe, Enter to keep the data: " a || a=''
       [[ "$a" == WIPE ]] && { "$FASTBOOT" -w; WIPED=1; } ;;
esac
"$FASTBOOT" reboot
if (( ! STAGED || WIPED )); then
  say "First boot: waiting for adb to stage my_stock (the first boot without it can look stuck; that is expected) ..."
  "$ADB" wait-for-device; for _ in $(seq 1 120); do [[ "$(ash 'test -d /data/system && echo y' 2>/dev/null)" == y ]] && break; sleep 5; done
  detect_root || die "No root over adb on the first boot; copy images/$MYSTOCK_NAME to /data/port by hand (see README)."
  stage_mystock; if (( COPIED )); then "$ADB" reboot; "$ADB" wait-for-device; fi
fi
if [[ $VARIANT == magisk ]]; then
  say "Waiting for Android to finish booting to install the Magisk app ..."
  for _ in $(seq 1 120); do [[ "$(ash getprop sys.boot_completed 2>/dev/null)" == 1 ]] && break; sleep 5; done
  ash pm list packages | grep -q '^package:com.topjohnwu.magisk$' || "$ADB" install -r images/Magisk-v31.0.apk || say "Install images/Magisk-v31.0.apk by hand."
fi
say "Done. After the first full boot with the camera already installed in /data from older live tests, run once:"
say "  adb shell pm uninstall-system-updates com.oplus.camera"
