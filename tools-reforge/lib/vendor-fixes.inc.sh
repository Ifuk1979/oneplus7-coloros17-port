# tools-reforge/lib/vendor-fixes.inc.sh - vendor-side BAKE-LIST fixes, sourced by stage 20 while the LOS vendor is mounted rw at $V.
# Ported from tools/build-port-b.sh (old line ranges in the block comments) and tools/build-17k-r2-vendor.sh (B26).
P="$PROJECT"; CD="$P/tools/live/camera-donor17"
# sidekey config (old 900-907)
# Action button position for the gesture app (OplusGestureUI default: /odm/etc/devices_config/sidekey_config.xml, /odm/etc
# -> /vendor/odm/etc): the slider sits on the right edge at 620..790 of a 2376-px reference height (OnePlus 15: left).
ODM_LABEL=$(getfattr -n security.selinux --only-values $V/odm/etc)
install -D -m 0644 -o root -g root $P/tools/live/sidekey/sidekey_config.xml $V/odm/etc/devices_config/sidekey_config.xml
chmod 0755 $V/odm/etc/devices_config
for f in $V/odm/etc/devices_config $V/odm/etc/devices_config/sidekey_config.xml; do
  setfattr -n security.selinux -v "$ODM_LABEL" "$f"
done
# camcorder profiles, AAC via Codec2, vidhance off (old 908-922)
# Camcorder profiles: libmedia reads the plural ro.media.xml_variant.profiles property. The singular spelling
# used through build 15 is ignored; without the variant H.40 video reports "camera 0 quality 6 not found".
# With _vendor loaded at framework startup, the app advances past profile selection (later HAL crash unresolved).
sed -i '/^ro.media.xml_variant.profile=/d; /^ro.media.xml_variant.profiles=/d' $V/build.prop
printf '\n# OnePlus7Port: camcorder profiles\nro.media.xml_variant.profiles=_vendor\n' >> $V/build.prop
# OpenCamera AAC: this port uses the LOS24 Codec2-only media stack (OMX service disabled). ColorOS defaults
# vendor.audio.hw.aac.encoder=true and its Oplus recorder requests the missing OMX.qcom AAC component. The live
# build 15 A/B test passed with this false, routing AAC creation through c2.android.aac.encoder.
sed -i '/^vendor\.audio\.hw\.aac\.encoder=/d' $V/build.prop
printf '\n# OnePlus7Port: AAC through Codec2 on the LOS24 base\nvendor.audio.hw.aac.encoder=false\n' >> $V/build.prop
# H.40 stock camera video: the EIS node (com.oneplus.node.eis.so -> libvidhance) SIGSEGVs in the camera provider as soon
# as recording starts (EisNode enableEIS 1; bad ANativeWindowBuffer incRef inside eglCreateImageKHR). Live build 15 test:
# vendor.vidhance.enabled=0 gives valid 1080p HEVC+AAC recordings and no provider crash. Cost: no vidhance EIS.
sed -i '/^vendor\.vidhance\.enabled=/d' $V/build.prop
printf '\n# OnePlus7Port: vidhance EIS crashes the H.40 camera video path\nvendor.vidhance.enabled=0\n' >> $V/build.prop
# proximity type 8 via IR (old 937-949), panel feature 217 (950-953), offline-charging qboot path (954-959)
# Proximity type 8 (handoff 2026-10-18, tools/live/sensors-re/README.md): the stock sensors HAL picks its proximity source per screen
# state but never learns the state on this kernel, so it falls through to the dead Elliptic ultrasound path and type 8 stays silent.
# sensors.ssc.so.aud (tools/live/sensors-re/make-aud-patch.py) = stock + (1) the audio-state node /dev/audio_ultrasound redirected to the
# FIFO /data/vendor/aus and (2) Proximity::GetUseProximityType reading that audio state instead of the dead screen-state field.
# port_prox_feeder (system rc 00-port-proxfeed.rc) drives it: display off -> IR, on/AOD -> no IR (no visible emitter blink).
SS=$V/lib64/sensors.ssc.so
SP=$P/tools/live/sensors-re
sha256sum -c --quiet <<SUMS || exit 1
f52b772de6f438124c9075fb7fcdf5da7dfcaa15551fd6c1a6f9240375b7b7d6  $SS
f52b772de6f438124c9075fb7fcdf5da7dfcaa15551fd6c1a6f9240375b7b7d6  $SP/sensors.ssc.so
3bc45a33f1ebc810814237f2fd09fd2d37bad7535de44dde86a446c91eaeb226  $SP/sensors.ssc.so.aud
SUMS
cat "$SP/sensors.ssc.so.aud" > "$SS"     # in place: keeps owner, mode and label
# Panel feature 217 (smooth transition bits: 2 = supported, 1 = doze without panel off), read by port.OplusStubs PanelBinder from
# persist.vendor.port.dpf.<id>. Kept on at the user's request (tools/live/BAKE-LIST.md §2); the lock-to-AOD fade is NOT fixed by it.
sed -i '/^persist\.vendor\.port\.dpf\.217=/d' $V/build.prop
printf '\n# OnePlus7Port: display panel feature 217 for ColorOS smooth transition (stub reads this)\npersist.vendor.port.dpf.217=3\n' >> $V/build.prop
# (build 17h) Offline charging (BAKE-LIST B5, user-verified live 2026-10-29): quickboot's Config::getResPath() defaults to
# system_ext/etc/media/quickboot/op818/ for prjname 18821; the donor has the images flat in that folder, so the first image load
# failed, quickboot SIGSEGV'd and its handler powered off (dead battery + cable -> ~40 s loop, static logo, no charging).
[ -f "$T/system_ext/etc/media/quickboot/boot_charger_01.png" ] || { echo "donor quickboot images moved"; exit 1; }
sed -i '/^ro\.qboot\.res\.path=/d' $V/build.prop
printf '\n# OnePlus7Port: offline-charging UI images (quickboot defaults to the missing op818/ folder for prjname 18821, crashes and powers off)\nro.qboot.res.path=/system_ext/etc/media/quickboot/\n' >> $V/build.prop
# camera provider SIGPIPE rc (old 960-971)
# (BAKE-LIST B14, live-tested 2026-11-03) Camera provider SIGPIPE: with the donor camera app a provider thread sometimes writes to
# one of the provider's own pipes after its read end closed; SIGPIPE's default action killed the whole provider (no tombstone)
# and the app with it, at capture or at open. Start it with SIGPIPE ignored (kept across exec), same domain via seclabel.
CR=$V/etc/init/android.hardware.camera.provider@2.4-service_64.rc
[ "$(sha256sum < $CR | cut -d' ' -f1)" = a2b7392048e2bfd145955948ae6e6a4a29dccb99a9809e6cd1c2aa5ffffe9aef ] || { echo "LOS camera provider rc changed"; exit 1; }
CRN=$P/tools/live/camera-sigpipe/android.hardware.camera.provider@2.4-service_64.rc
[ "$(sha256sum < $CRN | cut -d' ' -f1)" = dc250d3eaeac75cef9e6048582da08eac4ce456b655fa145737d86bf0ee729d0 ] || { echo "camera provider rc sha"; exit 1; }
cat "$CRN" > "$CR"
# (BAKE-LIST C1) 01-port-camera.rc bind-mounts the donor odm/etc/camera over this dir: it must keep the LOS files it hides.
for f in $(ls -A $V/odm/etc/camera); do
  cmp -s "$V/odm/etc/camera/$f" "$CD/bake/odm-camera/$f" || { echo "vendor odm/etc/camera/$f not in the camera bake copy"; exit 1; }
done
# DC flicker: optimize_refresh off (old 972-977), B16 props block (978-989)
# (BAKE-LIST B10, user-verified 2026-11-03) DC-dimming flicker: the LOS kernel skips the dim layer on the frame of every refresh-rate
# switch ("do not config dimlayer at the fps switch"), so with DC on (backlight held at 260) each 60<->90 Hz switch flashed an undimmed
# frame. One of the three switchers is Qualcomm's display-HAL idle drop (enable_optimize_refresh); the others are ColorOS VRR
# (persist.oplus.display.vrr, my_product) and Android's idle timer, which DcBridge pins out while DC is on.
grep -qx 'vendor.display.enable_optimize_refresh=1' $V/build.prop || { echo "LOS vendor enable_optimize_refresh line changed"; exit 1; }
sed -i 's/^vendor\.display\.enable_optimize_refresh=1$/vendor.display.enable_optimize_refresh=0/' $V/build.prop
# (BAKE-LIST B16, live-verified after reboot 2026-11-03 on vendor_b) H.40 / ColorOS props, REPORT.md
# (tools/live/prop-compare) section 3 items 2-9: density 600 + H.40 screenzoom, H.40 dalvik heap, confidential/allnet, mag_filter,
# OnePlus default sounds, keystore_desede + cuptsm, LTE RSRP thresholds + no data roaming, media_vol_default 15 + rc.size.
# vendor/build.prop because LOS vendor loads after my_* and wins; product/etc and odm/etc do not set any of these keys (preflight).
# No camera props (ro.camera.notify_nfc left out on purpose). Brightness tables (item 10) are NOT part of this.
B16=$P/tools/live/prop-compare/b16/vendor-build.prop.b16-block
[ "$(sha256sum < $B16 | cut -d' ' -f1)" = 958e8236cb146723c1b2a4ab5666b37f601f1e509175939d2ccd8839956d3dd6 ] || { echo "B16 prop block sha"; exit 1; }
grep -q '^# OnePlus7Port B16' $V/build.prop && { echo "B16 block already in vendor build.prop"; exit 1; }
for k in $(grep -v '^#' "$B16" | grep '=' | cut -d= -f1); do
  sed -i "/^$(printf '%s' "$k" | sed 's/\./\\./g')=/d" $V/build.prop
done
cat "$B16" >> $V/build.prop
# odm services: charger/cryptoeng HALs, netguard B22, slider B24/B25b, chglimit/bmslevel B20+B21, offlinecam B27, colormode ... (old 990-1003)
# Oplus odm services missing from the LOS24 odm (stock H.40; handoff-2026-10-17 §9b, build 17b): charger HAL (Battery Health,
# "getIChargerService fail") and cryptoeng HAL (Find My Device RPMB channel). The stock binaries need two symbols the LOS24 libbase /
# libjsoncpp export differently; their rc LD_PRELOADs libportcompat.so (tools/live/odm-services/compat). Build 17 without it: CANNOT LINK.
# Everything is listed in tools/live/odm-services/install.list; the closure of NEEDED libraries was resolved against this vendor
# + the LLNDK list (only libevent had to come from H.40 system/lib64); preflight re-runs that check on the built images.
OS=$P/tools/live/odm-services
(cd "$OS" && sha256sum -c --quiet SHA256SUMS) || { echo "odm-services sources changed"; exit 1; }
while read -r src dst mode label; do
  case "$src" in ''|\#*) continue;; esac
  [ ! -e "$V/odm/$dst" ] || { echo "LOS odm already has $dst"; exit 1; }
  install -D -m "$mode" -o root -g root "$OS/$src" "$V/odm/$dst"
  setfattr -n security.selinux -v "u:object_r:$label:s0" "$V/odm/$dst"
done < "$OS/install.list"
grep -q 'hal_secure_element_default_exec' $V/etc/selinux/vendor_sepolicy.cil || { echo "no hal_secure_element_default_exec type in vendor policy"; exit 1; }
# B26: audio policy, primary input maxOpenCount 2 -> 1 (tools/build-17k-r2-vendor.sh); written INTO the existing inodes so label/mode stay
AP="$P/tools/live/audio-policy-1input"
for f in audio_policy_configuration audio_policy_configuration_a2dp_offload_disabled; do
  t="$V/etc/$f.xml"
  cmp -s "$AP/$f.orig.xml" "$t" || { echo "$f.xml in the vendor is not the .orig we edited"; exit 1; }
  [ "$(grep -c 'name="primary input" role="sink" maxOpenCount="2"' "$t")" = 1 ] || { echo "primary input attribute count in $f"; exit 1; }
  cat "$AP/$f.xml" > "$t"
  [ "$(grep -c 'name="primary input" role="sink" maxOpenCount="1" maxActiveCount="2"' "$t")" = 1 ] && cmp -s "$AP/$f.xml" "$t" || { echo "edit failed in $f"; exit 1; }
done
