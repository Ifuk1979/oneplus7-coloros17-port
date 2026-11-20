#!/bin/bash
# Stage 01: extract the partitions that exist only inside OTA payloads into $WORK/cache.
#   - PLK110 full OTA (17.0.0.105): my_stock   (the shipped my_stock is NOT reproducible from this build, see docs/research/2026-11-08-my_stock-provenance.md)
# Everything else the build needs is already unpacked under StockRom/*/images (read directly, never copied).
# LOS=next additionally extracts the 20261109 nightly payload (partition list printed first).
set -uo pipefail
. "$HERE/config.env"; . "$HERE/lib/common.sh"
need_root
CACHE="$WORK/cache"; mkdir -p "$CACHE"
PY="python3 $HERE/lib/extract_payload.py"

# Decision 2026-11-10: the system chain is the .105 OTA itself (no AxisGSI). Partitions that StockRom/PLK110-full/images
# does not hold are extracted here; system, system_ext, my_manifest, my_region, odm, vendor are read from images/.
OTA_PARTS="product my_product my_engineering my_heytap my_carrier my_bigball"
fp="$(fingerprint "$SRC_FULL_ZIP" "$HERE/lib/extract_payload.py")-$LOS-v2"
done_all() { [ -s "$CACHE/my_stock-$CACHE_TAG.img" ] && for p in $OTA_PARTS; do [ -s "$CACHE/$p-$CACHE_TAG.img" ] || return 1; done; }
if stamp_ok 01 "$fp" && done_all; then
  say "stage 01 already done for these inputs (stamp matches); delete $(stamp_file 01) to redo"; exit 0
fi

say "partitions in the PLK110 full OTA:"
$PY list "$SRC_FULL_ZIP" || die "cannot read payload of $SRC_FULL_ZIP"

want=$MY_STOCK_BYTES     # my_stock size listed in the OTA manifest
if [ -s "$CACHE/my_stock-$CACHE_TAG.img" ]; then say "my_stock already extracted"; else
say "extracting my_stock (about 3 minutes, ~4.7 GB) ..."
$PY extract "$SRC_FULL_ZIP" my_stock "$CACHE/my_stock-$CACHE_TAG.img.part" || die "extract failed"
got="$(size_of "$CACHE/my_stock-$CACHE_TAG.img.part")"
[ "$got" = "$want" ] || die "my_stock size $got, expected $want"
mv "$CACHE/my_stock-$CACHE_TAG.img.part" "$CACHE/my_stock-$CACHE_TAG.img"
sha256sum "$CACHE/my_stock-$CACHE_TAG.img" | tee "$CACHE/my_stock-$CACHE_TAG.img.sha256"
fi
for p in $OTA_PARTS; do
  [ -s "$CACHE/$p-$CACHE_TAG.img" ] && continue
  say "extracting $p ..."
  $PY extract "$SRC_FULL_ZIP" "$p" "$CACHE/$p-$CACHE_TAG.img.part" || die "extract $p failed"
  mv "$CACHE/$p-$CACHE_TAG.img.part" "$CACHE/$p-$CACHE_TAG.img"
  sha256sum "$CACHE/$p-$CACHE_TAG.img" | tee "$CACHE/$p-$CACHE_TAG.img.sha256"
done

if [ "$LOS" = next ]; then
  say "LOS=next: partitions in the 20261109 nightly:"
  $PY list "$SRC_LOS_NEXT_ZIP" || die "cannot read payload of $SRC_LOS_NEXT_ZIP"
  for p in vendor boot dtbo vbmeta; do
    $PY extract "$SRC_LOS_NEXT_ZIP" "$p" "$CACHE/los1109-$p.img" || die "extract $p failed"
  done
fi
stamp_set 01 "$fp"
say "stage 01 done"
