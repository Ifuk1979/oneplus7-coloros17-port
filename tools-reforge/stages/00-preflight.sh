#!/bin/bash
# Stage 00: read-only check of sources, tools and disk. Writes nothing except the log.
set -uo pipefail
. "$HERE/config.env"; . "$HERE/lib/common.sh"
bad=0
fail() { warn "$*"; bad=1; }

say "project: $PROJECT   LOS=$LOS   work=$WORK   out=$OUT"
[ "$(id -u)" = 0 ] || fail "not root (run: wsl -u root)"

say "--- sources (exist + size)"
chk() { # label path
  if [ -e "$2" ]; then printf '  ok   %-18s %s (%s bytes)\n' "$1" "${2#$PROJECT/}" "$(size_of "$2")"
  else printf '  MISSING %-15s %s\n' "$1" "${2#$PROJECT/}"; bad=1; fi
}
chk "LOS baseline"  "$SRC_LOS_BASELINE/vendor.img"
chk "LOS baseline"  "$SRC_LOS_BASELINE/boot.img"
chk "LOS baseline"  "$SRC_LOS_BASELINE/dtbo.img"
chk "LOS baseline"  "$SRC_LOS_BASELINE/vbmeta.img"
chk "LOS 1109 zip"  "$SRC_LOS_NEXT_ZIP"
chk "AxisGSI zip"   "$SRC_GSI_ZIP"
chk "AxisGSI system" "$SRC_GSI_SYSTEM"
chk "donor full zip" "$SRC_FULL_ZIP"
for p in odm vendor system system_ext my_manifest my_region; do chk "donor $p" "$SRC_FULL_IMAGES/$p.img"; done
chk "H.40 zip"      "$SRC_H40_ZIP"
for p in system vendor odm reserve; do chk "H.40 $p" "$SRC_H40_IMAGES/$p.img"; done

if [ "$HASH_MODE" = 1 ]; then
  say "--- sha256 (full, slow)"
  for pair in "$SRC_LOS_NEXT_ZIP:$SRC_LOS_NEXT_SHA256" "$SRC_GSI_ZIP:$SRC_GSI_ZIP_SHA256" "$SRC_GSI_SYSTEM:$SRC_GSI_SYSTEM_SHA256" \
              "$SRC_FULL_ZIP:$SRC_FULL_ZIP_SHA256" "$SRC_H40_ZIP:$SRC_H40_ZIP_SHA256"; do
    f="${pair%%:*}"; h="${pair##*:}"
    if check_sha "$f" "$h"; then echo "  ok   sha256 ${f#$PROJECT/}"; else bad=1; fi
  done
else
  say "--- sha256 skipped (use --hash for the full check)"
fi

say "--- tools in WSL"
for t in python3 unshare mount losetup mkfs.erofs dump.erofs fsck.erofs e2fsck mke2fs resize2fs unzip zip sha256sum xz bzip2; do
  if have_tool "$t"; then printf '  ok   %s\n' "$t"; else printf '  MISSING %s\n' "$t"; [ "$t" = python3 ] || [ "$t" = unshare ] || [ "$t" = unzip ] || [ "$t" = mkfs.erofs ] && bad=1; fi
done
[ -f "$AVBTOOL" ] && echo "  ok   avbtool.py" || { echo "  MISSING avbtool.py ($AVBTOOL)"; bad=1; }
[ -f "$AVB_KEY" ] && echo "  ok   AVB key" || echo "  note: AVB key not found at $AVB_KEY (needed from the boot/vbmeta stages on)"
[ -f "$MAGISK_APK" ] && echo "  ok   Magisk apk" || echo "  note: Magisk apk missing ($MAGISK_APK)"

say "--- disk"
mkdir -p "$WORK" 2>/dev/null
free_gb=$(df -BG --output=avail "$WORK" 2>/dev/null | tail -1 | tr -dc 0-9)
echo "  free in $WORK: ${free_gb:-?} GB (need >= $MIN_FREE_GB)"
[ "${free_gb:-0}" -ge "$MIN_FREE_GB" ] || fail "not enough free space in $WORK"

say "--- repo inputs"
[ -d "$LIVE" ] && echo "  ok   $LIVE ($(ls "$LIVE" | wc -l) entries)" || fail "missing $LIVE"

[ "$bad" = 0 ] && say "preflight PASS" || { say "preflight FAIL"; exit 1; }
