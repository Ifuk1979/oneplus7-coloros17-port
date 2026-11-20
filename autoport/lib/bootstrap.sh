# autoport/lib/bootstrap.sh - check the host and install the toolchain the reforge stages need. Sourced by autoport.sh.
# Host: WSL2 or Linux x86_64, root, loop devices, mount namespaces, an ext4 work directory (security.* xattrs), enough space.
# Toolchain: Ubuntu/Debian apt packages + secilc 3.11 built statically from the bundled SELinux sources (Ubuntu 24.04 ships 3.5,
# which cannot compile the Android 17 policy).

APT_PKGS="python3 default-jre-headless libsmali-java apktool zipalign erofs-utils e2fsprogs lz4 cpio attr zip unzip xz-utils
  util-linux file binutils patch openssl rsync pigz build-essential flex bison pkg-config"
# tool -> package, checked after apt (a package rename on another distro shows up here, not deep inside a stage)
NEED_TOOLS="python3 java smali baksmali apktool zipalign mkfs.erofs dump.erofs fsck.erofs e2fsck mke2fs resize2fs lz4 cpio
  getfattr setfattr zip unzip xz unshare losetup file strings patch openssl sha256sum truncate"
SELINUX_VER=3.11
LIBSEPOL_SHA=79f3d2c88f44b7eb5cf54d9792e03232297e17f97a179163f2750099a00f164d
SECILC_SHA=1fb7de005d35ae0ac6ff8f8fc955d08a15b5c1a67e961b97ef987576af0db11a
SELINUX_URL=https://github.com/SELinuxProject/selinux/releases/download/$SELINUX_VER
MIN_FREE_GB=${MIN_FREE_GB:-80}

host_check() {
  [ "$(id -u)" = 0 ] || die "run as root (WSL: wsl -u root, Linux: sudo)"
  [ "$(uname -m)" = x86_64 ] || die "x86_64 Linux needed (this is $(uname -m))"
  if grep -qi microsoft /proc/version 2>/dev/null; then
    case "$(uname -r)" in *WSL2*|*microsoft-standard*) say "host: WSL2 ($(uname -r))" ;;
      *) die "WSL1 has no loop devices: convert the distro with 'wsl --set-version <distro> 2'" ;; esac
  else say "host: Linux $(uname -r)"; fi
  [ -r /etc/os-release ] && . /etc/os-release && say "distro: ${PRETTY_NAME:-unknown}"
  have apt-get || die "apt-get not found: AutoPort installs its tools with apt (Ubuntu 22.04/24.04 or Debian 12+). Install the packages in lib/bootstrap.sh by hand and rerun with --no-apt"
  [ -n "${VERSION_ID:-}" ] && [ "${ID:-}" = ubuntu ] && [ "${VERSION_ID%%.*}" -lt 22 ] && die "Ubuntu ${VERSION_ID} is too old (22.04 or newer)"
  return 0
}

work_check() { # dir
  local d=$1 t f
  case "$d" in /mnt/[a-z]/*|/mnt/[a-z]) die "work directory $d is on a Windows drive: use a Linux path (default /root/op7-autoport)" ;; esac
  mkdir -p "$d"; t=$(fs_type "$d")
  [ "$t" = ext4 ] || [ "$t" = xfs ] || [ "$t" = btrfs ] || die "work directory $d is on '$t': ext4 (or xfs/btrfs) is needed for SELinux labels"
  f="$d/.xattr-test"; : > "$f"
  setfattr -n security.selinux -v u:object_r:system_file:s0 "$f" 2>/dev/null || { rm -f "$f"; die "cannot set security.selinux xattrs in $d"; }
  rm -f "$f"
  local g; g=$(free_gb "$d"); say "free in $d: ${g} GB (need $MIN_FREE_GB)"
  [ "$g" -ge "$MIN_FREE_GB" ] || die "not enough space in $d (${g} GB free, $MIN_FREE_GB GB needed: donor images, caches, trees and the release zip)"
}

loop_check() {
  have losetup || apt_install util-linux
  losetup -f >/dev/null 2>&1 || modprobe loop 2>/dev/null || true
  losetup -f >/dev/null 2>&1 || die "no free loop device (losetup -f failed)"
  unshare --mount --propagation private true 2>/dev/null || die "unshare --mount does not work here (need a root shell, not a container without CAP_SYS_ADMIN)"
}

apt_install() {
  export DEBIAN_FRONTEND=noninteractive
  say "apt: installing $*"
  apt-get update -qq || die "apt-get update failed (network?)"
  # shellcheck disable=SC2086
  apt-get install -y -qq --no-install-recommends "$@" >/dev/null || die "apt-get install failed for: $*"
}

toolchain() { # tools dir ; sets PATH
  local td=$1 missing="" p
  if [ "${NO_APT:-0}" != 1 ]; then
    for p in $APT_PKGS; do dpkg -s "$p" >/dev/null 2>&1 || missing="$missing $p"; done
    # shellcheck disable=SC2086
    [ -z "$missing" ] && say "apt packages: all present" || apt_install $missing
  fi
  build_secilc "$td"
  export PATH="$td/bin:$PATH"
  local t bad=""
  for t in $NEED_TOOLS secilc; do have "$t" || bad="$bad $t"; done
  [ -z "$bad" ] || die "tools still missing after setup:$bad"
  java -version 2>&1 | head -1 | sed 's/^/  java: /'
  say "toolchain ready (secilc $SELINUX_VER in $td/bin)"
}

build_secilc() { # tools dir
  local td=$1 src="$PORT_ROOT/autoport/src" b="$td/build" s
  if [ -x "$td/bin/secilc" ] && [ -f "$td/bin/secilc.version" ] && [ "$(cat "$td/bin/secilc.version")" = "$SELINUX_VER" ]; then return 0; fi
  mkdir -p "$src" "$td/bin"; rm -rf "$b"; mkdir -p "$b"
  for n in libsepol:$LIBSEPOL_SHA secilc:$SECILC_SHA; do
    f="$src/${n%%:*}-$SELINUX_VER.tar.gz"
    if [ ! -f "$f" ]; then say "downloading ${f##*/}"; have curl || apt_install curl ca-certificates
      curl -fsSL -o "$f.part" "$SELINUX_URL/${f##*/}" || die "download of ${f##*/} failed"; mv "$f.part" "$f"; fi
    sha256_is "$f" "${n#*:}" || die "${f##*/} checksum mismatch (expected ${n#*:})"
    tar -xzf "$f" -C "$b"
  done
  say "building secilc $SELINUX_VER (static)"
  s="$b/stage"
  make -s -C "$b/libsepol-$SELINUX_VER" -j"$(nproc)" DESTDIR="$s" PREFIX=/usr install > "$b/libsepol.log" 2>&1 \
    || { tail -20 "$b/libsepol.log"; die "libsepol build failed ($b/libsepol.log)"; }
  make -C "$b/secilc-$SELINUX_VER" secilc CPPFLAGS="-I$s/usr/include" LDFLAGS="-static -L$s/usr/lib" > "$b/secilc.log" 2>&1 \
    || { tail -20 "$b/secilc.log"; die "secilc build failed ($b/secilc.log)"; }
  install -m 0755 "$b/secilc-$SELINUX_VER/secilc" "$td/bin/secilc"
  echo "$SELINUX_VER" > "$td/bin/secilc.version"
  rm -rf "$b"
}
