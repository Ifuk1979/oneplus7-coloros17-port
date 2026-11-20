# autoport/lib/firmware.sh - optional OnePlus 7 Pro firmware from the user's own OxygenOS 11 H.40 full OTA, and the Magisk boot.
# Sourced by autoport.sh.
#
# Firmware: the 15 partitions the port runs on (abl ... xbl_config, never LOGO) are extracted from the H.40 OTA payload and must
# match lib/h40-firmware.SHA256SUMS (the firmware of the published release). Without --firmware the package has no firmware/ and
# the installers leave the phone's firmware alone.
#
# Magisk: boot-magisk31.img is made on the PC with Magisk v31.0's own boot_patch.sh (x86_64 magiskboot, arm64 magiskinit/magisk/
# init-ld from the APK) and the settings the phone-side patch used (KEEPVERITY/KEEPFORCEENCRYPT true, PREINITDEVICE=sda17).
# Patching the published r2 boot.img this way gives the phone-made, phone-tested boot-magisk31.img byte for byte.

H40_FIRMWARE_PARTS="abl aop bluetooth cmnlib cmnlib64 devcfg dsp hyp keymaster modem qupfw storsec tz xbl xbl_config"
MAGISK_SHA=2c8a488b9a5293e578e95ae4f07e3c57aba4feec4a52ca4dd852a2692d6dd4e8   # Magisk-v31.0.apk
MAGISK_PREINITDEVICE=sda17                                                      # OnePlus 7 Pro storage layout (same on every GM1910)

firmware_prepare() { # H.40 OTA zip, out dir
  local zip=$1 out=$2 xp="$PORT_ROOT/tools-reforge/lib/extract_payload.py" list p
  [ -f "$zip" ] || die "firmware OTA not found: $zip"
  unzip -l "$zip" payload.bin >/dev/null 2>&1 || die "$zip has no payload.bin: give the OnePlus 7 Pro OxygenOS 11 H.40 full OTA (GM1910_11.H.40)"
  mkdir -p "$out"; list="$out/partitions.txt"
  python3 -I "$xp" list "$zip" > "$list" || die "cannot read the payload of $zip"
  for p in $H40_FIRMWARE_PARTS; do grep -q "^$p " "$list" || die "$zip has no '$p' partition: not a OnePlus 7 Pro full OTA"; done
  if (cd "$out" && sha256sum -c --quiet "$PORT_ROOT/autoport/lib/h40-firmware.SHA256SUMS") >/dev/null 2>&1; then
    say "H.40 firmware already extracted"; return 0
  fi
  for p in $H40_FIRMWARE_PARTS; do
    say "extracting firmware $p ..."
    python3 -I "$xp" extract "$zip" "$p" "$out/$p.img" >/dev/null || die "extracting $p failed"
  done
  (cd "$out" && sha256sum -c --quiet "$PORT_ROOT/autoport/lib/h40-firmware.SHA256SUMS") \
    || die "the firmware in $zip is not OxygenOS 11 H.40 (the only firmware this port is tested on); use GM1910_11.H.40 or leave out --firmware"
  say "firmware: OxygenOS 11 H.40, 15 partitions verified"
}

magisk_patch() { # boot.img, out boot-magisk31.img, work dir
  local boot=$1 out=$2 w=$3
  sha256_is "$MAGISK_APK" "$MAGISK_SHA" || die "Magisk APK is not v31.0 ($MAGISK_APK)"
  rm -rf "$w"; mkdir -p "$w/apk" "$w/p"
  unzip -q -o "$MAGISK_APK" 'lib/x86_64/libmagiskboot.so' 'lib/arm64-v8a/*' 'assets/*' -d "$w/apk"
  cp "$w/apk/assets/boot_patch.sh" "$w/apk/assets/util_functions.sh" "$w/apk/assets/stub.apk" "$w/p/"
  cp "$w/apk/lib/x86_64/libmagiskboot.so" "$w/p/magiskboot"
  for f in magiskinit magisk init-ld; do cp "$w/apk/lib/arm64-v8a/lib$f.so" "$w/p/$f"; done
  cp "$boot" "$w/p/boot.img"
  ( set +eu +o pipefail; cd "$w/p" && BOOTMODE=true && . ./util_functions.sh && SOURCEDMODE=1 KEEPVERITY=true KEEPFORCEENCRYPT=true \
      PATCHVBMETAFLAG=false RECOVERYMODE=false LEGACYSAR=false PREINITDEVICE=$MAGISK_PREINITDEVICE && . ./boot_patch.sh boot.img ) \
      > "$w/patch.log" 2>&1 || { tail -20 "$w/patch.log"; die "Magisk boot patch failed ($w/patch.log)"; }
  [ -s "$w/p/new-boot.img" ] || { tail -20 "$w/patch.log"; die "Magisk did not write new-boot.img"; }
  cp "$w/p/new-boot.img" "$out"
  say "Magisk v31.0 boot made ($(sha256sum "$out" | cut -c1-12)…)"
}
