#!/bin/bash
# Stage 35 (debug only, not part of a release): the smoke boot.img/vendor.img with the kmsg logger as /init and a permissive
# `kernel`/`logpersist` so a failed boot leaves /metadata/port-kmsg.txt (readable from slot B). Same method as tools/build-debug-b.sh.
# Output: $OUT/smoke-debug/{boot.img,vendor.img}. system.img/dtbo/vbmeta are unchanged (flash only boot_a + vendor_a).
set -euo pipefail
. "$HERE/config.env"; . "$HERE/lib/common.sh"
need_root
if [ -z "${REFORGE_NS:-}" ]; then export REFORGE_NS=1; exec unshare --mount --propagation private bash "$0" "$@"; fi
SM="$OUT/smoke"; DB="$OUT/smoke-debug"; W="$WORK/debug"
for f in boot vendor; do [ -s "$SM/$f.img" ] || die "run stages 10-30 first ($SM/$f.img)"; done
rm -rf "$W"; mkdir -p "$W/rd" "$DB"
have_tool aarch64-linux-gnu-gcc || die "aarch64-linux-gnu-gcc missing in WSL"
python3 -I "$PROJECT/tools/bootimg_v2.py" unpack "$SM/boot.img" "$W"
lz4 -dc "$W/ramdisk" > "$W/ramdisk.cpio"
(cd "$W/rd" && cpio -idm --quiet < ../ramdisk.cpio)
[ -L "$W/rd/init" ] || die "expected /init symlink in the ramdisk"
rm "$W/rd/init"
aarch64-linux-gnu-gcc -static -O2 -Wall -o "$W/rd/init" "$PROJECT/tools/port-logger.c"
chmod 0750 "$W/rd/init"
(cd "$W/rd" && find . | LC_ALL=C sort | cpio -o -H newc --quiet -R 0:0) > "$W/ramdisk.new.cpio"
lz4 -l -12 -f -q "$W/ramdisk.new.cpio" "$W/ramdisk.new"
python3 -I "$PROJECT/tools/bootimg_v2.py" repack "$SM/boot.img" "$W/ramdisk.new" "$DB/boot.img"
python3 -I "$PROJECT/tools/bootimg_v2.py" cmdline "$DB/boot.img" "$DB/boot.img" printk.devkmsg=on

cp "$SM/vendor.img" "$W/vendor.img"; mkdir -p "$W/v"; mount -o loop "$W/vendor.img" "$W/v"
F="$W/v/etc/selinux/vendor_sepolicy.cil"
grep -q '^(typepermissive kernel)' "$F" || printf '(typepermissive kernel)\n' >> "$F"
grep -q '^(typepermissive logpersist)' "$F" || printf '(typepermissive logpersist)\n' >> "$F"
cat > "$W/v/etc/init/port-logcat.rc" <<'EOF'
# DEBUG ONLY (OnePlus7Port): persist logcat of every boot to /metadata/port-logcat.txt (rotated to .prev).
service port_logcat /system/bin/logcat -b all -v threadtime -f /metadata/port-logcat.txt -r 8192 -n 1
    user root
    group log
    seclabel u:r:logpersist:s0
    oneshot
    disabled

on post-fs
    rm /metadata/port-logcat.txt.1
    start port_logcat
EOF
cat > "$W/v/etc/init/port-props.rc" <<'EOF'
# DEBUG ONLY (OnePlus7Port): dump every property at post-fs (before /data) and again at post-fs-data, so slot A can be diffed against slot B.
service port_props_a /system/bin/sh -c "/system/bin/getprop > /metadata/port-props-postfs.txt"
    user root
    seclabel u:r:su:s0
    oneshot
    disabled

service port_props_b /system/bin/sh -c "sleep 3; /system/bin/getprop > /metadata/port-props-postfsdata.txt"
    user root
    seclabel u:r:su:s0
    oneshot
    disabled

on post-fs
    start port_props_a

on post-fs-data
    start port_props_b
EOF
chmod 0644 "$W/v/etc/init/port-props.rc"; setfattr -n security.selinux -v u:object_r:vendor_configs_file:s0 "$W/v/etc/init/port-props.rc"
chmod 0644 "$W/v/etc/init/port-logcat.rc"; setfattr -n security.selinux -v u:object_r:vendor_configs_file:s0 "$W/v/etc/init/port-logcat.rc"
sync; umount "$W/v"; e2fsck -fn "$W/vendor.img" > /dev/null && say "vendor fsck clean"
cp "$W/vendor.img" "$DB/vendor.img"
(cd "$DB" && sha256sum boot.img vendor.img | tee SHA256SUMS)
say "stage 35 done"
