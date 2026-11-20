#!/bin/bash
# Stage 12: the patches whose input files differ between the old GSI base and the .105 OTA, re-derived on the .105 files:
#   a) services.jar   - fingerprint onFingerprintCmd vec<uint32> (patches/fpcmd-stub.diff = the smali delta of tools/live/fpcmd/services.jar vs the GSI original)
#   b) oplus-services - engineer HAL waitForService (tools/patch-oplus-services-engineer.py)
#   c) SystemUI.apk   - kernel dim layer (tools/patch-systemui-dim.py + sigblock transplant)
#   d) WallpaperChooser.apk (B15 video wallpaper release) -> $WORK/extras/ for the my_stock stage (apktool + patch_r0.py)
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
say "stage 12 done"
