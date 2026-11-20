# autoport/lib/package.sh - assemble the flash-ready release folder + zip from the reforge smoke output. Sourced by autoport.sh.
# Layout = the hand-made ColorOS17.0.1.201(los20261011-r2) release: install.sh / install.ps1 / two .bat, README.md, images/ with
# boot, boot-magisk31, dtbo, vbmeta, vendor, system, my_stock, firmware/ (only with --firmware), Magisk apk, SHA256SUMS.
# boot.img = stage 30's build; boot-magisk31.img = its Magisk v31.0 patch made on the PC (lib/firmware.sh magisk_patch).
# FIRMWARE_DIR (set by autoport.sh from --firmware) holds the verified H.40 firmware; empty = package without firmware.

render() { # template out
  sed -e "s|@RELEASE@|$RELEASE|g" -e "s|@RELEASE_SHORT@|$RELEASE_SHORT|g" -e "s|@MYSTOCK@|$MY_STOCK_DATA_IMG|g" \
      -e "s|@DONOR_DISPLAY@|$DONOR_DISPLAY_EXACT|g" -e "s|@DATE@|$(date +%F)|g" -e "s|@FIRMWARE@|$FIRMWARE_PARTS|g" "$1" > "$2"
}

package_release() { # smoke dir, release parent dir
  local sm=$1 parent=$2 rel img f
  FIRMWARE_PARTS=""; [ -n "${FIRMWARE_DIR:-}" ] && FIRMWARE_PARTS=$H40_FIRMWARE_PARTS
  RELEASE_SHORT="$DONOR_COLOROS($RELEASE_TAG)"; RELEASE="ColorOS$RELEASE_SHORT"
  rel="$parent/$RELEASE"; img="$rel/images"
  for f in boot dtbo vbmeta system vendor; do [ -s "$sm/$f.img" ] || die "missing $sm/$f.img (reforge stages did not finish)"; done
  [ -s "$sm/$MY_STOCK_DATA_IMG" ] || die "missing $sm/$MY_STOCK_DATA_IMG (stage 13)"
  say "packaging $RELEASE"
  rm -rf "$rel"; mkdir -p "$img"
  # images are hard-linked when possible (same filesystem), else copied
  put() { ln -f "$1" "$2" 2>/dev/null || cp "$1" "$2"; }
  for f in boot dtbo vbmeta system vendor; do put "$sm/$f.img" "$img/$f.img"; done
  put "$sm/$MY_STOCK_DATA_IMG" "$img/$MY_STOCK_DATA_IMG"
  magisk_patch "$sm/boot.img" "$img/boot-magisk31.img" "$WORK/magisk"
  cp "$MAGISK_APK" "$img/Magisk-v31.0.apk"
  if [ -n "$FIRMWARE_PARTS" ]; then
    mkdir -p "$img/firmware"
    for f in $FIRMWARE_PARTS; do cp "$FIRMWARE_DIR/$f.img" "$img/firmware/$f.img"; done
  fi
  for f in install.sh install.ps1 Install-NoRoot.bat Install-Magisk.bat README.md; do render "$PORT_ROOT/autoport/templates/$f" "$rel/$f"; done
  sed -i 's/$/\r/' "$rel"/*.bat
  find "$rel" -type f -exec chmod 0644 {} +; chmod 0755 "$rel/install.sh"
  if [ -z "$FIRMWARE_PARTS" ]; then
    printf '\n> **This package has no firmware** (built without --firmware): the phone must already run OxygenOS 11 H.40\n> firmware (latest OxygenOS 11, or LineageOS installed on top of it). The installers leave the firmware alone.\n' >> "$rel/README.md"
  fi
  say "writing SHA256SUMS"
  ( cd "$img" && { ls boot.img boot-magisk31.img dtbo.img vbmeta.img vendor.img system.img "$MY_STOCK_DATA_IMG" Magisk-v31.0.apk
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
