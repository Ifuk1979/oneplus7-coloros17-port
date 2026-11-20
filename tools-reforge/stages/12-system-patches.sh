#!/bin/bash
# Stage 12: the patches whose input files differ between the old GSI base and the .105 OTA, re-derived on the .105 files:
#   a) services.jar   - fingerprint onFingerprintCmd vec<uint32> (patches/fpcmd-stub.diff = the smali delta of tools/live/fpcmd/services.jar vs the GSI original)
#   b) oplus-services - engineer HAL waitForService (tools/patch-oplus-services-engineer.py)
#   c) SystemUI.apk   - kernel dim layer (tools/patch-systemui-dim.py + sigblock transplant)
#   d) WallpaperChooser.apk (B15 video wallpaper release) -> $WORK/extras/ for the my_stock stage (apktool + patch_r0.py)
#   e) framework.jar  - B34 MediaCodec crop fix (WeChat remote video) + the matching pinned boot image
# Every patch asserts its pattern, so a changed donor stops the build instead of producing a half-patched image.
set -euo pipefail
. "$HERE/config.env"; . "$HERE/lib/common.sh"
need_root
if [ -z "${REFORGE_NS:-}" ]; then export REFORGE_NS=1; exec unshare --mount --propagation private bash "$0" "$@"; fi
P="$PROJECT"; T="$WORK/tree"; W="$WORK/s12"; rm -rf "$W"; mkdir -p "$W" "$WORK/extras"
[ -d "$T/system" ] || die "run stage 10 first"
for t in baksmali smali java zipalign; do have_tool $t || die "$t missing in WSL"; done
inplace() { cat "$2" > "$1"; }        # rewrite in place: keeps inode, owner, mode and SELinux label

# ---------------------------------------------------------------------------------------------------------------- a) services.jar
SJ="$T/system/framework/services.jar"
mkdir -p "$W/sj" && (cd "$W/sj" && unzip -q -o "$SJ")
CLASS='vendor/oplus/hardware/biometrics/fingerprint/V2_1/IBiometricsFingerprintClientCallbackEx$Stub'
dex=""; for d in "$W"/sj/classes*.dex; do [ "$(strings -n 8 "$d" | grep -cF "L${CLASS};")" -gt 0 ] && { dex="$d"; break; }; done
[ -n "$dex" ] || die "services.jar: fingerprint callback class not found in any dex"
say "fpcmd patch: class lives in $(basename "$dex")"
baksmali d -o "$W/sj.s" "$dex" >/dev/null
( cd "$W/sj.s" && patch -p1 --dry-run < "$HERE/patches/fpcmd-stub.diff" >/dev/null ) || die "fpcmd patch does not apply to the .105 services.jar (class changed)"
( cd "$W/sj.s" && patch -p1 < "$HERE/patches/fpcmd-stub.diff" >/dev/null )
smali a -o "$W/patched.dex" "$W/sj.s" || die "smali failed for services.jar"
cp "$SJ" "$W/services.jar"; cp "$W/patched.dex" "$W/$(basename "$dex")"; (cd "$W" && zip -q -u services.jar "$(basename "$dex")")
inplace "$SJ" "$W/services.jar"
rm -f "$T"/system/framework/oat/*/services.{odex,vdex,art}{,.fsv_meta}

# ---------------------------------------------------------------------------------------------------------------- b) oplus-services.jar
OS="$T/system/framework/oplus-services.jar"
python3 -I "$P/tools/patch-oplus-services-engineer.py" "$OS" "$W/oplus-services-engineer.jar"
inplace "$OS" "$W/oplus-services-engineer.jar"
rm -f "$T"/system/framework/oat/*/oplus-services.{odex,vdex,art}{,.fsv_meta}

# ---------------------------------------------------------------------------------------------------------------- c) SystemUI.apk
SU="$T/system_ext/priv-app/SystemUI/SystemUI.apk"
python3 -I "$P/tools/patch-systemui-dim.py" "$SU" "$W/SystemUI-dim.apk"
python3 -I "$P/tools/transplant-apk-sigblock.py" "$SU" "$W/SystemUI-dim.apk" "$W/SystemUI-dim-signed.apk"
inplace "$SU" "$W/SystemUI-dim-signed.apk"
rm -rf "$T/system_ext/priv-app/SystemUI/oat"

# ---------------------------------------------------------------------------------------------------------------- d) WallpaperChooser (for the my_stock stage)
mkdir -p "$W/mnt-ms"; mount -o ro,loop "$WORK/cache/my_stock-$CACHE_TAG.img" "$W/mnt-ms"
WO="$W/mnt-ms/app/WallpaperChooser/WallpaperChooser.apk"; [ -f "$WO" ] || die "no WallpaperChooser in .105 my_stock"
WD="$P/tools/live/power-drain/wallpaper"
java -jar "$P/tools/camera-helper/apktool_3.0.3.jar" d -r -f -o "$W/wp.ad" "$WO" >/dev/null
case "$DONOR" in plk110) WPATCH=patch_r0.py ;; *) WPATCH=patch_s0.py ;; esac   # .201: engine s0 / flag H / U() / X(), same release logic
python3 -I "$WD/$WPATCH" "$W/wp.ad"
java -jar "$P/tools/camera-helper/apktool_3.0.3.jar" b "$W/wp.ad" -o "$W/wp.built.apk" >/dev/null
unzip -p "$W/wp.built.apk" classes.dex > "$W/wp.classes.dex"
python3 -I "$WD/replace_dex.py" "$WO" classes.dex "$W/wp.classes.dex" "$W/wp.u.apk"
zipalign -f -p 4 "$W/wp.u.apk" "$W/wp.a.apk"
python3 -I "$P/tools/transplant-apk-sigblock.py" "$WO" "$W/wp.a.apk" "$WORK/extras/WallpaperChooser-portwp.apk"
sha256sum "$WORK/extras/WallpaperChooser-portwp.apk"
umount "$W/mnt-ms"

# ---------------------------------------------------------------------------------------------------------------- e) B34 framework.jar
# WeChat remote video stretched: QTI Codec2 decoders with a Surface report a stale width/height (new crop) after a mid-stream
# resolution change; MediaCodec.portFixOutputFormat sets width/height from the crop for Surface outputs (patch_mediacodec_crop.py,
# docs/2026-11-20-wechat-remote-video-stretch.md; live-verified with a real WeChat video call 2026-11-20).
# framework.jar is in the boot image: the system boot image no longer matches the patched dex (ART would run imageless), so it is
# replaced by the primary boot image odrefresh compiled on the phone against exactly this classpath (bootimage/, arm64 + arm).
# That is only valid when every other boot classpath input is byte-identical to the 17.0.1.201 r2 system (bcp-inputs.SHA256SUMS);
# for any other donor the fix is skipped with a warning and framework.jar / the boot image stay stock.
B34="$P/tools/live/wechat-resize-test"; BI="$B34/bootimage"; FJ="$T/system/framework/framework.jar"
(cd "$BI" && sha256sum -c --quiet SHA256SUMS) || die "B34 pinned boot image files changed"
b34=1
[ "$(sha256sum < "$FJ" | cut -d' ' -f1)" = 504ca4bf13cec52f4ba7c4e65087fcd60d4738ab26472800d6cad66c1df75dba ] || b34=0
(cd "$T" && sha256sum -c --quiet "$BI/bcp-inputs.SHA256SUMS") >/dev/null 2>&1 || b34=0
if [ "$b34" = 1 ]; then
  # The boot image is bound to the exact bytes of the patched dex, so the pinned dex is installed as-is (it is the
  # patch_mediacodec_crop.py + smali --api 30 output of this original classes3.dex, the build that was live-tested; a rebuild on
  # another file system can order classes differently, e.g. AudioAttributes/Audioattributes on a case-insensitive disk).
  mkdir -p "$W/fj"; (cd "$W/fj" && unzip -q -o "$FJ" classes3.dex)
  [ "$(sha256sum < "$W/fj/classes3.dex" | cut -d' ' -f1)" = 3070fde66ad55d6e92a351c91e09bb2ec52dca25b3ba7128ddc1d2dc1ec366c3 ] || die "framework classes3.dex is not the 17.0.1.201 original"
  cp "$B34/framework-classes3-b34.dex" "$W/fj3.dex"
  cp "$FJ" "$W/framework.jar"; cp "$W/fj3.dex" "$W/classes3.dex"; (cd "$W" && zip -q -0 framework.jar classes3.dex)
  zipalign -f -p 4 "$W/framework.jar" "$W/framework.a.jar"
  [ "$(unzip -p "$W/framework.a.jar" classes3.dex | sha256sum | cut -d' ' -f1)" = "$(sha256sum < "$W/fj3.dex" | cut -d' ' -f1)" ] || die "framework.jar repack failed"
  unzip -v "$W/framework.a.jar" | grep -q ' Stored .* classes3.dex$' || die "framework.jar classes3.dex must be stored uncompressed"
  inplace "$FJ" "$W/framework.a.jar"
  for a in arm64 arm; do
    D="$T/system/framework/$a"; lab=$(getfattr -n security.selinux --only-values "$D/boot.art")
    [ "$(ls "$D" | grep -c '^boot')" = 144 ] || die "unexpected stock boot image layout in $D"
    rm -f "$D"/boot*.art "$D"/boot*.oat "$D"/boot*.vdex "$D"/boot*.fsv_meta
    for f in boot.art boot.oat boot.vdex boot-framework-adservices.art boot-framework-adservices.oat boot-framework-adservices.vdex; do
      install -m 0644 -o root -g root "$BI/$a/$f" "$D/$f"; setfattr -n security.selinux -v "$lab" "$D/$f"
    done
    [ "$(ls "$D" | grep -c '^boot')" = 6 ] || die "boot image replacement left stray files in $D"
  done
  say "B34: framework.jar MediaCodec crop fix + matching boot image installed"
else
  warn "B34 skipped: framework.jar or the boot classpath differs from 17.0.1.201 r2 (WeChat remote video may stretch after a resolution change)"
fi
say "stage 12 done"
