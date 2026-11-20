# autoport/lib/package.sh - assemble the flash-ready release folder + zip from the reforge smoke output. Sourced by autoport.sh.
# Layout = the hand-made ColorOS17.0.1.201(los20261011-r2) release: install.sh / install.ps1 / two .bat, README.md, images/ with
# boot, boot-magisk31, dtbo, vbmeta, vendor, system, my_stock, firmware/ (OxygenOS 11 H.40), Magisk apk, SHA256SUMS.
#
# Boot: stage 30's boot.img depends only on the LineageOS boot (not on the donor ROM). When it has the same content as the boot
# shipped and phone-tested in the reference release (lib/bootcmp.py: kernel, cmdline, ramdisk files), the tested boot.img and its
# Magisk v31.0 patch are used. Otherwise the built boot.img is used and the Magisk variant is left out (warned).

FIRMWARE_PARTS="abl aop bluetooth cmnlib cmnlib64 devcfg dsp hyp keymaster modem qupfw storsec tz xbl xbl_config"

render() { # template out
  sed -e "s|@RELEASE@|$RELEASE|g" -e "s|@RELEASE_SHORT@|$RELEASE_SHORT|g" -e "s|@MYSTOCK@|$MY_STOCK_DATA_IMG|g" \
      -e "s|@DONOR_DISPLAY@|$DONOR_DISPLAY_EXACT|g" -e "s|@DATE@|$(date +%F)|g" "$1" > "$2"
}

package_release() { # smoke dir, release parent dir
  local sm=$1 parent=$2 ref="$PORT_ROOT/StockRom/reference" rel img f magisk=1
  RELEASE_SHORT="$DONOR_COLOROS($RELEASE_TAG)"; RELEASE="ColorOS$RELEASE_SHORT"
  rel="$parent/$RELEASE"; img="$rel/images"
  for f in boot dtbo vbmeta system vendor; do [ -s "$sm/$f.img" ] || die "missing $sm/$f.img (reforge stages did not finish)"; done
  [ -s "$sm/$MY_STOCK_DATA_IMG" ] || die "missing $sm/$MY_STOCK_DATA_IMG (stage 13)"
  say "packaging $RELEASE"
  rm -rf "$rel"; mkdir -p "$img/firmware"
  # images are hard-linked when possible (same filesystem), else copied
  put() { ln -f "$1" "$2" 2>/dev/null || cp "$1" "$2"; }
  for f in dtbo vbmeta system vendor; do put "$sm/$f.img" "$img/$f.img"; done
  put "$sm/$MY_STOCK_DATA_IMG" "$img/$MY_STOCK_DATA_IMG"
  if python3 -I "$PORT_ROOT/autoport/lib/bootcmp.py" "$ref/boot.img" "$sm/boot.img"; then
    cp "$ref/boot.img" "$img/boot.img"; cp "$ref/boot-magisk31.img" "$img/boot-magisk31.img"
  else
    warn "the built boot.img differs from the tested reference boot: using the built one, Magisk variant NOT included"
    cp "$sm/boot.img" "$img/boot.img"; magisk=0
  fi
  for f in $FIRMWARE_PARTS; do cp "$PORT_ROOT/StockRom/H40/firmware/$f.img" "$img/firmware/$f.img"; done
  [ "$magisk" = 0 ] || cp "$MAGISK_APK" "$img/Magisk-v31.0.apk"
  for f in install.sh install.ps1 Install-NoRoot.bat README.md; do render "$PORT_ROOT/autoport/templates/$f" "$rel/$f"; done
  [ "$magisk" = 0 ] || render "$PORT_ROOT/autoport/templates/Install-Magisk.bat" "$rel/Install-Magisk.bat"
  sed -i 's/$/\r/' "$rel"/*.bat
  find "$rel" -type f -exec chmod 0644 {} +; chmod 0755 "$rel/install.sh"
  if [ "$magisk" = 0 ]; then
    printf '\n> This package was built without the Magisk variant (its boot image differs from the tested one); use NoRoot.\n' >> "$rel/README.md"
  fi
  say "writing SHA256SUMS"
  ( cd "$img" && { ls boot.img boot-magisk31.img dtbo.img vbmeta.img vendor.img system.img "$MY_STOCK_DATA_IMG" Magisk-v31.0.apk 2>/dev/null
       for f in $FIRMWARE_PARTS; do echo "firmware/$f.img"; done; } | xargs sha256sum > SHA256SUMS )
  ( cd "$img" && sha256sum -c --quiet SHA256SUMS ) || die "SHA256SUMS self-check failed"
  bash -n "$rel/install.sh" || die "rendered install.sh has a syntax error"
  if [ "${NO_ZIP:-0}" = 1 ]; then say "release folder: $rel (zip skipped)"; return 0; fi
  local zipf="$parent/OnePlus7Pro-$RELEASE.zip"
  say "zipping (about 10-20 minutes, ~12 GB)"
  rm -f "$zipf"
  ( cd "$parent" && zip -q -r -1 "$zipf" "$RELEASE" ) || die "zip failed"
  unzip -tq "$zipf" >/dev/null || die "zip test failed"
  ( cd "$parent" && sha256sum "$(basename "$zipf")" > "$RELEASE-RELEASE-SHA256SUMS.txt" )
  say "release zip: $zipf"
  say "sha256:      $(cut -d' ' -f1 "$parent/$RELEASE-RELEASE-SHA256SUMS.txt")"
}
