# autoport/lib/donor.sh - inspect the user's ColorOS 17 ROM, extract the image partitions the reforge stages read directly, and write
# $WORK/autoport.env with the detected donor identity (sourced by tools-reforge/config.env through AUTOPORT_ENV). Sourced by autoport.sh.

DIRECT_PARTS="system system_ext odm vendor my_manifest my_region"          # read by stages 10/20 from $SRC_FULL_IMAGES
STAGE01_PARTS="product my_product my_engineering my_heytap my_carrier my_bigball my_stock"   # extracted by reforge stage 01

prop() { grep -m1 "^$2=" "$1" | cut -d= -f2-; }

donor_prepare() {
  local rom=$1 xp="$PORT_ROOT/tools-reforge/lib/extract_payload.py" list img mnt
  [ -f "$rom" ] || die "ROM zip not found: $rom"
  unzip -l "$rom" payload.bin >/dev/null 2>&1 || die "$rom has no payload.bin: give the FULL OTA zip of a OnePlus PYB110 ColorOS 17 build"
  list="$WORK/donor-partitions.txt"
  say "reading the payload partition list"
  python3 -I "$xp" list "$rom" > "$list" || die "cannot read the payload of $rom"
  for p in $DIRECT_PARTS $STAGE01_PARTS; do
    grep -q "^$p " "$list" || die "the ROM has no '$p' partition: not a full ColorOS 17 PYB110 OTA (see $list)"
  done
  img="$WORK/donor-images"; mkdir -p "$img"
  for p in $DIRECT_PARTS; do
    if [ -s "$img/$p.img" ] && [ "$(stat -c %s "$img/$p.img")" = "$(awk -v p="$p" '$1==p {print $2}' "$list")" ]; then continue; fi
    say "extracting $p ..."
    python3 -I "$xp" extract "$rom" "$p" "$img/$p.img.part" || die "extracting $p failed"
    mv "$img/$p.img.part" "$img/$p.img"
  done
  mnt="$WORK/mnt-donor"; mkdir -p "$mnt/mm" "$mnt/v"
  mount -o ro,loop "$img/my_manifest.img" "$mnt/mm"; mount -o ro,loop "$img/vendor.img" "$mnt/v"
  local mb="$mnt/mm/build.prop" vb="$mnt/v/build.prop" show model device ver vpatch fapi
  show=$(prop "$mb" ro.build.display.id.show); model=$(prop "$mb" ro.product.model); device=$(prop "$mb" ro.product.device)
  vpatch=$(prop "$mb" ro.vendor.build.security_patch); fapi=$(prop "$mb" ro.product.first_api_level)
  umount "$mnt/mm" "$mnt/v"
  say "ROM: $show (model $model, device $device, vendor patch $vpatch, first API $fapi)"
  [ "$model" = PYB110 ] || die "this ROM is model '$model'; AutoPort supports OnePlus PYB110 (OnePlus 16 China) ColorOS 17 ROMs only"
  case "$show" in PYB110_17.*) ;; *) die "unexpected version string '$show' (want PYB110_17.x.y.z(...))" ;; esac
  ver=${show#PYB110_}; ver=${ver%%(*}                                   # e.g. 17.0.1.201
  [ -n "$vpatch" ] && [ -n "$fapi" ] && [ -n "$device" ] || die "my_manifest/build.prop lacks security_patch/first_api_level/device"
  [ "$ver" = 17.0.1.201 ] || warn "AutoPort was verified with PYB110 17.0.1.201; $ver is untested. The reforge stages check every file they patch and stop with a message if this build differs."
  DONOR_COLOROS_DETECTED=$ver
  local bre; bre=$(printf '%s' "$show" | sed 's/[.]/\\./g')              # BRE for stage 10's subst: dots escaped, ( ) literal
  cat > "$WORK/autoport.env" <<EOF
# written by autoport.sh $(date -u +%FT%TZ) from $(basename "$rom")
SRC_FULL_ZIP='$rom'
SRC_FULL_IMAGES='$img'
DONOR_COLOROS='$ver'
CACHE_TAG='pyb${ver##*.}'
MY_STOCK_BYTES='$(awk '$1=="my_stock" {print $2}' "$list")'
DONOR_MODEL='$model'
DONOR_DEVICE='$device'
DONOR_DISPLAY_EXACT='$show'
DONOR_DISPLAY_BRE='$bre'
DONOR_VENDOR_PATCH='$vpatch'
DONOR_FIRST_API='$fapi'
MY_STOCK_DATA_IMG='my_stock-pyb${ver##*.}.img'
SRC_LOS_BASELINE='$PORT_ROOT/StockRom/LineageOS24/payload'
SRC_LOS_TETHERING_CAPEX='$PORT_ROOT/StockRom/LineageOS24/extract/com.android.tethering.capex'
SRC_H40_EXTRACT='$PORT_ROOT/StockRom/H40/extract'
EOF
  say "donor profile written: $WORK/autoport.env"
}
