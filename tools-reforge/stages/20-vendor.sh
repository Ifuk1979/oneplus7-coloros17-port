#!/bin/bash
# Stage 20: vendor.img = LineageOS vendor (baseline payload) + the changes the ColorOS system needs, SMOKE SCOPE.
# Included: erofs /system fstab line, FBE standard, vendor sepolicy name clashes, SoundTrigger 2.1 pairing (else the audio HAL
# loops and takes system_server down), ultrasound guard, source-built composer, fingerprint wrapper retired.
# Later stages add the rest of the vendor-side BAKE-LIST items (B5, B14, B16, B22, B26, B27, odm services, sensors ...).
# Needs stage 10 (the assembled tree is read by patch-vendor-sepolicy.py). Output: $OUT/smoke/vendor.img
set -euo pipefail
. "$HERE/config.env"; . "$HERE/lib/common.sh"
need_root
if [ -z "${REFORGE_NS:-}" ]; then export REFORGE_NS=1; exec unshare --mount --propagation private bash "$0" "$@"; fi
[ "$LOS" = baseline ] || die "stage 20 smoke scope supports LOS=baseline only"
T="$WORK/tree"; V="$WORK/mnt20/vend"; ST="$WORK/mnt20/h40v"; SM="$OUT/smoke"
[ -d "$T/system" ] || die "run stage 10 first ($T missing)"
mkdir -p "$V" "$ST" "$SM"
EROFS_LINE='/dev/block/by-name/system                               /system                erofs   ro                                                   wait,slotselect,avb,first_stage_mount'
cp "$SRC_LOS_BASELINE/vendor.img" "$WORK/vendor.img"
mount -o loop "$WORK/vendor.img" "$V"

F="$V/etc/fstab.qcom"
grep -q '^/dev/block/by-name/system .* ext4 ' "$F" || die "no ext4 /system line in fstab.qcom"
awk -v l="$EROFS_LINE" '/^\/dev\/block\/by-name\/system .* ext4 / { print l } { print }' "$F" > "$WORK/fstab.new"
cat "$WORK/fstab.new" > "$F"                                   # in place: keeps the SELinux label
sed 's/fileencryption=ice,/fileencryption=aes-256-xts:aes-256-cts:v2,/' "$F" > "$WORK/fstab.new"; cat "$WORK/fstab.new" > "$F"
grep ' /data ' "$F" | grep -o 'fileencryption=[^,]*' | sort -u

python3 -I "$PROJECT/tools/patch-vendor-sepolicy.py" "$V" "$T"

# ---- SELinux permissive (the port has always run permissive: docs ARCHITECTURE.md; the GSI init forced it). The .105 init is a
# user-build init that ignores androidboot.selinux=permissive, so every domain is made permissive in the policy instead. First strict
# boot (run 3, docs/research/slotA-smoke-2026-11-10): /dev/ion is unlabeled on this vendor, qseecomd/keymaster are denied, keymaster
# aborts, keystore2/vold never come up, boot hangs at the logo. SELINUX_PERMISSIVE=0 turns this off once the policy is fixed properly.
if [ "${SELINUX_PERMISSIVE:-1}" = 1 ]; then
python3 -I - "$T" "$V" <<'PY'
import re, sys
T, V = sys.argv[1:3]
std = [f"{T}/system/etc/selinux/plat_sepolicy.cil", f"{T}/system_ext/etc/selinux/system_ext_sepolicy.cil",
       f"{T}/product/etc/selinux/product_sepolicy.cil", f"{V}/etc/selinux/vendor_sepolicy.cil"]
dbg = [f"{T}/system_ext/etc/selinux/plat_sepolicy_debug.cil", f"{T}/system_ext/etc/selinux/system_ext_sepolicy_debug.cil",
       f"{T}/product/etc/selinux/product_sepolicy_debug.cil", f"{V}/etc/selinux/vendor_sepolicy.cil"]
def scan(files):
    types, dom, perm = set(), set(), set()
    for f in files:
        for line in open(f, errors="replace"):
            m = re.match(r"\(type ([A-Za-z0-9_]+)\)", line)
            if m: types.add(m.group(1)); continue
            m = re.match(r"\(typepermissive ([A-Za-z0-9_]+)\)", line)
            if m: perm.add(m.group(1)); continue
            m = re.match(r"\(typeattributeset domain \((.*)\)\)\s*$", line)
            if m: dom.update(t for t in m.group(1).split() if "(" not in t and ")" not in t)
    return types, dom, perm
ts, ds, ps = scan(std); td, dd, pd = scan(dbg)
# only plain declared types present in BOTH compile sets, not yet permissive
want = sorted((ds & ts & dd & td) - ps - pd)
with open(f"{V}/etc/selinux/vendor_sepolicy.cil", "a") as o:
    o.write("\n; OnePlus7Port reforge: all domains permissive (the .105 init cannot be told to be permissive)\n")
    for t in want: o.write(f"(typepermissive {t})\n")
print(f"typepermissive added for {len(want)} domains")
PY
fi

# SoundTrigger @2.1 adapter from stock H.40 (build-port-b.sh 868-887)
# AutoPort bundles only the two H.40 vendor files used here ($SRC_H40_EXTRACT/vendor/lib/hw, same relative paths); default: mount the image.
if [ -n "${SRC_H40_EXTRACT:-}" ]; then mount --bind "$SRC_H40_EXTRACT/vendor" "$ST"; else mount -o ro,loop "$SRC_H40_IMAGES/vendor.img" "$ST"; fi
cmp -s "$ST/lib/hw/sound_trigger.primary.msmnile.so" "$V/lib/hw/sound_trigger.primary.msmnile.so" || die "sound_trigger.primary.msmnile.so differs from stock"
STL=$(getfattr -n security.selinux --only-values "$V/lib/hw/android.hardware.soundtrigger@2.3-impl.so")
install -m 0644 -o root -g root "$ST/lib/hw/android.hardware.soundtrigger@2.1-impl.so" "$V/lib/hw/"
setfattr -n security.selinux -v "$STL" "$V/lib/hw/android.hardware.soundtrigger@2.1-impl.so"
rm -f "$V/lib/hw/android.hardware.soundtrigger@2.3-impl.so" "$V/lib64/hw/android.hardware.soundtrigger@2.3-impl.so"
sed 's|<fqname>@2.3::ISoundTriggerHw/default</fqname>|<fqname>@2.1::ISoundTriggerHw/default</fqname>|' "$V/etc/vintf/manifest.xml" > "$WORK/manifest.new"
cat "$WORK/manifest.new" > "$V/etc/vintf/manifest.xml"
[ "$(grep -c '@2.1::ISoundTriggerHw/default' "$V/etc/vintf/manifest.xml")" -ge 1 ] || die "soundtrigger manifest edit failed"
umount "$ST"
bash "$PROJECT/tools/patch-soundtrigger.sh" "$V"

# source-built composer (QTI SET_LAYER_TYPE for ColorOS SF)
CS="$LIVE/hwc/composer-service-port"
check_sha "$CS" c8042313960793a6eafdc4206fe11bdd6994184ae6a7c8d07d5ad75ad695756a || die "composer blob sha"
cat "$CS" > "$V/bin/hw/android.hardware.graphics.composer@2.4-service"

# vold dm-default-key options format: v1 for the existing /data (see stage 10, first_api_level); explicit so it never depends on the API-level props
grep -q '^ro\.crypto\.dm_default_key\.options_format\.version=' "$V/build.prop" && die "vendor already sets options_format.version"
printf '\n# OnePlus7Port reforge: existing /data metadata encryption uses the v1 dm-default-key table\nro.crypto.dm_default_key.options_format.version=1\n' >> "$V/build.prop"

# retire the LOS fingerprint wrapper so the stock Goodix HAL registers itself
rm -f "$V/etc/init/android.hardware.biometrics.fingerprint@2.3-service.oplus.rc"

# ultrasound guard in the odm audio HAL
AH="$V/odm/lib/hw/audio.primary.msmnile.so"; AU="$LIVE/audio-ultrasound"
check_sha "$AH" 08a20a73c123c793d717f1b8e7078df1b9efb3853753fae7fac269d3a20a829f || die "audio HAL is not the expected stock one"
check_sha "$AU/audio.primary.msmnile.guard.so" a76ab72beacd4e2aacc907e0958885f1ca9b2602edea331e65954afa8f072e37 || die "guard blob sha"
cat "$AU/audio.primary.msmnile.guard.so" > "$AH"

# vendor-side BAKE-LIST fixes (sidekey, camcorder/AAC/vidhance props, proximity IR, dpf217, qboot, camera provider rc, B16, B26, odm services)
. "$HERE/lib/vendor-fixes.inc.sh"

sync; umount "$V"

# ---- gate: the split policy must compile exactly like init does it on the device (this is the failure the first smoke boot hit) ----
mount -o ro,loop "$WORK/vendor.img" "$V"
ver=$(cat "$V/etc/selinux/plat_sepolicy_vers.txt"); gv=$(cat "$V/etc/selinux/genfs_labels_version.txt")
pargs=("$T/system/etc/selinux/plat_sepolicy.cil" -m -M true -G -N -c 30 "$T/system/etc/selinux/mapping/$ver.cil")
[ -f "$T/system/etc/selinux/mapping/$ver.compat.cil" ] && pargs+=("$T/system/etc/selinux/mapping/$ver.compat.cil")
for part in system_ext product; do d="$T/$part/etc/selinux"
  [ -f "$d/${part}_sepolicy.cil" ] && pargs+=("$d/${part}_sepolicy.cil"); [ -f "$d/mapping/$ver.cil" ] && pargs+=("$d/mapping/$ver.cil"); done
pargs+=("$V/etc/selinux/plat_pub_versioned.cil" "$V/etc/selinux/vendor_sepolicy.cil" "$T/system/etc/selinux/plat_sepolicy_genfs_$gv.cil")
secilc "${pargs[@]}" -o "$WORK/policy.bin" -f /dev/null || die "SELinux policy does not compile (secilc), the phone would hit init SetupSelinux abort"
say "SELinux policy compile gate (standard set): OK ($(size_of "$WORK/policy.bin") bytes)"
# same for the userdebug set init uses when ro.debuggable=1 (dev images)
SE="$T/system_ext/etc/selinux"; PR="$T/product/etc/selinux"
dargs=("$SE/plat_sepolicy_debug.cil" -m -M true -G -N -c 30 "$T/system/etc/selinux/mapping/$ver.cil")
[ -f "$T/system/etc/selinux/mapping/$ver.compat.cil" ] && dargs+=("$T/system/etc/selinux/mapping/$ver.compat.cil")
dargs+=("$SE/system_ext_sepolicy_debug.cil" "$SE/mapping/$ver.cil" "$PR/product_sepolicy_debug.cil" "$PR/mapping/$ver.cil"
        "$V/etc/selinux/plat_pub_versioned.cil" "$V/etc/selinux/vendor_sepolicy.cil" "$T/system/etc/selinux/plat_sepolicy_genfs_$gv.cil")
secilc "${dargs[@]}" -o "$WORK/policy-debug.bin" -f /dev/null || die "userdebug SELinux policy set does not compile"
say "SELinux policy compile gate (userdebug set): OK ($(size_of "$WORK/policy-debug.bin") bytes)"
umount "$V"
e2fsck -fn "$WORK/vendor.img" > /dev/null && say "vendor fsck clean"
[ "$(size_of "$WORK/vendor.img")" -le 1073741824 ] || die "vendor.img too large"
cp "$WORK/vendor.img" "$SM/vendor.img"; sha256sum "$SM/vendor.img"
say "stage 20 done"
