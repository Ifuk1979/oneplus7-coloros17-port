"""bootcmp.py <a.img> <b.img> - exit 0 when two Android boot images (header v0-v2, lz4 ramdisk) have the same content:
same kernel, dtb, second, header cmdline and sizes, and a ramdisk with the same files (name, mode, uid/gid, symlink target, data).
cpio mtimes/inodes and the header id are ignored (they change on every rebuild). Prints the first differences otherwise.
"""
import struct
import subprocess
import sys


def sections(path):
    d = open(path, "rb").read()
    if d[:8] != b"ANDROID!":
        sys.exit(f"{path}: not an Android boot image")
    ks, _, rs, _, ss, _, _, pg, ver = struct.unpack("<IIIIIIIII", d[8:44])
    if ver > 2:
        sys.exit(f"{path}: header v{ver} not supported")
    rd_sz = struct.unpack("<I", d[1632:1636])[0] if ver >= 1 else 0
    dtb_sz = struct.unpack("<I", d[1648:1652])[0] if ver >= 2 else 0
    cmd = d[64:64 + 512].split(b"\0")[0] + d[608:608 + 1024].split(b"\0")[0]
    off, sec = pg, {}
    for name, size in (("kernel", ks), ("ramdisk", rs), ("second", ss), ("recovery_dtbo", rd_sz), ("dtb", dtb_sz)):
        sec[name] = d[off:off + size]
        off += ((size + pg - 1) // pg) * pg
    sec["header"] = struct.pack("<II", pg, ver) + d[44:48]   # page size, header version, os_version
    sec["cmdline"] = cmd
    return sec


def cpio_entries(raw):
    data = subprocess.run(["lz4", "-dc"], input=raw, capture_output=True, check=True).stdout
    out, i = {}, 0
    while True:
        if data[i:i + 6] != b"070701":
            sys.exit("ramdisk is not a newc cpio")
        f = [int(data[i + 6 + 8 * k:i + 14 + 8 * k], 16) for k in range(13)]
        mode, uid, gid, fsize, nsize = f[1], f[2], f[3], f[6], f[11]
        name = data[i + 110:i + 110 + nsize - 1].decode()
        j = (i + 110 + nsize + 3) & ~3
        body = data[j:j + fsize]
        i = (j + fsize + 3) & ~3
        if name == "TRAILER!!!":
            return out
        out[name] = (mode, uid, gid, body)


def main(a, b):
    sa, sb = sections(a), sections(b)
    diffs = [k for k in ("header", "cmdline", "kernel", "second", "recovery_dtbo", "dtb") if sa[k] != sb[k]]
    ea, eb = cpio_entries(sa["ramdisk"]), cpio_entries(sb["ramdisk"])
    for n in sorted(set(ea) | set(eb)):
        if ea.get(n) != eb.get(n):
            diffs.append(f"ramdisk:{n}")
    if diffs:
        print("boot images differ: " + ", ".join(diffs[:20]) + (" ..." if len(diffs) > 20 else ""))
        return 1
    print(f"boot images have the same content ({len(ea)} ramdisk entries)")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1], sys.argv[2]))
