#!/bin/bash
# Stage 30: boot.img = LineageOS boot (baseline) with the erofs /system line in the first-stage fstab, plus dtbo/vbmeta copies
# and SHA256SUMS for the smoke set. Output: $OUT/smoke/{boot,dtbo,vbmeta,system,vendor}.img (+ my_stock-105.img copy not made: pushed from cache).
set -euo pipefail
. "$HERE/config.env"; . "$HERE/lib/common.sh"
need_root
[ "$LOS" = baseline ] || die "stage 30 smoke scope supports LOS=baseline only"
LB="${SRC_LOS_BASELINE:-$PROJECT/StockRom/LineageOS24/payload}"; SM="$OUT/smoke"; B="$WORK/boot"
EROFS_LINE='/dev/block/by-name/system                               /system                erofs   ro                                                   wait,slotselect,avb,first_stage_mount'
add_erofs_line() {
  grep -q '^/dev/block/by-name/system .* ext4 ' "$1" || die "no ext4 /system line in $1"
  awk -v l="$EROFS_LINE" '/^\/dev\/block\/by-name\/system .* ext4 / { print l } { print }' "$1" > "$1.new"; cat "$1.new" > "$1" && rm "$1.new"
}
mkdir -p "$SM"; rm -rf "$B"; mkdir -p "$B/rd"
python3 -I "$PROJECT/tools/bootimg_v2.py" unpack "$LB/boot.img" "$B"
lz4 -dc "$B/ramdisk" > "$B/ramdisk.cpio"
(cd "$B/rd" && cpio -idm --quiet < ../ramdisk.cpio)
add_erofs_line "$B/rd/first_stage_ramdisk/system/etc/fstab.qcom"
add_erofs_line "$B/rd/system/etc/recovery.fstab"
(cd "$B/rd" && find . | LC_ALL=C sort | cpio -o -H newc --quiet -R 0:0) > "$B/ramdisk.new.cpio"
lz4 -l -12 -f -q "$B/ramdisk.new.cpio" "$B/ramdisk.new"
python3 -I "$PROJECT/tools/bootimg_v2.py" repack "$LB/boot.img" "$B/ramdisk.new" "$B/boot.img"
# kept from the GSI build; harmless on a stock init that has no xperms cap (this is part of what the smoke test checks)
python3 -I "$PROJECT/tools/bootimg_v2.py" cmdline "$B/boot.img" "$B/boot.img" androidboot.selinux_xperms_supported=1
cp "$B/boot.img" "$SM/boot.img"; cp "$LB/dtbo.img" "$SM/dtbo.img"; cp "$LB/vbmeta.img" "$SM/vbmeta.img"
for f in boot dtbo vbmeta system vendor; do [ -s "$SM/$f.img" ] || die "missing $SM/$f.img"; done
(cd "$SM" && sha256sum boot.img dtbo.img vbmeta.img system.img vendor.img | tee SHA256SUMS)
sha256sum "$WORK/cache/my_stock-$CACHE_TAG.img" | tee -a "$SM/SHA256SUMS.my_stock"
say "stage 30 done"
