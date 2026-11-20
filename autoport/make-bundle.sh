#!/bin/bash
# autoport/make-bundle.sh - build the AutoPort archive from this repository (maintainer side, WSL as root).
#
#   wsl -u root bash autoport/make-bundle.sh [--dest DIR] [--tar] [--no-copy]
#   Output: release/autoport/OnePlus7Port-AutoPort-v$AUTOPORT_VERSION/ (the folder to upload to the net disk); --tar also packs a .tar.gz
#
# The bundle holds everything AutoPort needs except the user's own ROMs: the reforge stages, the tools/live inputs they read,
# the 7.012 camera bake, the WeChat-fix boot image, the LineageOS 24 (20261011) vendor/boot/dtbo/vbmeta, the H.40 files the stages read,
# Magisk v31.0 and the SELinux 3.11 sources (no firmware, no prebuilt boot images). It never contains the AVB key of
# this repo (every AutoPort run makes its own). The finished tree is scanned for the maintainer's user name, git identity and
# private keys before it is packed.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$REPO/autoport/lib/common.sh"
[ "$(id -u)" = 0 ] || die "run as root (wsl -u root)"
DEST_PARENT=/root/op7-autoport-bundle; TAR=0; COPY=1
AUTOPORT_VERSION=0.1.0                  # AutoPort_v0.1.0_spinning_jenny
while [ $# -gt 0 ]; do
  case "$1" in --dest) DEST_PARENT=${2:?}; shift ;; --tar) TAR=1 ;; --no-copy) COPY=0 ;; *) die "unknown option $1" ;; esac; shift
done
NAME="OnePlus7Port-AutoPort-v$AUTOPORT_VERSION"
B="$DEST_PARENT/$NAME"
REF="$REPO/release/ColorOS17.0.1.201(los20261011-r2)/images"     # published release: source of the Magisk APK
SRCTAR=/root/autoport-src
rm -rf "$B"; mkdir -p "$B"
cp_rel() { # path relative to the repo (file or dir) -> same place in the bundle
  [ -e "$REPO/$1" ] || die "missing in repo: $1"
  mkdir -p "$B/$(dirname "$1")"; rsync -a --no-perms --chmod=Du=rwx,Dgo=rx,Fu=rw,Fgo=r --exclude=__pycache__ --exclude='*.pem' \
    --exclude='*.pk8' --exclude='*.jks' --exclude='*.keystore' "$REPO/$1" "$B/$(dirname "$1")/"
}

say "bundle: $B"
# ---- scripts
cp_rel autoport/autoport.sh; cp_rel autoport/lib; cp_rel autoport/templates; cp_rel autoport/README.md; cp_rel "autoport/自动移植脚本说明.md"
cp "$REPO/autoport/自动移植脚本说明.md" "$B/自动移植脚本说明.md"
cp "$REPO/autoport/README.md" "$B/README.md"
printf '#!/bin/bash\nexec bash "$(dirname "$(readlink -f "$0")")/autoport/autoport.sh" "$@"\n' > "$B/autoport.sh"
cp_rel tools-reforge
rm -rf "$B/tools-reforge/stages/35-debug-slotA.sh"        # debug-only stage (needs a cross compiler), not part of a release
mkdir -p "$B/autoport/src" "$B/docs/logs"
for f in libsepol-3.11.tar.gz secilc-3.11.tar.gz; do cp "$SRCTAR/$f" "$B/autoport/src/"; done

# ---- tools read by the stages
for f in avb/avbtool.py bootimg_v2.py drop-propctx-conflicts.py patch-vendor-sepolicy.py patch-soundtrigger.sh soundtrigger-compat \
         transplant-apk-sigblock.py patch-cutout-overlay.py patch-eyeprotect-strings.py patch-oplus-services-engineer.py \
         patch-systemui-dim.py oplus-stubs camera-helper/apktool_3.0.3.jar; do cp_rel "tools/$f"; done
for d in als audio-policy-1input audio-ultrasound brightness camera-sigpipe display-dc fpcmd health-root hwc ims \
         ims-rilsvc keylayout nandswap odm-services power-drain screen-state-feed sensors-re sidekey stune; do
  cp_rel "tools/live/$d"
done
for f in OVMS_1st_wakeup.bin OVMS_settings.xml OVoiceManagerService-sva-c17sig.apk patch_c17.py sva_opaque_helper.smali.txt; do
  cp_rel "tools/live/breeno-sva/$f"; done
cp_rel tools/live/prop-compare/IDENTITY.md; cp_rel tools/live/prop-compare/b16
cp_rel tools/live/BAKE-LIST.md
CD=tools/live/camera-donor17
for f in bake bake-7012 OplusCamera-7012-t6-sys.apk pyb-sdk-v16.jar oplus_camera_config.pyb2.json; do cp_rel "$CD/$f"; done
cp_rel tools/live/camera/OnePlusCamera-H40-v10.apk                     # H.40 camera, video-fixed v10 (stage 13)
for f in patch_mediacodec_crop.py framework-classes3-b34.dex bootimage; do cp_rel "tools/live/wechat-resize-test/$f"; done   # B34 (stage 12)

# ---- LineageOS 24 (20261011) images + the one file of its system image stage 10 needs
mkdir -p "$B/StockRom/LineageOS24/payload" "$B/StockRom/LineageOS24/extract"
for f in vendor boot dtbo vbmeta; do cp "$REPO/StockRom/LineageOS24/payload/$f.img" "$B/StockRom/LineageOS24/payload/"; done
M=$(mktemp -d); trap 'for m in $M/*; do mountpoint -q "$m" && umount "$m"; done; rm -rf "$M"' EXIT
mkdir -p "$M/los" "$M/h40s" "$M/h40o" "$M/h40v"
mount -o ro,loop "$REPO/StockRom/LineageOS24/payload/system.img" "$M/los"
cp "$M/los/system/apex/com.android.tethering.capex" "$B/StockRom/LineageOS24/extract/"; umount "$M/los"

# ---- H.40: the odm overlay + power profile (stage 11), camera apps (stage 13), two sound trigger libs (stage 20). No firmware:
#      users add their own H.40 OTA with --firmware
E="$B/StockRom/H40/extract"; mkdir -p "$E/odm/overlay" "$E/odm/etc/power_profile" "$E/vendor/lib/hw"
mount -o ro,loop "$REPO/StockRom/H40/images/system.img" "$M/h40s"; mount -o ro,loop "$M/h40s/system/euclid/odm.img" "$M/h40o"
cp "$M/h40o/overlay/oplus_framework_res_overlay.display.product.18821.apk" "$E/odm/overlay/"
cp "$M/h40o/etc/power_profile/power_profile.xml" "$E/odm/etc/power_profile/"
umount "$M/h40o"
mkdir -p "$M/h40p" "$E/my_product/priv-app" "$E/my_product/etc/permissions"      # H.40 camera apps (stage 13)
mount -o ro,loop "$M/h40s/system/euclid/my_product.img" "$M/h40p"
cp -a "$M/h40p/priv-app/OnePlusCamera" "$M/h40p/priv-app/OnePlusCameraService" "$E/my_product/priv-app/"
cp "$M/h40p/etc/permissions/com.oneplus.camera.xml" "$M/h40p/etc/permissions/com.oneplus.camera.service.xml" "$E/my_product/etc/permissions/"
umount "$M/h40p" "$M/h40s"
mount -o ro,loop "$REPO/StockRom/H40/images/vendor.img" "$M/h40v"
cp "$M/h40v/lib/hw/sound_trigger.primary.msmnile.so" "$M/h40v/lib/hw/android.hardware.soundtrigger@2.1-impl.so" "$E/vendor/lib/hw/"
umount "$M/h40v"

# ---- Magisk v31.0 (AutoPort makes the Magisk boot on the PC; no prebuilt boot images are shipped)
mkdir -p "$B/StockRom/Magisk"
cp "$REF/Magisk-v31.0.apk" "$B/StockRom/Magisk/"

# ---- privacy scan: no maintainer identity, no private keys
say "privacy scan"
pats=()
wu=$(printf '%s' "$REPO" | sed -n 's|^/mnt/[a-z]/Users/\([^/]*\)/.*|\1|p'); [ -n "$wu" ] && pats+=("Users/$wu" "Users\\\\$wu")
for k in user.name user.email; do v=$(git -C "$REPO" config "$k" 2>/dev/null || true); [ -n "$v" ] && pats+=("$v"); done
h=$(cat /proc/sys/kernel/hostname); pats+=("@$h")
[ -n "${EXTRA_PRIVATE:-}" ] && pats+=($EXTRA_PRIVATE)
bad=0
for p in "${pats[@]}"; do
  if hits=$(grep -rlaF -- "$p" "$B" 2>/dev/null) && [ -n "$hits" ]; then warn "found '${p:0:3}…' in:"; printf '  %s\n' $hits >&2; bad=1; fi
done
# a PEM private key = the BEGIN line followed by base64 (plain "PRIVATE KEY" strings inside vendor binaries are not keys)
if hits=$(grep -rlaPz -- '-----BEGIN [A-Z ]*PRIVATE KEY-----\r?\n[A-Za-z0-9+/=]{40}' "$B" 2>/dev/null) && [ -n "$hits" ]; then
  warn "PEM private keys in:"; printf '  %s\n' $hits >&2; bad=1; fi
find "$B" -name '*.pem' -o -name '*.pk8' -o -name '*.jks' -o -name '*.keystore' -o -name 'adbkey*' | grep . && { warn "key files in the bundle"; bad=1; }
[ "$bad" = 0 ] || die "privacy scan failed: remove or redact the files above (the bundle is in $B)"

# ---- sums + archive
(cd "$B" && find . -type f ! -name BUNDLE-SHA256SUMS -printf '%P\n' | LC_ALL=C sort | xargs -d '\n' sha256sum > BUNDLE-SHA256SUMS)
say "bundle: $(du -sh "$B" | cut -f1), $(wc -l < "$B/BUNDLE-SHA256SUMS") files"
OUTD="$REPO/release/autoport"; mkdir -p "$OUTD"
if [ "$COPY" = 1 ]; then
  say "copying the folder to $OUTD/$NAME (upload this folder)"
  rm -rf "$OUTD/$NAME.part"; rsync -a --no-perms --no-owner --no-group "$B/" "$OUTD/$NAME.part/"
  (cd "$OUTD/$NAME.part" && sha256sum -c --quiet BUNDLE-SHA256SUMS) || die "copy to $OUTD failed the checksum test"
  rm -rf "$OUTD/$NAME"; mv "$OUTD/$NAME.part" "$OUTD/$NAME"
  say "folder: $OUTD/$NAME ($(du -sh "$OUTD/$NAME" | cut -f1), $(wc -l < "$OUTD/$NAME/BUNDLE-SHA256SUMS") files)"
fi
[ "$TAR" = 1 ] || exit 0
say "packing $OUTD/$NAME.tar.gz"
tar -C "$DEST_PARENT" --owner=0 --group=0 --numeric-owner -cf - "$NAME" | pigz -6 > "$OUTD/$NAME.tar.gz.part"
mv "$OUTD/$NAME.tar.gz.part" "$OUTD/$NAME.tar.gz"
(cd "$OUTD" && sha256sum "$NAME.tar.gz" > "$NAME.tar.gz.sha256")
say "done: $OUTD/$NAME.tar.gz ($(du -h "$OUTD/$NAME.tar.gz" | cut -f1)) sha256 $(cut -d' ' -f1 "$OUTD/$NAME.tar.gz.sha256")"
