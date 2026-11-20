#!/bin/bash
# Stage 13: camera (BAKE-LIST C1, B6-adjacent) system-side parts + the my_stock image (.105 my_stock + H.40 camera + port-camera tree +
# patched WallpaperChooser). Ported from tools/build-port-b.sh lines 44-172. Output: $OUT/smoke/my_stock-105.img (PYB110: my_stock-pyb201.img)
# Differences from the GSI build: my_stock base is the full .105 image (no 40-app donor merge), .105 already ships my_product/app/OplusCamera
# (replaced by the p9 patched copy) and the patched WallpaperChooser comes from stage 12.
set -euo pipefail
. "$HERE/config.env"; . "$HERE/lib/common.sh"
need_root
if [ -z "${REFORGE_NS:-}" ]; then export REFORGE_NS=1; exec unshare --mount --propagation private bash "$0" "$@"; fi
P="$PROJECT"; T="$WORK/tree"; W="$WORK/s13"; SM="$OUT/smoke"; rm -rf "$W"; mkdir -p "$W" "$SM"
[ -d "$T/system" ] || die "run stage 10 first"
case "$DONOR" in plk110) MSN=my_stock-105.img ;; *) MSN=my_stock-$CACHE_TAG.img ;; esac   # on-device name the my_stock rc mounts
[ -s "$WORK/extras/WallpaperChooser-portwp.apk" ] || die "run stage 12 first (patched WallpaperChooser)"
MS="$WORK/mystock-tree"; rm -rf "$MS"; mkdir -p "$W/ms-mnt"
mount -o ro,loop "$WORK/cache/my_stock-$CACHE_TAG.img" "$W/ms-mnt"; say "copying the .105 my_stock tree (4.7 GB)"; cp -a "$W/ms-mnt/." "$MS/" 2>/dev/null || { mkdir -p "$MS"; cp -a "$W/ms-mnt/." "$MS/"; }
umount "$W/ms-mnt"
CAMX="$MS"
# H.40 OnePlusCamera + OnePlusCameraService (both donors since 2026-11-20, user request). On .105/.201 com.oneplus.camera.service
# (sharedUserId system, uid 1000) aborted in zygote: selinux_android_setcontext(1000, "default:privapp:...") has no seapp_contexts
# match because its H.40 signer is not this build's platform key (seinfo default). Fix: its signing certificate is added to
# product_mac_permissions.xml as seinfo platform (-> system_app, like on H.40). The camera app itself stays a normal priv_app.
H40CS_CERT_SHA=fc98dae63ad39626   # first 16 hex of sha256(DER cert) of OnePlusCameraService.apk META-INF/CERT.RSA
if true; then
# ---- H.40 camera apps (old 50-60)
mkdir -p /mnt/h40s /mnt/h40myp
if [ -n "${SRC_H40_EXTRACT:-}" ]; then   # AutoPort: the two priv-app dirs + permission XMLs pre-extracted (same relative paths)
  mountpoint -q /mnt/h40myp || mount --bind "$SRC_H40_EXTRACT/my_product" /mnt/h40myp
else
  mountpoint -q /mnt/h40s || mount -o ro,loop $P/StockRom/H40/images/system.img /mnt/h40s
  mountpoint -q /mnt/h40myp || mount -o ro,loop /mnt/h40s/system/euclid/my_product.img /mnt/h40myp
fi
cp -a /mnt/h40myp/priv-app/OnePlusCamera /mnt/h40myp/priv-app/OnePlusCameraService "$CAMX/priv-app/"
PAL=$(getfattr -n security.selinux --only-values "$CAMX/priv-app")   # label like the donor's own priv-app (the extract has no xattrs)
for d in OnePlusCamera OnePlusCameraService; do
  chown -R root:root "$CAMX/priv-app/$d"; find "$CAMX/priv-app/$d" -type d -exec chmod 0755 {} +; find "$CAMX/priv-app/$d" -type f -exec chmod 0644 {} +
  find "$CAMX/priv-app/$d" -exec setfattr -h -n security.selinux -v "$PAL" {} +
done
# seinfo platform for the H.40 camera service signer (mac_permissions is read by PackageManager from /product/etc/selinux)
CSA="$CAMX/priv-app/OnePlusCameraService/OnePlusCameraService.apk"
CSR=$(unzip -l "$CSA" | awk '/META-INF\/[^ ]*\.RSA$/ {print $4}' | head -1)
CSH=$(unzip -p "$CSA" "$CSR" | openssl pkcs7 -inform DER -print_certs | openssl x509 -outform DER | od -An -v -tx1 | tr -d ' \n')
[ "$(printf %s "$CSH" | xxd -r -p | sha256sum | cut -c1-16)" = "$H40CS_CERT_SHA" ] || die "OnePlusCameraService signer changed"
MP="$T/product/etc/selinux/product_mac_permissions.xml"
[ -f "$MP" ] && grep -q '</policy>' "$MP" || die "no product_mac_permissions.xml with </policy> in the donor"
! grep -qi "$CSH" "$MP" || die "H.40 camera service signer already in product_mac_permissions.xml"
sed "s|</policy>|    <!-- OnePlus7Port: H.40 OnePlusCameraService (uid 1000) -> seinfo platform -->\n    <signer signature=\"$CSH\">\n        <seinfo value=\"platform\" />\n    </signer>\n</policy>|" "$MP" > "$W/mac.xml"
[ "$(grep -c '<signer' "$W/mac.xml")" = "$(( $(grep -c '<signer' "$MP") + 1 ))" ] || die "mac_permissions edit failed"
cat "$W/mac.xml" > "$MP"   # in place: keeps label
cp -a /mnt/h40myp/etc/permissions/com.oneplus.camera.xml /mnt/h40myp/etc/permissions/com.oneplus.camera.service.xml "$CAMX/etc/permissions/"
PEL=$(getfattr -n security.selinux --only-values "$CAMX/etc/permissions")
for x in com.oneplus.camera.xml com.oneplus.camera.service.xml; do
  chown root:root "$CAMX/etc/permissions/$x"; chmod 0644 "$CAMX/etc/permissions/$x"; setfattr -n security.selinux -v "$PEL" "$CAMX/etc/permissions/$x"
done
# v10 = novib + the live-validated video patches (tools/live/rea-analysis/*, all offset-preserving dex edits): EIS bypass,
# 4K30 session type 0x8116 -> 0, no 960x540 preview-frame reader (4th stream makes the HAL return -38 at 4K).
# Live test (build 15 + vendor.vidhance.enabled=0 + vendor.audio.hw.aac.encoder=false): 1080p30, 4K30 and 1080p60 recordings
# are valid HEVC+AAC (docs/logs/camera-video-b14/v10-*.mp4).
[ "$(sha256sum < $P/tools/live/camera/OnePlusCamera-H40-v10.apk | cut -d' ' -f1)" = 3415078eebeb5c24cade0ae0ba6caa731c2719b5060f1d53a873879ba61fc5e1 ]
cat $P/tools/live/camera/OnePlusCamera-H40-v10.apk > "$CAMX/priv-app/OnePlusCamera/OnePlusCamera.apk"   # keep label
umount /mnt/h40myp; if mountpoint -q /mnt/h40s; then umount /mnt/h40s; fi
# ---- default permissions + donor camera system side (old 61-128; .105 ships my_product/app/OplusCamera: replaced)
# Its 2019 runtime-permission request loops on Android 17 (dialog never shows): pre-grant like a stock system camera.
install -D -m 0644 -o root -g root /dev/null "$T/system/etc/default-permissions/oneplus7port-camera.xml"
printf '%s\n' '<?xml version="1.0" encoding="utf-8"?>' '<exceptions>' '    <exception package="com.oneplus.camera">' \
  '        <permission name="android.permission.CAMERA" fixed="false"/>' \
  '        <permission name="android.permission.RECORD_AUDIO" fixed="false"/>' \
  '        <permission name="android.permission.ACCESS_FINE_LOCATION" fixed="false"/>' \
  '        <permission name="android.permission.ACCESS_COARSE_LOCATION" fixed="false"/>' \
  '        <permission name="android.permission.READ_MEDIA_IMAGES" fixed="false"/>' \
  '        <permission name="android.permission.READ_MEDIA_VIDEO" fixed="false"/>' \
  '        <permission name="android.permission.POST_NOTIFICATIONS" fixed="false"/>' \
  '    </exception>' '</exceptions>' > "$T/system/etc/default-permissions/oneplus7port-camera.xml"
setfattr -n security.selinux -v u:object_r:system_file:s0 "$T/system/etc/default-permissions/oneplus7port-camera.xml"
fi
# (BAKE-LIST C1/C1b-fix, baked 2026-11-03) ColorOS 17 donor camera com.oplus.camera 7.006.125 = the live set of
# tools/live/camera-donor17/restore-live.sh (this replaces it; tools/live/camera-donor17/BAKE-NOTES.md). The H.40 OnePlusCamera
# above stays. Sources were pulled from the phone's /data/local/tmp/cos17-cam and match its live mounts byte for byte.
#  - app: /my_product/app/OplusCamera, where the full donor my_product ships it (not priv-app; the 41 JNI libs it needs from
#    /my_product/lib64 are already in this tree, checked below = the live /product/lib64 overlay). APK = p9 (patched classes7/9/12)
#    + zipalign -p 4 + the donor APK's own signing block (tools/transplant-apk-sigblock.py; signer b0a9bbfc, same as the /data
#    install). System-partition APKs are scanned without digest checks, like the transplanted SystemUI/ims/OVoiceManagerService.
#  - SDK v11 + adapter v18 jars in /product/framework, their <library> XML in /system/etc/permissions (the only file the live
#    /system/etc/permissions bind added); persist.camera.override_* defaults in my_product/build.prop.
#  - donor odm etc/camera (1.5 GB: LUTs, models, config/ with op7hw oplus_camera_config, simple2 camera_unit_config,
#    master-filter feature protobuf, SimTool_Master.ini ODT=0 CWCM=0) and 113 donor odm libs (735 MB) do not fit vendor_b
#    (~240 MB free): they go in my_stock.img (/my_stock/port-camera) and 01-port-camera.rc bind-mounts / overlays them at
#    post-fs-data, right after 00-port-mystock.rc mounts /my_stock, before any HAL or zygote starts.
  # PYB110 .201 (revised 2026-11-17 after the live test + lib analysis): the .201 camera (com.oplus.camera 7.012.185) is an APEX
  # (my_product/apex/com.oplus.camera.app.apex) that this port never activates, and its native stack moved into five odm APEXes
  # (aps, aps.algo.library 1.08 GB, aps.algo.model 1.78 GB, camerahalserver x2): odm/lib64 holds 126 symlinks into /apex/com.oplus.camera.aps*,
  # so only 8 of the 113 odm libs of the proven bake exist as real files. The proven p9 bake (7.006.125, 41 JNI libs, SDK v11 / adapter v18,
  # odm camera data and libs from tools/live/camera-donor17/bake) is therefore applied to PYB too; it needs nothing from the .201 camera.
  # The 41 JNI libs only the .105 my_product carried are taken (sha-checked) from the 17k release image.
CD=$P/tools/live/camera-donor17
if [ "$DONOR" = plk110 ]; then
  LIBSRC="$T/my_product/lib64"; LIBSUMS="$CD/bake/my_product-lib64.SHA256SUMS"; CAM_APK="$CD/OplusCamera-p9-sys.apk"
  CAM_JARS="com.oplus.camera.unit.sdk.jar:camera-sdk-v11.jar com.oplus.camera.unit.sdk.adapter.jar:camera-adapter-v18.jar"
  CAM_XML="$CD/bake/oneplus7port-camera-unit.xml"; CAM_CFG=""
sha256sum -c --quiet <<SUMS || { echo "donor camera sources changed"; exit 1; }
5d38a17594af24737b9a18b96aad7dc1ced35ec87fa2f215fda343de16e38423  $CD/OplusCamera-p9-sys.apk
736d601d616b82b746c62c7e3ae89efba9f512ae65add9d64942d7ea3ef2be2b  $CD/camera-sdk-v11.jar
f6b71fd36935654df17a38c1c1669b2ef38e0dae702ea2197696b2474e917426  $CD/camera-adapter-v18.jar
94ec843860349ce65480bcf9a90f1463b89956247e447a831d2d78e610d2b580  $CD/bake/oneplus7port-camera-unit.xml
SUMS
else
  # PYB110 (2026-11-19, live-verified on PYB .201 incl. this exact system-app layout via a /my_product/app overlay +
  # pm uninstall-system-updates): PYB110's own camera com.oplus.camera 7.012.185 instead of the p9 7.006 bake.
  # docs/2026-11-18-handoff-pyb110-own-camera.md sections 7-12. APK = pristine 7.012 + patch-app-tele/portrait-aps/nobeauty
  # (classes12/classes) + patch-app-nobokeh (classes4), zipalign -p 4, pristine signing block transplanted. SDK = pyb-sdk-v16
  # (pyb-dev/build-sdk.sh chain, adapter merged, no adapter jar). The 42 JNI libs = the live /product/lib64 overlay
  # (17k set, 6 replaced by the 7.012 apex builds, + libApsAITranslateJni). odm camera config = pyb2 (make-pyb2-config.py).
  [ ! -e "$T/my_product/app/OplusCamera" ] || die "PYB tree already has my_product/app/OplusCamera"
  LIBSRC="$CD/bake-7012/product-lib64"; LIBSUMS="$CD/bake-7012/product-lib64.SHA256SUMS"; CAM_APK="$CD/OplusCamera-7012-t6-sys.apk"
  CAM_JARS="com.oplus.camera.unit.sdk.jar:pyb-sdk-v16.jar"
  CAM_XML="$CD/bake-7012/oneplus7port-camera-unit.xml"; CAM_CFG="$CD/oplus_camera_config.pyb2.json"
sha256sum -c --quiet <<SUMS || { echo "PYB 7.012 camera sources changed"; exit 1; }
acf796bfdd5888fc0da578d2034012debe243c261653b321eeea9153b007a65c  $CD/OplusCamera-7012-t6-sys.apk
6eb5f2d2144f270988175c8f179a84dbc5cab54c00516d3fbfb0c4cc94450d8d  $CD/pyb-sdk-v16.jar
2903a4403c881b54d201471e4a6ad79ae5cc4f4210abf92a536b868e110e4a96  $CD/bake-7012/oneplus7port-camera-unit.xml
40e0477fb7699a0430c215ad2406e2ec37df8382ed484436544bac397cc9b707  $CD/oplus_camera_config.pyb2.json
SUMS
  [ "$(wc -l < "$LIBSUMS")" = 42 ] && [ "$(ls "$LIBSRC" | wc -l)" = 42 ] || { echo "bake-7012 product-lib64 is not the 42-lib live set"; exit 1; }
fi
(cd "$CD/bake" && sha256sum -c --quiet SHA256SUMS) || { echo "camera-donor17/bake tree changed"; exit 1; }
[ "$(cd "$CD/bake" && find odm-camera odm-lib64 -type f | wc -l)" = "$(wc -l < "$CD/bake/SHA256SUMS")" ] || { echo "camera-donor17/bake has files not in SHA256SUMS"; exit 1; }
# the live config choices are what the bake tree carries
sha256sum -c --quiet <<SUMS || { echo "bake odm-camera config is not the live set"; exit 1; }
17eb6a99563d90b8398265b691cd2d6c51c4be2771092a4f4fbe08789eb8095a  $CD/bake/odm-camera/config/oplus_camera_config
2c9ff5c2c52b30d3dd3da1eb9503015559a94f24a1f470b5dedfb5742119d2f4  $CD/bake/odm-camera/config/camera_unit_config
44aa8023f1a57f3f7df73b43ee01ec22c6f4df433ea422a247c8b278001cdc69  $CD/bake/odm-camera/config/camera_unit_feature_config.protobuf
6a252b4d7193879ac85b173276ead926ff2c3d24a2b379d5eea4eb258c897ebf  $CD/bake/odm-camera/basictone/setting/SimTool_Master.ini
SUMS
(cd "$LIBSRC" && sha256sum -c --quiet "$LIBSUMS") || { echo "camera JNI lib source $LIBSRC lacks/differs from $LIBSUMS"; exit 1; }
# 17j-r2: the camera app's linker namespace (product apk, my_product/app) searches /product/lib64, NOT /my_product/lib64, so the
# same 41 libs must also be in /product/lib64 (without them: UnsatisfiedLinkError libCombineLutJni.so not found; live-verified with
# the plib-upper overlay). Copies of the sha-checked donor my_product libs, system_lib_file like the rest of /product/lib64.
while read -r sum name; do
  [ ! -e "$T/product/lib64/$name" ] || { echo "donor product/lib64 already has $name"; exit 1; }
  install -m 0644 -o root -g root "$LIBSRC/$name" "$T/product/lib64/$name"
  setfattr -n security.selinux -v u:object_r:system_lib_file:s0 "$T/product/lib64/$name"
done < "$LIBSUMS"
(cd "$T/product/lib64" && sha256sum -c --quiet "$LIBSUMS") || { echo "product/lib64 camera libs differ"; exit 1; }
OC=$T/my_product/app/OplusCamera
rm -rf "$OC"   # .105 ships the donor camera app; the p9 patched copy replaces it
install -d -m 0755 -o root -g root "$OC"
install -m 0644 -o root -g root "$CAM_APK" "$OC/OplusCamera.apk"
setfattr -n security.selinux -v u:object_r:system_file:s0 "$OC"
setfattr -n security.selinux -v u:object_r:system_file:s0 "$OC/OplusCamera.apk"
for j in $CAM_JARS; do
  [ ! -e "$T/product/framework/${j%%:*}" ] || { echo "donor already has product/framework/${j%%:*}"; exit 1; }
  install -m 0644 -o root -g root "$CD/${j#*:}" "$T/product/framework/${j%%:*}"
  setfattr -n security.selinux -v u:object_r:system_file:s0 "$T/product/framework/${j%%:*}"
done
[ ! -e "$T/system/etc/permissions/oneplus7port-camera-unit.xml" ] || { echo "camera unit library XML already present"; exit 1; }
install -m 0644 -o root -g root "$CAM_XML" "$T/system/etc/permissions/oneplus7port-camera-unit.xml"
setfattr -n security.selinux -v u:object_r:system_file:s0 "$T/system/etc/permissions/oneplus7port-camera-unit.xml"
# HDR (HLG) preview off (else the SDR preview is tagged HLG and looks oversaturated). A value already persisted in /data wins.
! grep -q '^persist\.camera\.override_' "$T/my_product/build.prop" || { echo "donor my_product already sets persist.camera.override_*"; exit 1; }
printf '\n# OnePlus7Port: donor camera, no HDR preview (BAKE-LIST C1)\npersist.camera.override_enable=true\npersist.camera.override_preview_hdr_support=false\n' >> "$T/my_product/build.prop"
# ---- my_stock payload: port-camera tree, init rc, sepolicy (old 131-149)
MSC=$CAMX/port-camera
[ ! -e "$MSC" ] || { echo "$MSC already exists"; exit 1; }
install -d -m 0755 -o root -g root "$MSC"
cp -r "$CD/bake/odm-camera" "$MSC/odm-camera"
cp -r "$CD/bake/odm-lib64" "$MSC/odm-lib64"
# PYB: the 7.012 port's odm camera config (slow-mo 1080p240 default, time-lapse v1, no hyperlapse/Dual-view/long exposure/IPU beauty)
[ -z "$CAM_CFG" ] || cat "$CAM_CFG" > "$MSC/odm-camera/config/oplus_camera_config"
chown -R root:root "$MSC"; find "$MSC" -type d -exec chmod 0755 {} +; find "$MSC" -type f -exec chmod 0644 {} +
setfattr -n security.selinux -v u:object_r:system_file:s0 "$MSC"
find "$MSC/odm-camera" -exec setfattr -n security.selinux -v u:object_r:vendor_configs_file:s0 {} +   # = vendor odm/etc/camera
find "$MSC/odm-lib64" -exec setfattr -n security.selinux -v u:object_r:vendor_file:s0 {} +              # = vendor odm/lib64
# The bind hides vendor's own odm/etc/camera: the bake copy must still carry its 2 files unchanged (checked in the vendor stage too).
printf '%s\n' "# OnePlus7Port: donor camera odm data from /my_stock (build-port-b.sh, BAKE-LIST C1). 01- sorts after 00-port-mystock.rc," \
  "# whose post-fs-data action mounts /my_stock first. Read-only overlay: donor libs (top) over the LOS odm libs." \
  "on post-fs-data" \
  "    mount none /my_stock/port-camera/odm-camera /vendor/odm/etc/camera bind" \
  "    mount overlay overlay /vendor/odm/lib64 ro lowerdir=/my_stock/port-camera/odm-lib64:/vendor/odm/lib64" > "$T/system/etc/init/01-port-camera.rc"
chmod 0644 "$T/system/etc/init/01-port-camera.rc"
setfattr -n security.selinux -v u:object_r:system_file:s0 "$T/system/etc/init/01-port-camera.rc"
PL="$T/system/etc/selinux/plat_sepolicy.cil"   # init may mount on vendor_file dirs already; add vendor_configs_file
grep -q '^(allow init vendor_file (dir (mounton)))' "$PL" || printf '(allow init vendor_file (dir (mounton)))\n' >> "$PL"
grep -q '^(allow init vendor_configs_file (dir (mounton)))' "$PL" || printf '(allow init vendor_configs_file (dir (mounton)))\n' >> "$PL"
# ---- B15 patched WallpaperChooser (stage 12), stale oat dropped
WPD="$CAMX/app/WallpaperChooser"
rm -rf "$WPD/oat"
install -m 0644 -o root -g root "$WORK/extras/WallpaperChooser-portwp.apk" "$WPD/WallpaperChooser.apk"
setfattr -n security.selinux -v u:object_r:system_file:s0 "$WPD" "$WPD/WallpaperChooser.apk"
# ---- my_stock.img
say "mkfs.erofs my_stock (several minutes)"
rm -f "$SM/$MSN"
mkfs.erofs -zlz4hc,12 -E legacy-compress -b4096 --mount-point=/my_stock "$SM/$MSN" "$MS" > "$W/mystock-mkfs.log"
ls -l "$SM/$MSN"; sha256sum "$SM/$MSN"
say "stage 13 done"
