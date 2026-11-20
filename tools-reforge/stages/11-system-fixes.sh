#!/bin/bash
# Stage 11: system-side BAKE-LIST fixes on the .105 tree (stage 10), ported from tools/build-port-b.sh (line ranges noted per block).
# Left out on purpose (re-patch needed on .105 or handled elsewhere): services.jar fpcmd, oplus-services engineer, SystemUI dim,
# WallpaperChooser (stage 12), camera C1 (stage 13), CUST_LEVEL_LIST export (stock .105 init sets it itself), B3 Play updater (.105 ships one),
# display.id.show / model / dev props / adb key (stage 10).
set -euo pipefail
. "$HERE/config.env"; . "$HERE/lib/common.sh"
need_root
if [ -z "${REFORGE_NS:-}" ]; then export REFORGE_NS=1; exec unshare --mount --propagation private bash "$0" "$@"; fi
P="$PROJECT"; T="$WORK/tree"; W="$WORK/s11"; rm -rf "$W"; mkdir -p "$W"
[ -d "$T/system" ] || die "run stage 10 first"
# ---- helpers (old script 186-189)
need_sha() { [ "$(sha256sum < "$1" | cut -d' ' -f1)" = "$2" ] || { echo "unexpected donor file $1 (artifact made for another donor)"; exit 1; }; }
replace_file() {  # rewrite in place: keeps inode, owner, mode and SELinux xattr
  cat "$2" > "$1"
}
# ---- Oplus AIDL stubs, touchpanel.kl, proximity feeder (old 199-248)
install -m 0644 -o root -g root $P/tools/oplus-stubs/oplus-stubs.dex "$T/system/framework/oplus-port-stubs.dex"
setfattr -n security.selinux -v u:object_r:system_file:s0 "$T/system/framework/oplus-port-stubs.dex"
# Screen-off gestures: the LOS touch driver reports gestures as scancode 246 + type (O 252, V 248, single tap 262);
# ColorOS OplusScreenOffGestureManager only acts on KEYCODE_F4 + /proc/touchpanel/coordinate. Map them to F4
# (live-verified: single tap -> AOD, O and V actions, double tap wakes). The stub keeps double tap in the mask.
install -m 0644 -o root -g root $P/tools/live/keylayout/touchpanel.kl "$T/system/usr/keylayout/touchpanel.kl"
setfattr -n security.selinux -v u:object_r:system_file:s0 "$T/system/usr/keylayout/touchpanel.kl"
printf '%s\n' "# OnePlus7Port: Oplus AIDL stub services (tools/oplus-stubs, see build-port-b.sh)" \
  "service port_oplus_stubs /system/bin/app_process /system/bin port.OplusStubs vendor.oplus.hardware.stability.oplus_project.IOplusProject/default vendor.oplus.hardware.performance.IPerformance/default vendor.oplus.hardware.displaypanelfeature.IDisplayPanelFeature/default vendor.oplus.hardware.touch.IOplusTouch/default" \
  "    user root" \
  "    group root system" \
  "    setenv CLASSPATH /system/framework/oplus-port-stubs.dex" \
  "    seclabel u:r:su:s0" \
  "    disabled" \
  "" \
  "on post-fs-data" \
  "    start port_oplus_stubs"   ""   "# Alert slider -> ColorOS action button (port.SliderBridge): up = press, middle = nothing, down = long press."   "service port_slider_bridge /system/bin/app_process /system/bin port.SliderBridge"   "    user root"   "    group root input"   "    setenv CLASSPATH /system/framework/oplus-port-stubs.dex"   "    seclabel u:r:su:s0"   "    disabled"   ""   "on property:sys.boot_completed=1"   "    start port_slider_bridge"   "    start port_motor_bridge"   ""   "# Pop-up front camera motor (port.MotorBridge, LOS CameraMotorService logic): front cam opened = up, released = down."   "service port_motor_bridge /system/bin/app_process /system/bin port.MotorBridge"   "    user root"   "    group root camera"   "    setenv CLASSPATH /system/framework/oplus-port-stubs.dex"   "    seclabel u:r:su:s0"   "    disabled" > "$T/system/etc/init/00-port-oplus-stubs.rc"
setfattr -n security.selinux -v u:object_r:system_file:s0 "$T/system/etc/init/00-port-oplus-stubs.rc"
# Proximity (type 8) through IR only while the display is off (live-verified 2026-10-18; tools/live/BAKE-LIST.md §1,
# tools/live/sensors-re/README.md). The vendor sensors HAL (patched sensors.ssc.so, see the vendor stage) reads its "audio state" from the
# FIFO /data/vendor/aus (4-byte ints). port_prox_feeder (tools/live/screen-state-feed/ScreenStateFeeder.java, root app_process) writes
# 0 = display off (HAL picks IR) / 8 = display on or AOD (HAL uses no IR, so the under-screen emitter does not blink). The FIFO must exist
# before the HAL starts and have a permanent writer, else its reader thread dies at start or busy-spins on EOF: port_prox_fifo creates it at
# post-fs-data and holds a read-write fd forever. The feeder starts after boot and init restarts it if it ever dies.
# (BAKE-LIST B15, live-verified 2026-11-03) Event-driven feeder: DisplayManager.DisplayListener instead of a 150 ms Display.getState()
# poll (binder call into system_server ~6.7x/s, also screen off); last value re-sent every 30 s. Poll build kept as ssfeed.dex.poll150 (3824ac2b…).
PF=$P/tools/live/screen-state-feed
[ "$(sha256sum < $PF/ssfeed.dex | cut -d' ' -f1)" = af275ed36c6c9dc26cbb6ba234ed5bba03e3d2db22f93152858c931dd91a8c49 ] || { echo "ssfeed.dex sha"; exit 1; }
install -m 0644 -o root -g root $PF/ssfeed.dex "$T/system/framework/oplus-port-proxfeed.dex"
setfattr -n security.selinux -v u:object_r:system_file:s0 "$T/system/framework/oplus-port-proxfeed.dex"
printf '%s\n' "# OnePlus7Port: IR proximity only while the display is off (build-port-b.sh, tools/live/BAKE-LIST.md §1)" \
  'service port_prox_fifo /system/bin/sh -c "while [ ! -d /data/vendor ]; do sleep 1; done; [ -p /data/vendor/aus ] || mkfifo /data/vendor/aus; chmod 0666 /data/vendor/aus; exec 3<>/data/vendor/aus; while :; do sleep 3600; done"' \
  "    user root" \
  "    group root" \
  "    seclabel u:r:su:s0" \
  "    disabled" \
  "" \
  "on post-fs-data" \
  "    start port_prox_fifo" \
  "" \
  "service port_prox_feeder /system/bin/app_process /system/bin ScreenStateFeeder" \
  "    user root" \
  "    group root" \
  "    setenv CLASSPATH /system/framework/oplus-port-proxfeed.dex" \
  "    seclabel u:r:su:s0" \
  "    disabled" \
  "" \
  "# restart, not start: sys.boot_completed goes 0 -> 1 again whenever the framework restarts (zygote/system_server crash or live test)," \
  "# and the feeder's DisplayListener dies with the old system_server, so the HAL would stay on IR with the screen on (visible blink)." \
  "on property:sys.boot_completed=1" \
  "    restart port_prox_feeder" > "$T/system/etc/init/00-port-proxfeed.rc"
setfattr -n security.selinux -v u:object_r:system_file:s0 "$T/system/etc/init/00-port-proxfeed.rc"
# ---- B1 eye protect + DcBridge (old 260-281), B2 nandswap (282-304), B4 health poke (305-318), ALS (319-344)
# B1 low-flicker options -> panel DC backlight: patched option text (same-size arsc edit) + DcBridge service.
EP=$T/system_ext/app/OplusEyeProtect/OplusEyeProtect.apk
case "$DONOR" in
  plk110) EP_SHA=28574614ba00e534ed77e99c1ba9a72b88c36a08406c55b4a89918a9e1df8145; EP_OUT=17a83bdfdfa2fa9ff558dbb16cea5154e7c97de9672379612fa1a426c6457646 ;;
  pyb110) EP_SHA=1849ef1c8cad6837f6351ee383e0a17c8e23b9477905febde59f1975548c24d3; EP_OUT=PYB_UNPINNED ;;   # same patcher, all 9 strings found once
esac
[ "$(sha256sum < $EP | cut -d' ' -f1)" = $EP_SHA ] || { echo "OplusEyeProtect.apk donor sha"; exit 1; }
python3 -I $P/tools/patch-eyeprotect-strings.py $EP "$W/OplusEyeProtect.patched.apk"
if [ "$EP_OUT" = PYB_UNPINNED ]; then say "OplusEyeProtect patched sha (pin it): $(sha256sum < $W/OplusEyeProtect.patched.apk | cut -d' ' -f1)"
else [ "$(sha256sum < $W/OplusEyeProtect.patched.apk | cut -d' ' -f1)" = $EP_OUT ] || { echo "patched OplusEyeProtect sha"; exit 1; }; fi
cat "$W/OplusEyeProtect.patched.apk" > $EP   # in place: keeps owner/mode/SELinux label
DB=$P/tools/live/display-dc
# (B10, 2026-11-03) DcBridge also pins min_refresh_rate = peak while DC is on (was 1ce3c71e…, kept as tools/live/display-dc/dcbridge.dex.b1)
[ "$(sha256sum < $DB/dcbridge.dex | cut -d' ' -f1)" = 44ef9e2c30d70373f09ae142ad29a6d07d4124ed08488e33a4a70f5a4a8e952b ] || { echo "dcbridge.dex sha"; exit 1; }
install -m 0644 -o root -g root $DB/dcbridge.dex "$T/system/framework/oplus-port-dcbridge.dex"
setfattr -n security.selinux -v u:object_r:system_file:s0 "$T/system/framework/oplus-port-dcbridge.dex"
printf '%s\n' "# OnePlus7Port: low-flicker option 2 -> kernel dimlayer_bl_en (DcBridge.java, tools/live/BAKE-LIST.md B1)" \
  "service port_dc_bridge /system/bin/app_process /system/bin DcBridge" \
  "    user root" \
  "    group root" \
  "    setenv CLASSPATH /system/framework/oplus-port-dcbridge.dex" \
  "    seclabel u:r:su:s0" \
  "    disabled" \
  "" \
  "on property:sys.boot_completed=1" \
  "    start port_dc_bridge" > "$T/system/etc/init/00-port-dcbridge.rc"
setfattr -n security.selinux -v u:object_r:system_file:s0 "$T/system/etc/init/00-port-dcbridge.rc"
# B2 memory extension (nandswap) workaround for the LineageOS kernel: swap file on /data, see tools/live/nandswap/port-nandswap.sh.
NS=$P/tools/live/nandswap/port-nandswap.sh
[ "$(sha256sum < $NS | cut -d' ' -f1)" = 9979c1feaf2182e03087627a7af1a665ef99380025dd8e02be4f9bba9dc3530a ] || { echo "port-nandswap.sh sha"; exit 1; }
! grep -q $'\r' $NS || { echo "port-nandswap.sh has CRLF"; exit 1; }
install -m 0755 -o root -g root $NS "$T/system/bin/port-nandswap.sh"
setfattr -n security.selinux -v u:object_r:system_file:s0 "$T/system/bin/port-nandswap.sh"
printf '%s\n' "# OnePlus7Port: ColorOS memory extension (tools/live/BAKE-LIST.md B2); the stock script races this one at boot, hence the delay" \
  "service port_nandswap /system/bin/sh -c \"sleep 5; /system/bin/port-nandswap.sh\"" \
  "    user root" \
  "    group root" \
  "    seclabel u:r:su:s0" \
  "    oneshot" \
  "    disabled" \
  "" \
  "on property:persist.sys.oplus.nandswap=*" \
  "    start port_nandswap" \
  "" \
  "on property:persist.sys.oplus.nandswap.swapsize=*" \
  "    start port_nandswap" \
  "" \
  "on property:sys.boot_completed=1" \
  "    start port_nandswap" > "$T/system/etc/init/00-port-nandswap.rc"
setfattr -n security.selinux -v u:object_r:system_file:s0 "$T/system/etc/init/00-port-nandswap.rc"
# (build 17g) Battery level/voltage/temperature lag: android.hardware.health-service.qti ignores the kernel's 5 s battery uevents (it only
# refreshes on plug events and its periodic timer, 600 s while unplugged), so the level stayed stale for minutes with the screen off until a
# screen cycle forced an update. IHealth::update() (AIDL transaction 3) refreshes and notifies BatteryService; poke it every 20 s
# (live-verified 2026-10-25: each call updates BatteryService voltage; tools/live/BAKE-LIST.md B4).
printf '%s\n' "# OnePlus7Port: keep BatteryService fresh while unplugged (build-port-b.sh, BAKE-LIST B4)" \
  'service port_health_poke /system/bin/sh -c "while :; do /system/bin/service call android.hardware.health.IHealth/default 3 >/dev/null 2>&1; sleep 20; done"' \
  "    user root" \
  "    group root" \
  "    seclabel u:r:su:s0" \
  "    disabled" \
  "" \
  "on property:sys.boot_completed=1" \
  "    start port_health_poke" > "$T/system/etc/init/00-port-health-poke.rc"
setfattr -n security.selinux -v u:object_r:system_file:s0 "$T/system/etc/init/00-port-health-poke.rc"
# Light sensor: the OP7 Pro ALS (stk_stk2232) sits under the OLED. LOS's sensors HAL (vendor) subtracts the screen's own
# light using the pixels above the sensor, fetched from the system-side AIDL service vendor.lineage.oplus_als
# IAreaCapture/default (LOS sm8150-common als/default, system_ext). AlsCorrection::init() only connects if that
# instance is VINTF-declared; otherwise service=nullptr and every reading needing correction is dropped ("Could not
# get area above sensor") -> no lux at all (seen 2026-10-16). Ship LOS's 4 files unchanged except that the rc gets a
# seclabel (ColorOS policy has no hal_lineage_oplus_als domain; su like the other port services).
A=$P/tools/live/als
sha256sum -c --quiet <<SUMS || exit 1
23da00307930cb130bcb2d96391647fddd4056f7f0845817008b9b6880f701da  $A/vendor.lineage.oplus_als-V1-ndk.so
6654a74d56e85c038c64706fcf9646f3c9d87d8a10fbaf5a74b9e9d38da4979b  $A/vendor.lineage.oplus_als.service
b1aab70a497dd2725afe29ff7110f42c1a36997aa49a5e0d8e75bbc5d2b31c2f  $A/vendor.lineage.oplus_als.service.rc
8936b22f4757b3c9620cc3e3ba14fff2645ea0c949c29528e00df3f98465184c  $A/vendor.lineage.oplus_als.service.xml
SUMS
for f in "$T/system/lib64/vendor.lineage.oplus_als-V1-ndk.so" "$T/system_ext/bin/hw/vendor.lineage.oplus_als.service" \
         "$T/system_ext/etc/init/vendor.lineage.oplus_als.service.rc" "$T/system_ext/etc/vintf/manifest/vendor.lineage.oplus_als.service.xml"; do
  [ ! -e "$f" ] || { echo "donor already has $f"; exit 1; }
done
install -m 0644 -o root -g root $A/vendor.lineage.oplus_als-V1-ndk.so "$T/system/lib64/"
setfattr -n security.selinux -v u:object_r:system_lib_file:s0 "$T/system/lib64/vendor.lineage.oplus_als-V1-ndk.so"
install -D -m 0755 -o root -g 2000 $A/vendor.lineage.oplus_als.service "$T/system_ext/bin/hw/vendor.lineage.oplus_als.service"
setfattr -n security.selinux -v u:object_r:system_file:s0 "$T/system_ext/bin/hw/vendor.lineage.oplus_als.service"
{ cat $A/vendor.lineage.oplus_als.service.rc; echo "    seclabel u:r:su:s0"; } > "$T/system_ext/etc/init/vendor.lineage.oplus_als.service.rc"
chmod 0644 "$T/system_ext/etc/init/vendor.lineage.oplus_als.service.rc"
setfattr -n security.selinux -v u:object_r:system_file:s0 "$T/system_ext/etc/init/vendor.lineage.oplus_als.service.rc"
install -m 0644 -o root -g root $A/vendor.lineage.oplus_als.service.xml "$T/system_ext/etc/vintf/manifest/"
setfattr -n security.selinux -v u:object_r:system_file:s0 "$T/system_ext/etc/vintf/manifest/vendor.lineage.oplus_als.service.xml"
# ---- my_product OnePlus 7 Pro adjustments, overlays, power profile, wireless, cutout, about device, supersize, poweron_opt (old 380-527)
# OnePlus 7 Pro hardware vs the PLK110 (OnePlus 15) my_product. With CUST_LEVEL_LIST set, ColorOS reads my_product's
# features too, so OnePlus 15-only hardware must not be declared:
#  - display: no punch hole (pop-up camera), 1440x3120 / 1080x2340 panel, 60/90 Hz without LTPO (no ADFR/PDFR, no
#    144/165 Hz exclusive modes; the OnePlus 11 also keeps adfr=2 for its LTPO panel);
#  - always-on sensor hub (aon_*), wired reverse charging, camera-hole brighten/curve: hardware/HALs not present;
#  - radio: GM1910 is LTE-only (no 5G / dual NR).
python3 -I - "$T/my_product/build.prop" "$T/my_product/etc/extension/com.oplus.oplus-feature.xml" <<'PY'
import sys, re
bp, feat = sys.argv[1], sys.argv[2]
s = open(bp).read()
def setp(k, v):
    global s
    assert re.search(r'^%s=' % re.escape(k), s, re.M), k
    s = re.sub(r'^%s=.*$' % re.escape(k), '%s=%s' % (k, v), s, flags=re.M)
def dropp(k):
    global s
    assert re.search(r'^%s=' % re.escape(k), s, re.M), k
    s = re.sub(r'^%s=.*\n' % re.escape(k), '', s, flags=re.M)
dropp('ro.oplus.display.screenhole.positon')
setp('ro.oplus.resolution.low', '1080,2340')
setp('ro.oplus.resolution.high', '1440,3120')
setp('persist.oplus.display.vrr.adfr', '0')
setp('persist.oplus.display.vrr.pdfr', '0')
dropp('persist.oplus.display.ogfr.exclusive')
# Auto brightness: the OnePlus 7 Pro also has an under-screen light sensor, but at H.40's region (stock
# my_product build.prop, 1440-wide panel), not the OnePlus 15's 732,100,770,137 on 1272x2772.
setp('ro.lcd.display.screen.underlightsensor.region', '988,251,1042,305')
setp('ro.oplus.lcd.display.screen.underlightsensor.region', '988,251,1042,305')
setp('ro.oplus.lcd.display.screen.underlightsensor.screensize', '1440,3120')
setp('ro.oplus.radio.dual_nr_enabled', 'false')
setp('ro.oplus.radio.dual_nr_toggle_enabled', 'false')
open(bp, 'w').write(s)
f = open(feat).read()
OPTIONAL = ('oplus.software.aon_aod_enable', 'oplus.software.display.camera.brighten')   # not in PYB110 .201
for name in ('oplus.software.aon_sensorhub_enable', 'oplus.software.aon_phone_camera_gesture_recognition',
             'oplus.software.aon_aod_enable', 'oplus.software.display.adfr_v32_lp', 'oplus.hardware.wired_reverse_charging',
             'oplus.software.display.camera.brighten', 'oplus.software.display.camera.curve',
             'oplus.software.radio.support_5g', 'oplus.software.radio.support_dual_nr'):
    pat = r'[ \t]*<oplus-feature name="%s"\s*/>[ \t]*\n' % re.escape(name)
    n = len(re.findall(pat, f))
    if name in OPTIONAL and n == 0:
        print('my_product: optional feature absent in donor:', name); continue
    assert n == 1, name
    f = re.sub(pat, '', f)
open(feat, 'w').write(f)
print('my_product: OnePlus 7 Pro adjustments applied')
PY
# OnePlus 15 panel overlays (static, always enabled): framework one sets a 78x141 punch-hole cutout, 176 px rounded
# corners, stable display 1272x2772 and a dual (rear) light sensor; the oplus one holds its cutout/rounded-corner
# drawables -> hole mask drawn on a notchless panel. Stock H.40 my_product has no display overlay (framework
# defaults).
# Neither can simply be dropped. The android one also defines config_availableColorModes (0,1,3,256-265,301-308);
# without it ColorOS's saved display_color_mode=301 is invalid -> system_server crash loop "Invalid colorMode: 301"
# (ColorDisplayService:1333), seen live 2026-10-16 15:11-15:12 -> keep it, blank its cutout (below).
# The oplus one holds only the rc/cutout drawables (oplus_rc_cutout.png = the visible hole), but dropping it is wrong too: ColorOS 17's default oplus_rc_top_left.png has a punch hole baked in (a
# hole then showed top-left, live 2026-10-16). Use what stock H.40 ships for this panel instead: H.40 odm
# oplus_framework_res_overlay.display.product.18821.apk (18821 = OP7 Pro project; same package name, static, target
# "oplus") = only the 4 OP7 Pro rounded corners, no cutout image -> ColorOS 17's default oplus_rc_cutout.png, which
# is fully transparent. Live-verified 2026-10-16 15:21 (no hole, no crash).
case "$DONOR" in plk110) PNUM=24831 ;; pyb110) PNUM=25825 ;; esac   # donor project number in the overlay names
f=oplus_framework_res_overlay.display.product.$PNUM.apk
if [ "$DONOR" = plk110 ]; then
  [ -f "$T/my_product/overlay/$f" ] || { echo "display overlay $f missing in donor"; exit 1; }
  rm "$T/my_product/overlay/$f"
else
  # PYB110 .201 has no oplus_framework_res_overlay.display.product.* (only the android_ one); the H.40 18821 overlay below is still
  # installed so ColorOS 17's baked top-left punch hole drawable is replaced (inert if the target package is absent).
  [ ! -e "$T/my_product/overlay/$f" ] || { echo "PYB donor unexpectedly has $f"; exit 1; }
fi
if [ -n "${SRC_H40_EXTRACT:-}" ]; then   # AutoPort: the two H.40 files below, pre-extracted (same relative paths, sha-checked below)
  mkdir -p /mnt/b14-h40eodm; mountpoint -q /mnt/b14-h40eodm && umount /mnt/b14-h40eodm; mount --bind "$SRC_H40_EXTRACT/odm" /mnt/b14-h40eodm
else
mkdir -p /mnt/b14-h40sys /mnt/b14-h40eodm
mountpoint -q /mnt/b14-h40sys && umount -R /mnt/b14-h40sys; mount -o ro,loop $P/StockRom/H40/images/system.img /mnt/b14-h40sys
mount -o ro,loop /mnt/b14-h40sys/system/euclid/odm.img /mnt/b14-h40eodm
fi
h=oplus_framework_res_overlay.display.product.18821.apk
echo "1c2200edd65a8383d402612f11a01e8f0dcf6db5097ba1103bdb7d58b0f4ed2c  /mnt/b14-h40eodm/overlay/$h" | sha256sum -c --quiet || exit 1
install -m 0644 -o root -g root "/mnt/b14-h40eodm/overlay/$h" "$T/my_product/overlay/$h"
setfattr -n security.selinux -v "u:object_r:system_file:s0" "$T/my_product/overlay/$h"
# Power profile: the GSI's framework-res power_profile is a placeholder (battery.capacity=2.0, every component 0.1)
# -> Settings "2 mAh (typical)" (DeviceInfoUtils.getBatteryCapacity uses PowerProfile, the prop only on confidential
# builds) and meaningless battery-usage stats. ColorOS reads <partition>/etc/power_profile/power_profile.xml
# (oplus-framework.jar); stock H.40 ships this phone's profile in odm and my_product (identical, capacity 4065).
# LOS has the same data in its vendor overlay OPlusFrameworksResTarget, but /vendor/overlay is hidden by the Axis GSI
# (rw-system.sh: mount -o bind /system/axisgsi/vo /vendor/overlay). Live-verified 2026-10-16 15:30: 4065, user OK.
pp=/mnt/b14-h40eodm/etc/power_profile/power_profile.xml
echo "fbe1bffc1e328b9527dac42e321aab0fdcb9554faae425809757e90399f276dc  $pp" | sha256sum -c --quiet || exit 1
if [ "$DONOR" = plk110 ]; then
  [ ! -e "$T/my_product/etc/power_profile" ] || { echo "donor my_product already has power_profile"; exit 1; }
  install -d -m 0755 -o root -g root "$T/my_product/etc/power_profile"
  install -m 0644 -o root -g root "$pp" "$T/my_product/etc/power_profile/power_profile.xml"
else   # PYB110 ships the OnePlus 16 profile there: replace its content in place (keeps owner/mode/label)
  [ -f "$T/my_product/etc/power_profile/power_profile.xml" ] || { echo "PYB donor power_profile.xml missing"; exit 1; }
  cat "$pp" > "$T/my_product/etc/power_profile/power_profile.xml"
fi
setfattr -n security.selinux -v "u:object_r:system_file:s0" "$T/my_product/etc/power_profile"
setfattr -n security.selinux -v "u:object_r:system_file:s0" "$T/my_product/etc/power_profile/power_profile.xml"
# Wireless charging: the donor declares the OnePlus 15's 50 W wireless charging (About phone "50W 无线闪充" via
# app feature os.charge.settings.wirelesscharging.power, read since CUST_LEVEL_LIST). OP7 Pro = Warp Charge 30, wired
# only; stock H.40 declares no wireless feature. Drop exactly these features (live-verified 2026-10-16, user OK).
python3 -I - "$T/my_product/etc/extension" <<'PY'
import sys, os
ext = sys.argv[1]
drop = {
    'com.oplus.app-features.xml': ['os.charge.settings.wirelesscharging.power', 'os.charge.settings.wirelesscharge.support',
                                   'oplus.power.onwirelesscharger.support', 'oplus.power.wirelesschgwhenwired.support',
                                   'os.charge.settings.wirelesschargingcoil.position'],
    'feature_com.android.battery.xml': ['oplus.power.onwirelesscharger.support'],
}
for fn, names in drop.items():
    p = os.path.join(ext, fn)
    lines = open(p).read().split('\n')
    out = []
    for l in lines:
        hit = [n for n in names if 'name="%s"' % n in l]
        if hit:
            names.remove(hit[0])
            continue
        out.append(l)
    assert not names, '%s: not found %s' % (fn, names)
    with open(p, 'r+') as f:   # in place: keeps the SELinux label
        f.seek(0); f.write('\n'.join(out)); f.truncate()
print('my_product: wireless charging features removed')
PY
umount /mnt/b14-h40eodm; if mountpoint -q /mnt/b14-h40sys; then umount /mnt/b14-h40sys; fi   # h40sys is not mounted with SRC_H40_EXTRACT
# The android overlay (24831) stays for its colour modes, but its cutout path/rect approximation are the OnePlus 15's
# 78x141 hole -> emptied in place by tools/patch-cutout-overlay.py (the rect approximation references the same
# string). Live-verified 2026-10-16 15:24 with no fabricated overlays: DisplayCutout insets 0, colour mode 301 valid.
a=android_framework_res_overlay.display.product.$PNUM.apk
case "$DONOR" in
  plk110) OV_SHA=d0ddc215d6e0acbb01b7886403478e791de46af66998b517bf3a96f8703b3efc; OV_OUT=72ffbbddf5a7712e7be6bc1e89683929f9b3ce05b3caadd4870bc302d6b17121 ;;
  pyb110) OV_SHA=1db7c6caf4bc2b08bd3ada05155921e001fdfef539061fc52d3952ca228ba29e; OV_OUT=PYB_UNPINNED ;;   # hole is "M -39,0 L -39,143 L 39,143 L 39,0 Z"
esac
echo "$OV_SHA  $T/my_product/overlay/$a" | sha256sum -c --quiet || exit 1
python3 -I $P/tools/patch-cutout-overlay.py "$T/my_product/overlay/$a" "$W/$a"
if [ "$OV_OUT" = PYB_UNPINNED ]; then say "cutout overlay patched sha (pin it): $(sha256sum < "$W/$a" | cut -d' ' -f1)"
else echo "$OV_OUT  $W/$a" | sha256sum -c --quiet || exit 1; fi
cat "$W/$a" > "$T/my_product/overlay/$a"   # in place: keeps owner/mode/SELinux label
# About device: show the real phone. Only display values change (market names, LUMO camera badge, typical battery);
# ro.product.model/name/device stay PLK110/OP60FFL1 because ColorOS apps and services key features on them.
# ro.product.batterycapacity is unset in every partition (stock sets it at runtime) -> Settings showed "2 mAh";
# OnePlus 7 Pro typical capacity 4000 mAh.
python3 -I - "$T/my_manifest/build.prop" "$T/my_product/build.prop" "$DONOR_MODEL" <<'PY'
import sys, re
man, prod, bp_model = sys.argv[1], sys.argv[2], sys.argv[3]
m = open(man).read()
gen = '16' if 'PYB110' in bp_model else '15'   # donor generation in the market name
for old, new in (('ro.vendor.oplus.market.name=一加 ' + gen, 'ro.vendor.oplus.market.name=一加 7 Pro'),
                 ('ro.vendor.oplus.market.enname=OnePlus ' + gen, 'ro.vendor.oplus.market.enname=OnePlus 7 Pro')):
    assert m.count(old + '\n') == 1, old
    m = m.replace(old + '\n', new + '\n')
open(man, 'w').write(m)
p = open(prod).read()
if p.count('\nro.oplus.camera.isSupportLumo=1\n') == 1:
    p = p.replace('\nro.oplus.camera.isSupportLumo=1\n', '\nro.oplus.camera.isSupportLumo=0\n')
else:
    assert 'isSupportLumo' not in p, 'isSupportLumo has an unexpected value'
    print('PYB110: no isSupportLumo in my_product build.prop (nothing to turn off)')
assert 'ro.product.batterycapacity=' not in p
p += '\n# OnePlus7Port: typical battery capacity (Settings > About device)\nro.product.batterycapacity=4000\n'
open(prod, 'w').write(p)
print('about device: OnePlus 7 Pro names, battery 4000 mAh, LUMO off')
PY
# Storage size prop: stock supersize.rc runs system_ext/bin/getsuperlayoutsize.sh (CRLF file) at boot_completed; it
# sums lpdump sectors of the super partition. OnePlus 7 Pro has no super -> lpdump fails -> the prop becomes "\r".
# com.oplus.wallpapers OdinHeaderTools parses `getprop` with readLine() (splits on \r) -> "[...super_size]: [" ->
# StringIndexOutOfBounds -> process dies (Flux theme editing, build 12). Set it from the real slot-B partitions
# (system_b 3640655872 + vendor_b 1073741824 + odm_b 104857600 bytes on GM1910) and drop the script's trigger.
grep -q '^ro.oplus.storage.super_size=' "$T/system_ext/etc/build.prop" && { echo "super_size already in system_ext build.prop"; exit 1; }
printf '\n# OnePlus7Port: no super partition (getsuperlayoutsize.sh would set "\\r")\nro.oplus.storage.super_size=4819255296\n' >> "$T/system_ext/etc/build.prop"
rm "$T/system_ext/etc/init/supersize.rc"
# Incoming SMS (live-verified 2026-10-17, docs/2026-10-17-ims-volte-findings.md): the donor ships persist.vendor.radio.poweron_opt=1.
# With it qcrild buffers incoming SMS ("MT SMS ACK NEEDED Power Opt buffer") and waits for an ACK handshake ColorOS never
# sends, times out after ~20 s and the network redelivers forever; nothing reaches Android. 0 + qcrild restart: all texts arrived.
grep -qx 'persist.vendor.radio.poweron_opt=1' "$T/system_ext/etc/build.prop" || { echo "poweron_opt line changed in donor"; exit 1; }
sed -i 's/^persist\.vendor\.radio\.poweron_opt=1$/persist.vendor.radio.poweron_opt=0/' "$T/system_ext/etc/build.prop"
# ---- identity, brightness, IMS, Breeno, loc_sys_service, AON, getprop shim, stune, wallpaper keeper, vrr, SE, volume key, ccodec (old 538-749)
# Identity (B17, tools/live/prop-compare/IDENTITY.md "safe to switch", user-approved 2026-11-03): display-only OnePlus 7 Pro
# values from H.40 odm/build.prop. Kept donor: fingerprints, security patch, OTA/version keys, prjname (device/name/build.product:
# switched since 17j, see the B17 test-key loop below).
for kv in "ro.product.bootimage.model=${DONOR_MODEL}:GM1910" "ro.product.bootimage.name=${DONOR_MODEL}:OnePlus7Pro_CH" "ro.product.bootimage.device=${DONOR_DEVICE}:OnePlus7Pro"; do
  k=${kv%%=*}; v=${kv#*=}; old=${v%%:*}; new=${v#*:}
  grep -qx "$k=$old" "$T/my_manifest/build.prop" || { echo "$k not $old in donor my_manifest"; exit 1; }
  sed -i "s/^$k=$old\$/$k=$new/" "$T/my_manifest/build.prop"
done
case "$DONOR" in plk110) AUTH_OLD=25C44PC2W477 ;; pyb110) AUTH_OLD=26C44PC20319 ;; esac
grep -qx "ro.product.authentication=$AUTH_OLD" "$T/my_product/build.prop" || { echo "authentication changed in donor my_product"; exit 1; }
sed -i "s/^ro\.product\.authentication=$AUTH_OLD\$/ro.product.authentication=2018CP7481/" "$T/my_product/build.prop"
# (B17 test keys, build 17j) IDENTITY.md "test first" keys, live-tested 2026-11-03 on 17i as a "# OnePlus7Port B17-test" block in
# /vendor/build.prop (camera photo OK, apps open): Build.DEVICE / Build.PRODUCT / ro.build.product = the H.40 values. Baked here in
# my_manifest (where the donor sets them), NOT in vendor: the vendor flash drops the live block. The camera HAL reads
# ro.build.product (GM1910 on H.40), libarcsoft_portrait_distortion_correction ro.product.device. Revert: drop these three.
for kv in "ro.product.device=${DONOR_DEVICE}:OnePlus7Pro" "ro.product.name=${DONOR_MODEL}:OnePlus7Pro_CH" "ro.build.product=${DONOR_MODEL}:GM1910"; do
  k=${kv%%=*}; v=${kv#*=}; old=${v%%:*}; new=${v#*:}
  [ "$(grep -c "^$(printf '%s' "$k" | sed 's/\./\\./g')=" "$T/my_manifest/build.prop")" = 1 ] || { echo "$k not set exactly once in donor my_manifest"; exit 1; }
  grep -qx "$k=$old" "$T/my_manifest/build.prop" || { echo "$k not $old in donor my_manifest"; exit 1; }
  sed -i "s/^$k=$old\$/$k=$new/" "$T/my_manifest/build.prop"
done
# Auto-brightness (live-verified 2026-10-17): ColorOS 17's lux->nit curve is built in; the donor's nit->level table in
# display_brightness_config_default.xml is for the donor panel. The OP7 Pro maps level/10 -> panel raw, and H.40's stock lux->raw
# curve is 2.55 x that nit curve at every sampled lux, so nit(level) = level/10/2.55 (tools/live/brightness/rescale_nits.py).
BR=$P/tools/live/brightness/display_brightness_config_default.h40nits.xml
[ "$(sha256sum "$T/system_ext/etc/display_brightness_config_default.xml" | cut -d' ' -f1)" = 0cf4765eddae24ccbb7847635e8b21b26d5bcd9c7915391e4e27852cca8e28c7 ] || { echo "donor brightness table changed"; exit 1; }
[ "$(sha256sum $BR | cut -d' ' -f1)" = ae420be14e7dbff8f2c46f2a035749e829cec49a939748d1510ffef40651cf3c ] || { echo "brightness table sha"; exit 1; }
cat $BR > "$T/system_ext/etc/display_brightness_config_default.xml"
# IMS / VoLTE (live-verified 2026-10-17: outgoing calls over VoLTE, SMS over IMS). ColorOS 17's org.codeaurora.ims only has an
# AIDL IImsRadio client; the LOS24 vendor only has the HIDL one, so MMTEL stayed UNAVAILABLE and calls fell back to CS (cause 248).
# Ship the LOS24 ims.apk (HIDL ImsRadio) with: QtiImsExt.<init> calling ColorOS's QtiImsExtBase.<init>(Executor, Context) (the base
# class from ColorOS ims-ext-common stores mContext; the no-arg call left it null -> NPE -> com.android.phone crash), ColorOS's
# own signing block (tools/transplant-apk-sigblock.py; system apps are scanned without digest checks, same signer keeps the shared
# uid android.uid.qtiphone), the matching LOS JNI libs, and a library dependency so the app can load android.hidl.manager-V1.0-java.
# Artifacts and how they were made: tools/live/ims/ (smali edit, apktool 3.0.3).
# (build 17h) Incoming SMS fix (BAKE-LIST §B "Incoming SMS / IMS regression after 17g", user-verified live 2026-10-18): the 17g APK
# (470b8c12…) was skipped by PackageManager (resources.arsc not 4-byte aligned, R+ target) and, once aligned, the LOS app crashed on the
# donor oplus-ims-ext.jar factory (getImsServiceSub need +2 params). ims-sms-fix-cossig.apk = zipalign -f 4 BEFORE the signing-block
# transplant + OplusImsFactory.getInstance() using its own base factory (tools/live/ims/los/sms-fix-smali/). zipalign -c 4 verified.
I=$P/tools/live/ims
case "$DONOR" in plk110) IMS_SHA=93c199d707cd6dd908b82e3d24d7aa3bdc15f28aa858aae9b9b14c362ca1f48c ;; pyb110) IMS_SHA=3bb9c9989cab8b8f43c574f1eb409f15f60bcc3554cbb7bbe12055f5aa7b078a ;; esac
# PYB110: the LOS ims.apk fix was built against the .105 oplus-ims-ext.jar; compatibility with .201 is UNVERIFIED (check IMS/SMS on the phone).
sha256sum -c --quiet <<SUMS || exit 1
$IMS_SHA  $T/system_ext/priv-app/ims/ims.apk
2d0231984a8b68c24f312f5b3ee227354e5cc706371476eff5cf67d892e8c3c0  $T/product/etc/permissions/ims_ext_common.xml
296bc757dc9d99373c815c594529494a72e79859baa5ddabb25ada296f18acbf  $I/los/ims-sms-fix-cossig.apk
a0e3a93431cdc272374fe3b3c47654f27f1b0a4d97cf0eafb7082f66d994a5c9  $I/ims_ext_common.xml
96101b310219f1ce1c4f52c3f5fadd1a609aec7128a06d8a8811bd05540d7902  $I/los/lib-arm64/libimsmedia_jni.so
c34698971641c9536e50ab69b9225ed97954f0c57f641d31e56537e414813177  $I/los/lib-arm64/libimscamera_jni.so
SUMS
python3 -I - "$I/los/ims-sms-fix-cossig.apk" <<'PY' || { echo "ims.apk resources.arsc not stored/4-aligned"; exit 1; }
import sys, zipfile, struct
z = zipfile.ZipFile(sys.argv[1]); i = z.getinfo('resources.arsc'); f = open(sys.argv[1], 'rb'); f.seek(i.header_offset)
h = f.read(30); n, e = struct.unpack('<HH', h[26:30]); off = i.header_offset + 30 + n + e
sys.exit(0 if i.compress_type == 0 and off % 4 == 0 else 1)
PY
cat "$I/los/ims-sms-fix-cossig.apk" > "$T/system_ext/priv-app/ims/ims.apk"     # keeps owner, mode and label
cat "$I/ims_ext_common.xml" > "$T/product/etc/permissions/ims_ext_common.xml"
rm -rf "$T/system_ext/priv-app/ims/oat"                                           # odex/vdex belong to the ColorOS apk
IL=$T/system_ext/priv-app/ims/lib/arm64
rm -f "$IL/libimsmedia_jni.so"                                                    # donor: symlink to the ColorOS jni lib
for f in libimsmedia_jni.so libimscamera_jni.so; do
  install -m 0644 -o root -g root "$I/los/lib-arm64/$f" "$IL/$f"
  setfattr -n security.selinux -v u:object_r:system_lib_file:s0 "$IL/$f"
done
# Breeno wake-up on the H.40 DSP (live-verified 2026-10-17 14:18, user confirmed; docs/2026-10-17-handoff.md §11d, tools/live/breeno-sva/):
# ColorOS 17's own wake service (com.oplus.ovoicemanager.wakeup, its settings switch and enroll screen) runs on the H.40 Qualcomm SVA first
# stage. Its donor model/uuid (Breeno-Speech 68ac2d41-..., aispeech container) cannot run on the H.40 ADSP, so: (1) the donor
# OVoiceManagerService.apk is the smali-patched copy (keyphrase xiaobuxiaobu, raw model file, SVA 3.0 opaque start data; ColorOS 17
# signing block transplanted), (2) OVMS_settings.xml uses the QTI SVA vendor uuid 68ab2d40-e860-11e3-95ef-0002a5d5c51b, (3) the model
# OVMS_1st_wakeup.bin is H.40's sm3_xiaobuxiaobu.uim. The package stays ENABLED (earlier builds disabled it at boot because the unpatched
# app crash-looped the audio HAL through the SoundTrigger HAL), so there is no 01-port-audio-fix.rc any more. The OnePlus
# com.oneplus.voicewakeup app and the H.40 listen libs are not shipped (build 17/17b had them; not needed).
if [ "$DONOR" != plk110 ]; then
  # PYB110 .201: no my_product/etc/OVMS_1st_wakeup.bin (it ships breenospeech2/custom_lpi/*.umdl, a different model layout), so the H.40 model is added.
  # UNVERIFIED on the phone: if the patched app crash-loops the audio HAL (see audio-hal-crash-loops), disable the package at boot as old builds did.
  # Revised 2026-11-17 (user request): patch the .201 app itself. adapter/u/c.smali has the same class path in .201 and patch_c17.py's asserts all pass;
  # settings/model files are the .105-era bake files. The model .bin does not exist in .201 (it uses breenospeech2/custom_lpi), so it is added.
  BS=$P/tools/live/breeno-sva
  sha256sum -c --quiet <<SUMS || exit 1
0d1ce62eef5fb551173d563b8c59a26e708a377c5ca4a4268c817b80917d54b9  $BS/OVMS_settings.xml
b8591733916c56872df3879ba4f733d7d297500e08dd40409454236a106e6371  $BS/OVMS_1st_wakeup.bin
SUMS
  OV=$T/my_product/priv-app/OVoiceManagerService
  [ -f "$OV/OVoiceManagerService.apk" ] || { echo "donor OVoiceManagerService.apk missing"; exit 1; }
  for t in baksmali smali zipalign; do have_tool $t || die "$t missing in WSL"; done
  B="$W/breeno"; mkdir -p "$B"; (cd "$B" && unzip -q -o "$OV/OVoiceManagerService.apk" classes2.dex && baksmali d classes2.dex -o sm/classes2 >/dev/null)
  cp "$BS/patch_c17.py" "$BS/sva_opaque_helper.smali.txt" "$B/"
  (cd "$B" && python3 -I patch_c17.py) || die "Breeno patch_c17.py does not apply to the .201 OVoiceManagerService"
  (cd "$B" && smali a sm/classes2 -o classes2.new.dex) || die "smali failed for OVoiceManagerService"
  python3 -I "$P/tools/live/power-drain/wallpaper/replace_dex.py" "$OV/OVoiceManagerService.apk" classes2.dex "$B/classes2.new.dex" "$B/u.apk"
  zipalign -f -p 4 "$B/u.apk" "$B/a.apk"
  python3 -I "$P/tools/transplant-apk-sigblock.py" "$OV/OVoiceManagerService.apk" "$B/a.apk" "$B/OVoiceManagerService-sva-c201sig.apk"
  [ "$(unzip -p "$B/OVoiceManagerService-sva-c201sig.apk" 'classes*.dex' | grep -ac svaOpaque)" -ge 1 ] || { echo "breeno apk lacks svaOpaque"; exit 1; }
  say "Breeno .201 patched apk sha (pin it): $(sha256sum < "$B/OVoiceManagerService-sva-c201sig.apk" | cut -d' ' -f1)"
  replace_file "$OV/OVoiceManagerService.apk" "$B/OVoiceManagerService-sva-c201sig.apk"
  rm -rf "$OV/oat"
  for d in "$T/my_product/etc" "$T/my_product/etc/breenospeech2"; do
    [ -f "$d/OVMS_settings.xml" ] || { echo "donor lacks $d/OVMS_settings.xml"; exit 1; }
    replace_file "$d/OVMS_settings.xml" "$BS/OVMS_settings.xml"
    [ ! -e "$d/OVMS_1st_wakeup.bin" ] || { echo "donor already has $d/OVMS_1st_wakeup.bin"; exit 1; }
    install -m 0644 -o root -g root "$BS/OVMS_1st_wakeup.bin" "$d/OVMS_1st_wakeup.bin"
    setfattr -n security.selinux -v u:object_r:system_file:s0 "$d/OVMS_1st_wakeup.bin"
  done
  # Live-verified 2026-11-17: the .201 app tries its "LP v3" model first (u5/a.e -> custom_lpi/xbxb_lpi_1st.umdl + .graph, a 103168-byte
  # container). The H.40 audio HAL cannot open that graph (gcs_enable graph_open -131), startRecognition fails, SoundTriggerHalEnforcer
  # sets sys.audio.restart.hal and init SIGKILLs the HAL every ~6 s. With the custom_lpi files absent the app logs LP_SYSTEM_XBXB_UMDL_MISSING,
  # falls back to the raw OVMS_1st_wakeup.bin path patched above and START_RECOGNITION succeeds (HAL stable). So the models are removed.
  rm -rf "$T/my_product/etc/breenospeech2/custom_lpi"
  [ ! -e "$T/my_product/etc/breenospeech2/custom_lpi" ] || die "custom_lpi still present"
  rm -f "$T/system/etc/init/01-port-audio-fix.rc"
else
BS=$P/tools/live/breeno-sva
sha256sum -c --quiet <<SUMS || exit 1
cd68824e961323f7b2f47b42638150a5f99e236fa79d85e18b65b5fea6f34238  $BS/OVoiceManagerService-sva-c17sig.apk
0d1ce62eef5fb551173d563b8c59a26e708a377c5ca4a4268c817b80917d54b9  $BS/OVMS_settings.xml
b8591733916c56872df3879ba4f733d7d297500e08dd40409454236a106e6371  $BS/OVMS_1st_wakeup.bin
SUMS
[ "$(unzip -p "$BS/OVoiceManagerService-sva-c17sig.apk" 'classes*.dex' | grep -ac svaOpaque)" -ge 1 ] || { echo "breeno apk lacks svaOpaque"; exit 1; }   # grep -c reads all (grep -q + pipefail = SIGPIPE)
OV=$T/my_product/priv-app/OVoiceManagerService
[ -f "$OV/OVoiceManagerService.apk" ] || { echo "donor OVoiceManagerService.apk missing"; exit 1; }
for f in "$T/my_product/etc/OVMS_settings.xml" "$T/my_product/etc/breenospeech2/OVMS_settings.xml" "$T/my_product/etc/OVMS_1st_wakeup.bin" "$T/my_product/etc/breenospeech2/OVMS_1st_wakeup.bin"; do
  [ -f "$f" ] || { echo "donor lacks $f"; exit 1; }
done
replace_file "$OV/OVoiceManagerService.apk" "$BS/OVoiceManagerService-sva-c17sig.apk"      # keeps owner, mode and label
rm -rf "$OV/oat"                                                                           # odex/vdex belong to the donor apk
for d in "$T/my_product/etc" "$T/my_product/etc/breenospeech2"; do
  replace_file "$d/OVMS_settings.xml" "$BS/OVMS_settings.xml"
  replace_file "$d/OVMS_1st_wakeup.bin" "$BS/OVMS_1st_wakeup.bin"
done
rm -f "$T/system/etc/init/01-port-audio-fix.rc"
fi
# (BAKE-LIST B9, live-verified 2026-11-02) /system_ext/bin/loc_sys_service bridges Qualcomm's AIDL location extras
# (vendor.qti.gnss.ILocAidl*: FLP, geofence, geocoder, debug report) for Qualcomm location apps that are not shipped here; the
# LOS24 vendor only has the HIDL GNSS stack, so it retried ILocAidlGnss/default about 3x per second forever (servicemanager lazy
# start + init control message each time). GPS uses the HIDL GNSS HAL directly. Do not start it.
[ -f "$T/system_ext/etc/init/loc_sys_service.rc" ] || { echo "donor loc_sys_service.rc moved"; exit 1; }
rm -f "$T/system_ext/etc/init/loc_sys_service.rc"
# (BAKE-LIST B12, user request 2026-11-03) Hide Settings > Display & brightness > 注视时不息屏 ("keep on looking" / screen
# attention): the OnePlus 15 has an always-on (AON) front camera; the OnePlus 7 Pro front camera is a motorised pop-up. The
# static overlay aon.frameworkres.overlay.product sets config_adaptive_sleep_available=true (the only gate Settings'
# KeepOnLookingController finds here; no oplus.hardware.aon_enable feature) and config_defaultAttentionService =
# com.aiunit.aon/.AONAttentionService. Without it the entry is hidden and AttentionManagerService has no camera-based service.
if [ -f "$T/my_product/overlay/aon.frameworkres.overlay.product.apk" ]; then rm -f "$T/my_product/overlay/aon.frameworkres.overlay.product.apk"
elif [ "$DONOR" = plk110 ]; then echo "donor AON framework overlay moved"; exit 1
else say "PYB110: no AON framework overlay in my_product (nothing to remove)"; fi
# The overlay is not the only gate: my_product com.oplus.oplus-feature.xml declares oplus.hardware.aon_enable (Settings shows the
# entry for it too) and the AON camera features aon_enable / aon_pay_qrcode_enable / aon_phone_enable / aon_phone_mute /
# aon_distance_detection_enable / aon_pose_detection_enable, all built for an always-on front camera. Drop every oplus.*.aon_* feature.
OF="$T/my_product/etc/extension/com.oplus.oplus-feature.xml"
grep -q '<oplus-feature name="oplus.hardware.aon_enable"/>' "$OF" || { echo "donor oplus.hardware.aon_enable feature moved"; exit 1; }
sed -i -E '/^[[:space:]]*<oplus-feature name="oplus\.(hardware|software)\.aon_[a-z_]+"[[:space:]]*\/>[[:space:]]*$/d' "$OF"
! grep -qE 'oplus\.(hardware|software)\.aon_' "$OF" || { echo "AON features left in oplus-feature.xml"; exit 1; }
# (BAKE-LIST B31, live-verified by the user 2026-11-18 on PYB .201) Fingerprint spot did not light in battery-saver mode, so the optical
# sensor captured nothing ("Up too fast") and the lock screen could not be unlocked. Saver sets secure oplus_customize_screen_refresh_rate=2
# (60 Hz); with feature oplus.software.lockscreen.enable.standard_refresh_rate, services UdfpsHelperExtImpl.shouldNotifyRefreshRate() is true,
# preShowUdfpsOverlay posts a HAL sendFingerprintCmd(1021) on the same handler thread that later has to send panel feature 28 (HBM spot), which
# blocks ~560 ms, so 28=1 arrives at finger release. Without the feature the code takes requestRefreshRate(1) and 28=1 follows in ~1 ms.
grep -q '<oplus-feature name="oplus.software.lockscreen.enable.standard_refresh_rate"/>' "$OF" || { echo "donor standard_refresh_rate feature moved"; exit 1; }
sed -i -E '/^[[:space:]]*<oplus-feature name="oplus\.software\.lockscreen\.enable\.standard_refresh_rate"[[:space:]]*\/>[[:space:]]*$/d' "$OF"
! grep -q 'enable.standard_refresh_rate' "$OF" || { echo "standard_refresh_rate feature left in oplus-feature.xml"; exit 1; }
# (BAKE-LIST B33, user request + live-verified 2026-11-19 on PYB .201) The OnePlus 7 Pro has no wireless charging coil, but the
# Battery app (com.oplus.battery) shows "Wireless charging" (Quiet charging) and "Reverse wireless charging" in Charging settings and
# offers the reverse-charging QS tile (WirelessReverseControService) when the system feature oplus.power.onwirelesscharger.support is
# declared. Live: removing it (bind-mounted XML + framework restart) removed both settings entries and the tile; restoring it brought
# them back.
WLF="$T/my_product/etc/permissions/com.oppo.features_allnet_android.xml"
if [ "$DONOR" = pyb110 ]; then grep -q '<feature name="oplus.power.onwirelesscharger.support" */>' "$WLF" || { echo "donor wireless charger feature moved"; exit 1; }; fi
if [ -f "$WLF" ]; then
  sed -i -E '/^[[:space:]]*<feature name="oplus\.power\.onwirelesscharger\.support"[[:space:]]*\/>[[:space:]]*$/d' "$WLF"
  ! grep -q 'oplus.power.onwirelesscharger.support' "$WLF" || { echo "wireless charger feature left in $WLF"; exit 1; }
fi
! grep -rqs '"oplus.power.onwirelesscharger.support"' "$T/my_product/etc/permissions" "$T/system/etc/permissions" "$T/product/etc/permissions" || { echo "wireless charger feature declared elsewhere"; exit 1; }
# (BAKE-LIST B13, user request 2026-11-03) App root checks: the port keeps ro.debuggable=1 / ro.secure=0 for adb root, and OPPO
# Health (SafetyCheck.checkForDangerousProps, via `getprop` output) shows a "device rooted" dialog and closes. /product/bin is first
# on every app's PATH, so a getprop shim there shows app uids ro.debuggable=0 / ro.secure=1; callers of /system/bin/getprop and
# non-app uids get the real values. Independent of the app version.
GP=$P/tools/live/health-root/getprop
[ "$(sha256sum < $GP | cut -d' ' -f1)" = f92f6644530d11d3062d8685fe65bf8c32ec4976dc728b57e6858ecac65ed5b0 ] || { echo "getprop shim sha"; exit 1; }
[ -d "$T/product/bin" ] && [ ! -e "$T/product/bin/getprop" ] || { echo "donor /product/bin changed"; exit 1; }
install -m 0755 -o 0 -g 2000 "$GP" "$T/product/bin/getprop"
setfattr -n security.selinux -v "u:object_r:system_file:s0" "$T/product/bin/getprop"
# (BAKE-LIST B15, live-verified 2026-11-03) Battery: schedtune + IMS rebind loop.
# (a) /dev/stune: the LOS kernel has CONFIG_SCHED_TUNE (BOOSTGROUPS_COUNT 6) and the LOS vendor (powerhint.json, init.target.rc)
# writes /dev/stune/{top-app,camera-daemon}/schedtune.*; LOS mounts it from /system/etc/task_profiles/cgroups_28.json (libprocessgroup
# loads cgroups_<ro.product.first_api_level>.json; 28 here), which ColorOS does not ship -> the power HAL retried every 0.5 s forever.
# Ship LOS's cgroups_28.json, a task_profiles_28.json that keeps ColorOS's cpu actions and adds LOS's schedtune joins
# (make-task-profiles.py; LOS's own file would replace the 11 profiles), and LOS's mkdir/chown block as an early-init rc.
ST=$P/tools/live/stune
sha256sum -c --quiet <<SUMS || exit 1
a928742b8697cd78dece935dfc07238c5bbddde58764210e633c8332b95d5c1c  $T/system/etc/task_profiles.json
18497edda1c81883eac3063708ded1b7deb493c519d6ae320b3048c5e090056c  $ST/cgroups_28.json
ec4614ffdb5fe69b6108b9a66b383918ae24e4d5426d2bc6b20a04f968542d6b  $ST/task_profiles_28.json
593d5b0b42f41071fa3e97236878473da6c311d6e2ed95bb35a93b6409c994ef  $ST/00-port-stune.rc
SUMS
[ ! -e "$T/system/etc/task_profiles" ] && ! grep -q '"schedtune"' "$T/system/etc/cgroups.json" || { echo "donor already has task_profiles/ or a schedtune cgroup"; exit 1; }
install -d -m 0755 -o root -g root "$T/system/etc/task_profiles"
setfattr -n security.selinux -v u:object_r:system_file:s0 "$T/system/etc/task_profiles"
install -m 0644 -o root -g root "$ST/cgroups_28.json" "$T/system/etc/task_profiles/cgroups_28.json"
setfattr -n security.selinux -v u:object_r:cgroup_desc_file:s0 "$T/system/etc/task_profiles/cgroups_28.json"
install -m 0644 -o root -g root "$ST/task_profiles_28.json" "$T/system/etc/task_profiles/task_profiles_28.json"
setfattr -n security.selinux -v u:object_r:task_profiles_file:s0 "$T/system/etc/task_profiles/task_profiles_28.json"
install -m 0644 -o root -g root "$ST/00-port-stune.rc" "$T/system/etc/init/00-port-stune.rc"
setfattr -n security.selinux -v u:object_r:system_file:s0 "$T/system/etc/init/00-port-stune.rc"
# (b) com.android.phone's ImsRilConnector rebinds org.codeaurora.ims/.ImsRilService every ~0.5 s (the LOS24-based ims.apk returns a
# null binder). Keep that component disabled from a boot_completed one-shot (no-op once disabled; survives a /data wipe).
# Revert on the phone: setprop persist.sys.port.imsrilsvc on; pm enable org.codeaurora.ims/org.codeaurora.ims.ImsRilService
IR=$P/tools/live/ims-rilsvc/00-port-ims-rilsvc.rc
[ "$(sha256sum < $IR | cut -d' ' -f1)" = 2eda53c0af42580fd1b166b339f2c3e3aa91ba2acec7264922e9eb3ad470a9d0 ] || { echo "ims rilsvc rc sha"; exit 1; }
install -m 0644 -o root -g root "$IR" "$T/system/etc/init/00-port-ims-rilsvc.rc"
setfattr -n security.selinux -v u:object_r:system_file:s0 "$T/system/etc/init/00-port-ims-rilsvc.rc"
# (BAKE-LIST B18, build 17j, user-approved) Keep the user's live wallpaper across reboots: ColorOS WMS binds the default (Infiniti1)
# at every boot and rewrites wallpaper_info.xml. port_wp_keep (oneshot, 20 s after boot_completed) re-applies the component saved in
# /data/port/wp/wallpaper-component through IWallpaperManager.setWallpaperComponentChecked (system+lock; oplus-port-wpset.dex, helper
# verified live 2026-11-03); port_wp_save (separate non-oneshot inotifyd service) saves later user changes, never the boot default
# (/dev/.port_wp_ready set by the oneshot + 150 s system_server-uptime guard). No saved file: nothing happens until the user's next
# change (or seed the file by hand). Sources: tools/live/power-drain/wallpaper/keep/ (SHA256SUMS), helper source reapply/proj.
WK=$P/tools/live/power-drain/wallpaper/keep
(cd "$WK" && sha256sum -c --quiet SHA256SUMS) || { echo "wallpaper keep sources changed (B18)"; exit 1; }
sha256sum -c --quiet <<SUMS || { echo "wallpaper keep source shas (B18)"; exit 1; }
ef2826e697224b5f5823cf506472d63ab5de3c39e08103ec3b3c72869560c186  $WK/portwpset.dex
a8e189f128c78f7bbd093931f47d0daa26be4d720d03b43fbe294f3824bf6e6c  $WK/port-wp-keep.sh
12c414ac01ce04e2b34ec96e66e79e9f253270efd0fcfec484f289d173fa10d2  $WK/port-wp-save.sh
7b3e9cf3a0e6d63167ca40bfb9be2f3b24fb4d74a9343c0530ce98b321cba581  $WK/00-port-wpkeep.rc
SUMS
! grep -q $'\r' "$WK/port-wp-keep.sh" "$WK/port-wp-save.sh" "$WK/00-port-wpkeep.rc" || { echo "wallpaper keep sources have CRLF (B18)"; exit 1; }
for f in system/framework/oplus-port-wpset.dex system/bin/port-wp-keep.sh system/bin/port-wp-save.sh system/etc/init/00-port-wpkeep.rc; do
  [ ! -e "$T/$f" ] || { echo "donor already has $f"; exit 1; }
done
[ -e "$T/system/bin/inotifyd" ] || { echo "donor has no /system/bin/inotifyd (B18 watcher)"; exit 1; }
install -m 0644 -o root -g root "$WK/portwpset.dex" "$T/system/framework/oplus-port-wpset.dex"
install -m 0755 -o 0 -g 2000 "$WK/port-wp-keep.sh" "$T/system/bin/port-wp-keep.sh"
install -m 0755 -o 0 -g 2000 "$WK/port-wp-save.sh" "$T/system/bin/port-wp-save.sh"
install -m 0644 -o root -g root "$WK/00-port-wpkeep.rc" "$T/system/etc/init/00-port-wpkeep.rc"
for f in system/framework/oplus-port-wpset.dex system/bin/port-wp-keep.sh system/bin/port-wp-save.sh system/etc/init/00-port-wpkeep.rc; do
  setfattr -n security.selinux -v u:object_r:system_file:s0 "$T/$f"
done
# (c) port-colormode.sh (odm, from tools/live/odm-services, see the vendor stage) now watches the settings dir with inotifyd instead of
# reading the whole logcat (live-verified 2026-11-03; sha in odm-services/SHA256SUMS).
# (BAKE-LIST B10) ColorOS VRR's OTI director in SurfaceFlinger drops to 60 Hz on idle regardless of DisplayManager's range; every
# switch shows one undimmed frame with DC dimming on this kernel. Default it off (Android's own idle timer still idles to 60 Hz
# when DC is off; DcBridge pins 90 Hz while DC is on). A value already persisted in /data wins over this default.
grep -qx 'persist.oplus.display.vrr=1' "$T/my_product/build.prop" || { echo "donor persist.oplus.display.vrr line changed"; exit 1; }
sed -i 's/^persist\.oplus\.display\.vrr=1$/persist.oplus.display.vrr=0/' "$T/my_product/build.prop"
# OMAPI for Wallet "Se Service Connection Error" (handoff-2026-10-17 §9b): the donor has no com.android.se, only the overlay
# SecureElementResTarget_Vendor. Use the LOS24 build (targetSdk 37 = this Android; it registers "secure_element" and, with the
# secure_element_vintf_enabled resource, android.se.omapi.ISecureElementService/default). The H.40 one is Android 12, binds by intent
# and needs the H.40 com.vendor.nfc library. It reaches the SIM1/SIM2 secure_element HALs of the LOS vendor; the eSE (stock
# android.hardware.secure_elementnq330 HAL) is shipped since 17d and needs the CONFIG_NFC_P73_ESE kernel + corrected eSE power GPIO (handoff §12).
# (17h+, live-verified 2026-10-30, BAKE-LIST B7) The LOS24 APK (78a219c9…) requests only INTERACT_ACROSS_USERS_FULL (signature: denied,
# LOS platform key) and crash-looped every ~20 s without a SIM (Terminal.sendStateChangedBroadcast -> sendBroadcastAsUser(CURRENT)).
# SecureElement-iau.apk = same APK + <uses-permission INTERACT_ACROSS_USERS> (signature|privileged; the app is PRIVILEGED), rebuilt with
# apktool 3.0.3, zipalign -p 4, original LOS signing block transplanted (same cert 852a750c, shared uid android.uid.se unchanged).
SE=$P/tools/live/odm-services/app/SecureElement-iau.apk
[ "$(sha256sum < $SE | cut -d' ' -f1)" = 25691543bdcbabbb6dfad199bf842e9d08bebd788ffba8f8b789d7d3c5a8e0e2 ] || { echo "SecureElement apk sha"; exit 1; }
[ ! -e "$T/system_ext/app/SecureElement" ] || { echo "donor already has SecureElement"; exit 1; }
install -d -m 0755 -o root -g root "$T/system_ext/app/SecureElement"
install -m 0644 -o root -g root "$SE" "$T/system_ext/app/SecureElement/SecureElement.apk"
setfattr -n security.selinux -v u:object_r:system_file:s0 "$T/system_ext/app/SecureElement" "$T/system_ext/app/SecureElement/SecureElement.apk"
# Volume panel: OnePlus 7 Pro volume keys are on the left; the PLK110 donor says right (SystemUI
# FeatureOption.isOplusVolumeKeyInRight reads this prop).
python3 -I - "$T/my_product/build.prop" <<'PY'
import sys
p = sys.argv[1]; d = open(p).read(); old = '\npersist.oplus.software.audio.right_volume_key=true\n'
assert d.count(old) == 1, 'right_volume_key line changed in donor'
open(p, 'r+').write(d.replace(old, '\npersist.oplus.software.audio.right_volume_key=false\n'))
PY
# Video codecs: ColorOS sets debug.stagefright.ccodec=1 ("Codec2 for audio, OMX for video"), which drops every vendor
# C2 codec except *.avc.*; the LOS vendor has no OMX (disabled on purpose), so HEVC/VP8/VP9 fell to the software
# decoders (10-bit HEVC fails -> fingerprint-enroll guide video hangs Settings). 4 = all components, normal ranks.
python3 -I - "$T/system/build.prop" <<'PY'
import sys
p = sys.argv[1]; d = open(p).read()
assert d.count('\ndebug.stagefright.ccodec=1\n') == 1, 'ccodec line changed in donor'
open(p, 'r+').write(d.replace('\ndebug.stagefright.ccodec=1\n', '\ndebug.stagefright.ccodec=4\n'))
PY
say "stage 11 done"
