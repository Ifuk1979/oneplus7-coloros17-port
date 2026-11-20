#!/bin/bash
# Stage 18: pack the assembled and fixed tree ($WORK/tree, stages 10-17) into system.img (EROFS + AVB hashtree footer).
# Output: $OUT/smoke/system.img
set -euo pipefail
. "$HERE/config.env"; . "$HERE/lib/common.sh"
need_root
SYSTEM_PART=3640655872
T="$WORK/tree"; SM="$OUT/smoke"; mkdir -p "$SM"
[ -d "$T/system" ] || die "run stages 10-17 first"
# ---- size cuts: the .105 tree is ~130 MB too big for the 3,640,655,872-byte system partition (first run: 3,768,459,264 B before the
# ~29 MB AVB hashtree). Removable apps the OnePlus 7 Pro cannot use or that duplicate others. Later stages should move big apps to the
# my_stock image instead (decision pending); the list is the only place that drops donor apps.
SIZE_CUTS="my_product/del-app/SogouInput_U_Product_Del my_product/del-app/HeytapReader my_product/del-app/heytapbook my_product/priv-app/AICallAssistant my_product/priv-app/RemoteControl"
# PYB 2026-11-19: the baked 7.012 camera (my_product/app/OplusCamera 171 MB + 42 libs) put system.img 47 MB over the partition;
# drop the deletable Baidu IME (my_product/del-app, ~110 MB; the default keyboard is com.oplus.keyboard, Sogou is already cut).
SIZE_CUTS="$SIZE_CUTS my_product/del-app/BaiduInput_U_Product_Del"
for c in $SIZE_CUTS; do [ -d "$T/$c" ] || { say "size cut $c already applied"; continue; }; say "size cut: $c ($(du -sm --apparent-size "$T/$c" | cut -f1) MB)"; rm -rf "$T/$c"; done

# ---- erofs + AVB hashtree footer ------------------------------------------------------------------------------------------
say "mkfs.erofs (this takes a few minutes)"
rm -f "$WORK/system.img"
mkfs.erofs -zlz4hc,12 -E legacy-compress -b4096 --mount-point=/ "$WORK/system.img" "$T" > "$WORK/mkfs-system.log"
ls -l "$WORK/system.img"
[ "$(size_of "$WORK/system.img")" -le "$SYSTEM_PART" ] || die "system.img larger than the $SYSTEM_PART byte partition"
python3 -I "$AVBTOOL" add_hashtree_footer --image "$WORK/system.img" --partition_name system --partition_size $SYSTEM_PART \
  --hash_algorithm sha256 --do_not_generate_fec --algorithm SHA256_RSA4096 --key "$AVB_KEY"
cp "$WORK/system.img" "$SM/system.img"
sha256sum "$SM/system.img"
say "stage 18 done"
