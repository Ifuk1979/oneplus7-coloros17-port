#!/bin/bash
# Stage 10: system.img from the PLK110 .105 OTA (decision 2026-11-10: no AxisGSI), SMOKE SCOPE.
# Smoke scope = what is needed to answer "does the .105 chain boot on the LineageOS kernel/vendor": the assembled tree, dev props,
# adb key, the Oplus AIDL stubs, tethering APEX gates, wifi odm link, property-context and xperms CIL fixes, my_stock mount rc.
# Everything else in tools/live/BAKE-LIST.md is added by later stages (see fixes.tsv). Output: $WORK/tree (packed by stage 18)
set -euo pipefail
. "$HERE/config.env"; . "$HERE/lib/common.sh"
need_root
if [ -z "${REFORGE_NS:-}" ]; then export REFORGE_NS=1; exec unshare --mount --propagation private bash "$0" "$@"; fi
[ "$LOS" = baseline ] || die "stage 10 smoke scope supports LOS=baseline only"
CACHE="$WORK/cache"; M="$WORK/mnt10"; T="$WORK/tree"

# adb_keys: EMPTY unless ADB_PUB names a key (2026-11-20). The dev props below set ro.adb.secure=0, so adb needs no key; a baked
# builder key put the builder's user@host into every released image and authorised the builder's PC on all installs.
ADB_PUB="${ADB_PUB:-}"
for f in "$CACHE/my_stock-$CACHE_TAG.img" "$CACHE/product-$CACHE_TAG.img" "$CACHE/my_product-$CACHE_TAG.img" "$AVB_KEY"; do
  [ -s "$f" ] || die "missing $f (run stage 01 / check keys)"; done
rm -rf "$M"; mkdir -p "$M"/{s,se,pr,mp,mm,mr,eng,hey,car,big,los}
mnt() { mount -o ro,loop "$1" "$2"; }
mnt "$SRC_FULL_IMAGES/system.img" "$M/s"; mnt "$SRC_FULL_IMAGES/system_ext.img" "$M/se"
mnt "$CACHE/product-$CACHE_TAG.img" "$M/pr"; mnt "$CACHE/my_product-$CACHE_TAG.img" "$M/mp"
mnt "$SRC_FULL_IMAGES/my_manifest.img" "$M/mm"; mnt "$SRC_FULL_IMAGES/my_region.img" "$M/mr"
for p in eng:my_engineering hey:my_heytap car:my_carrier big:my_bigball; do mnt "$CACHE/${p#*:}-$CACHE_TAG.img" "$M/${p%%:*}"; done
# AutoPort bundles only the one file stage 10 needs from the LOS system image (SRC_LOS_TETHERING_CAPEX); default: mount the image.
if [ -z "${SRC_LOS_TETHERING_CAPEX:-}" ]; then mnt "$SRC_LOS_BASELINE/system.img" "$M/los"; fi

say "assembling the tree from the .105 OTA partitions"
grep -qx "ro.build.display.id.show=$DONOR_DISPLAY_EXACT" "$M/mm/build.prop" || die "donor my_manifest is not $DONOR_DISPLAY_EXACT"
rm -rf "$T"; cp -a "$M/s" "$T"
for p in se:system_ext pr:product mp:my_product mm:my_manifest mr:my_region eng:my_engineering hey:my_heytap car:my_carrier big:my_bigball; do
  d="$T/${p#*:}"; [ -d "$d" ] || die "no mount point $d in the OTA system root"
  cp -a "$M/${p%%:*}/." "$d/"
done
du -sm --apparent-size "$T" | sed 's/^/tree MB: /'

# ---- helpers ------------------------------------------------------------------------------------------------------
lab() { setfattr -n security.selinux -v "$1" "${@:2}"; }
subst() {  # subst FILE BRE REPLACEMENT : exactly one matching line; rewritten in place (keeps inode and SELinux label)
  local f=$1 n; n=$(grep -c -- "$2" "$f" || true); [ "$n" = 1 ] || die "$f: '$2' matched $n lines (donor changed?)"
  sed "s|$2|$3|" "$f" > "$f.new" && cat "$f.new" > "$f" && rm "$f.new"
}

# ---- identity (About phone): GM1910_<donor>(<tag>), see config.env RELEASE_NAME ---------------------------------------
MB="$T/my_manifest/build.prop"
subst "$MB" "^ro\.build\.display\.id\.show=${DONOR_DISPLAY_BRE}\$" "ro.build.display.id.show=GM1910_${DONOR_COLOROS}(${RELEASE_TAG})"
subst "$MB" "^ro\.product\.model=${DONOR_MODEL}\$" 'ro.product.model=GM1910'
# /data key compatibility (slot A smoke run 5, docs/research/slotA-smoke-2026-11-10): the existing metadata key blob was made when the
# device reported vendor patch 2022-12-05 and first_api_level 28 (LOS vendor values; the GSI init let the vendor's ro.* win over
# my_manifest). The .105 Oplus init loads my_manifest first, so A reported 2026-09-01 / 36: keymaster answered KEY_REQUIRES_UPGRADE (-62)
# and vold chose dm-default-key options format v2 (28 -> v1), so /data could not be mapped. Keep the old values.
subst "$MB" "^ro\.vendor\.build\.security_patch=${DONOR_VENDOR_PATCH}\$" 'ro.vendor.build.security_patch=2022-12-05'
subst "$MB" "^ro\.product\.first_api_level=${DONOR_FIRST_API}\$" 'ro.product.first_api_level=28'

# ---- Oplus game GPU control panel off. Slot A smoke run 6: GameManagerService.onBootPhase(1000) -> GameGpuControlPanel.onBootCompleted ->
# nativeSaveGpuControlPanelProfile blocks the display thread for >60 s, Watchdog kills system_server and sys.boot_completed is never set.
# The class skips itself ("Missing GameGpuControlPanel in feature node") when the node is absent from the feature config.
python3 -I - "$T/my_product/etc/extension" <<'PY'
import json, sys
# .105 listed the node in both files. 17.0.1.201 keeps it only in the dedicated panel file
# (sys_graphic_enhancement_config.json feature is just "colorx"). Remove it wherever it is.
removed = []
for fn in ("sys_graphic_enhancement_config.json", "sys_graphics_game_gpu_control_panel.json"):
    p = f"{sys.argv[1]}/{fn}"
    d = json.load(open(p, encoding="utf-8"))
    feat = d.get("feature")
    if not isinstance(feat, dict) or "GameGpuControlPanel" not in feat:
        print(f"{fn}: no GameGpuControlPanel node")
        continue
    del feat["GameGpuControlPanel"]
    with open(p, "r+", encoding="utf-8") as f:     # in place: keeps the SELinux label
        f.seek(0); f.write(json.dumps(d, indent=4, ensure_ascii=False)); f.truncate()
    removed.append(fn)
assert removed, "GameGpuControlPanel node not found in either feature config (donor changed?)"
print("GameGpuControlPanel node removed from " + ", ".join(removed))
PY

# ---- dev props: the OTA is a production build (ro.secure=1, ro.debuggable=0, ro.adb.secure=1) ------------------------------
SB="$T/system/build.prop"
subst "$SB" '^ro\.secure=1$' 'ro.secure=0'; subst "$SB" '^ro\.debuggable=0$' 'ro.debuggable=1'; subst "$SB" '^ro\.adb\.secure=1$' 'ro.adb.secure=0'
printf '\n# --- OnePlus7Port reforge (dev) ---\npersist.service.adb.enable=1\npersist.service.debuggable=1\npersist.sys.usb.config=adb\n# LineageOS sm8150 kernel has eBPF backported to 5.10 level\nro.bpf.kver_override=5.10.239\n' >> "$SB"
if [ -n "$ADB_PUB" ]; then install -m 0644 -o root -g root "$ADB_PUB" "$T/product/etc/security/adb_keys"
else install -m 0644 -o root -g root /dev/null "$T/product/etc/security/adb_keys"; fi
lab u:object_r:adb_keys_file:s0 "$T/product/etc/security/adb_keys"

# ---- my_stock lives on /data (slot A smoke uses its own file name; slot B's my_stock.img is never touched) -----------------
printf '%s\n' "# OnePlus7Port: my_stock lives on /data (reforge smoke)" "on post-fs-data" "    mkdir /data/port 0750 root root encryption=None" \
  "    mount erofs loop@/data/port/$MY_STOCK_DATA_IMG /my_stock ro" > "$T/system/etc/init/00-port-mystock.rc"
chmod 0644 "$T/system/etc/init/00-port-mystock.rc"; lab u:object_r:system_file:s0 "$T/system/etc/init/00-port-mystock.rc"

# ---- WiFi: LOS vendor links firmware/wlan/qca_cld/WCNSS_qcom_cfg.ini -> /odm/vendor/... (LOS: /odm -> /vendor/odm) ----------
[ ! -e "$T/odm/vendor" ] || die "odm/vendor already exists"
ln -s /vendor/odm/vendor "$T/odm/vendor"; lab u:object_r:vendor_file:s0 -h "$T/odm/vendor" 2>/dev/null || setfattr -h -n security.selinux -v u:object_r:vendor_file:s0 "$T/odm/vendor"
grep -qx libcamera_metadata.so "$T/system/etc/llndk.libraries.txt" || echo libcamera_metadata.so >> "$T/system/etc/llndk.libraries.txt"

# ---- property contexts: drop system-side prefixes that clash with the LOS vendor's (init trie build would LOG(FATAL)) --------
mkdir -p "$M/losv"; mnt "$SRC_LOS_BASELINE/vendor.img" "$M/losv"
python3 -I "$PROJECT/tools/drop-propctx-conflicts.py" "$T" "$M/losv"

# ---- xperms: strip logging-only auditallowx/dontauditx from the system-side CIL (kept from the GSI build; may be unnecessary on stock init) ----
for f in "$T/system/etc/selinux/plat_sepolicy.cil" "$T/system_ext/etc/selinux/system_ext_sepolicy.cil" "$T/product/etc/selinux/product_sepolicy.cil"; do
  [ -f "$f" ] || continue
  grep -vE '^\((auditallowx|dontauditx) ' "$f" > "$f.new" || true
  say "$(basename "$f"): removed $(( $(wc -l < "$f") - $(wc -l < "$f.new") )) auditallowx/dontauditx"
  cat "$f.new" > "$f" && rm "$f.new"
done

# ---- duplicate genfscon: secilc fails ("Problems processing genfscon rules") when system and vendor label the same fs path.
# Found by the first smoke boot (docs/research/slotA-smoke-2026-11-10): .105 system_ext labels proc "/shell-temp" horae_proc, the LOS
# vendor labels it proc_horae. Keep the vendor's label (the vendor HALs/kernel are its consumers), drop the system-side duplicate.
GKEYS="$WORK/vendor-genfs.keys"
cat "$M/losv/etc/selinux/vendor_sepolicy.cil" "$M/losv/etc/selinux/plat_pub_versioned.cil" | \
  awk '/^\(genfscon / { if (match($0, /^\(genfscon [a-z0-9_]+ "[^"]*"/)) print substr($0, 11, RLENGTH-10) }' | sort -u > "$GKEYS"
# The .105 init switches to the *_debug.cil set when ro.debuggable=1 ("Using userdebug system sepolicy"), so both sets are fixed.
for f in "$T/system/etc/selinux/plat_sepolicy.cil" "$T/system_ext/etc/selinux/system_ext_sepolicy.cil" "$T/product/etc/selinux/product_sepolicy.cil" \
         "$T/system_ext/etc/selinux/plat_sepolicy_debug.cil" "$T/system_ext/etc/selinux/system_ext_sepolicy_debug.cil" "$T/product/etc/selinux/product_sepolicy_debug.cil"; do
  [ -f "$f" ] || continue
  awk -v kf="$GKEYS" 'BEGIN { while ((getline k < kf) > 0) bad[k]=1 }
    /^\(genfscon / && match($0, /^\(genfscon [a-z0-9_]+ "[^"]*"/) && (substr($0, 11, RLENGTH-10) in bad) { print "dropped duplicate genfscon: " $0 > "/dev/stderr"; next }
    { print }' "$f" > "$f.new"
  cat "$f.new" > "$f" && rm "$f.new"
done

# ---- tethering APEX kernel gates (build-port-b.sh lines 784-827) ---------------------------------------------------------
KV_FILES="bin/netbpfload lib/libframework-connectivity-jni.so lib64/libframework-connectivity-jni.so
  lib64/libandroid_net_connectivity_com_android_net_module_util_jni.so lib64/libnetd_resolv.so
  lib64/libnetd_updatable.so lib64/libnetworkstats.so lib64/libservice-connectivity.so"
W2="$WORK/losapex"; rm -rf "$W2"; mkdir -p "$W2/los" "$W2/cos"
unzip -p "${SRC_LOS_TETHERING_CAPEX:-$M/los/system/apex/com.android.tethering.capex}" original_apex > "$W2/los.apex"
unzip -p "$W2/los.apex" apex_payload.img > "$W2/los.img"
unzip -p "$T/system/apex/com.android.tethering.apex" apex_payload.img > "$W2/cos.img"
mount -o ro,loop "$W2/los.img" "$W2/los"; mount -o ro,loop "$W2/cos.img" "$W2/cos"
D="$T/system/etc/port-los-tether"; RC="$T/system/etc/init/00-port-netbpfload.rc"
printf '%s\n' "# OnePlus7Port: LineageOS (ro.bpf.kver_override-aware) builds over ColorOS's tethering APEX." "on load-bpf-programs" > "$RC"
labels=""
for rel in $KV_FILES; do
  nm -D --defined-only "$W2/cos/$rel" | awk '{print $3}' | sort > "$W2/kv-a"
  nm -D --defined-only "$W2/los/$rel" | awk '{print $3}' | sort > "$W2/kv-b"
  cmp -s "$W2/kv-a" "$W2/kv-b" || die "tethering export mismatch: $rel (the .105 APEX changed)"
  l=$(getfattr -n security.selinux --only-values "$W2/cos/$rel"); mode=$(stat -c %a "$W2/cos/$rel")
  install -D -m "$mode" -o root -g 2000 "$W2/los/$rel" "$D/$rel"; lab "$l" "$D/$rel"
  echo "    mount none /system/etc/port-los-tether/$rel /apex/com.android.tethering/$rel bind" >> "$RC"
  labels="$labels ${l#u:object_r:}"
done
cp -a "$W2/los/etc/bpf" "$D/bpf"
echo "    mount none /system/etc/port-los-tether/bpf /apex/com.android.tethering/etc/bpf bind" >> "$RC"
umount "$W2/los" "$W2/cos"
for dir in "$D" "$D/bin" "$D/lib" "$D/lib64"; do lab u:object_r:system_file:s0 "$dir"; done
chmod 0644 "$RC"; lab u:object_r:system_file:s0 "$RC"
PL="$T/system/etc/selinux/plat_sepolicy.cil"
for t in $(echo $labels | tr ' ' '\n' | sed 's/:s0$//' | sort -u); do
  grep -q "^(allow init $t (file (mounton)))" "$PL" || printf '(allow init %s (file (mounton)))\n' "$t" >> "$PL"
done
grep -q '^(allow init system_file (dir (mounton)))' "$PL" || printf '(allow init system_file (dir (mounton)))\n' >> "$PL"

say "stage 10 done (tree assembled; fix stages 11-17 and pack stage 18 follow)"
