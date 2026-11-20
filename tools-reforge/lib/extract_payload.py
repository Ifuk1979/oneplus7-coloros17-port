#!/usr/bin/env python3
"""Extract partitions from an Android OTA zip (payload.bin) using only the standard library.

Usage:
  extract_payload.py list <ota.zip>
  extract_payload.py extract <ota.zip> <partition> <out.img>

Handles the operation types found in full OTAs (REPLACE, REPLACE_BZ, REPLACE_XZ, ZERO).
Derived from the extractor measured in docs/research/2026-11-07-scratch-build-audit.md (4.7 GB my_stock in ~3 min).
Not done yet: verifying each operation's data_sha256_hash and the partition's new_partition_info.hash.
"""
import sys, struct, zipfile, bz2, lzma


def rv(b, p):
    r = s = 0
    while True:
        c = b[p]; p += 1
        r |= (c & 0x7f) << s; s += 7
        if not c & 0x80:
            return r, p


def fields(b):
    p = 0
    while p < len(b):
        k, p = rv(b, p)
        fn, wt = k >> 3, k & 7
        if wt == 0:
            v, p = rv(b, p)
        elif wt == 2:
            l, p = rv(b, p); v = b[p:p + l]; p += l
        elif wt == 1:
            v = b[p:p + 8]; p += 8
        elif wt == 5:
            v = b[p:p + 4]; p += 4
        else:
            raise SystemExit("unsupported wire type %d" % wt)
        yield fn, v


def open_payload(zipp):
    z = zipfile.ZipFile(zipp)
    info = z.getinfo('payload.bin')
    raw = open(zipp, 'rb')
    raw.seek(info.header_offset)
    lh = raw.read(30)
    n, e = struct.unpack('<HH', lh[26:30])
    base = info.header_offset + 30 + n + e
    raw.seek(base)
    magic, ver, msz, sigsz = struct.unpack('>4sQQI', raw.read(24))
    if magic != b'CrAU':
        raise SystemExit("not a payload.bin (magic %r)" % magic)
    m = raw.read(msz)
    data0 = base + 24 + msz + sigsz
    bs = next((v for f, v in fields(m) if f == 3), 4096)
    return raw, m, data0, bs


def partitions(m):
    for fn, v in fields(m):
        if fn != 13:
            continue
        name, size, ops = None, 0, []
        for f2, v2 in fields(v):
            if f2 == 1:
                name = v2.decode()
            if f2 == 7:
                size = next((v3 for f3, v3 in fields(v2) if f3 == 1), 0)
            if f2 == 8:
                op = {'dst': [], 'off': 0, 'len': 0, 'type': 0}
                for f3, v3 in fields(v2):
                    if f3 == 1: op['type'] = v3
                    elif f3 == 2: op['off'] = v3
                    elif f3 == 3: op['len'] = v3
                    elif f3 == 6:
                        s = nb = 0
                        for f4, v4 in fields(v3):
                            if f4 == 1: s = v4
                            if f4 == 2: nb = v4
                        op['dst'].append((s, nb))
                ops.append(op)
        yield name, size, ops


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    cmd, zipp = sys.argv[1], sys.argv[2]
    raw, m, data0, bs = open_payload(zipp)
    if cmd == 'list':
        for name, size, ops in partitions(m):
            print("%-20s %14d" % (name, size))
        return
    if cmd != 'extract' or len(sys.argv) != 5:
        raise SystemExit(__doc__)
    want, outp = sys.argv[3], sys.argv[4]
    for name, size, ops in partitions(m):
        if name != want:
            continue
        with open(outp, 'wb') as out:
            out.truncate(size)
            for op in ops:
                if op['type'] == 6:      # ZERO
                    continue
                raw.seek(data0 + op['off'])
                d = raw.read(op['len'])
                if op['type'] == 8:      # REPLACE_XZ
                    d = lzma.decompress(d)
                elif op['type'] == 1:    # REPLACE_BZ
                    d = bz2.decompress(d)
                elif op['type'] != 0:    # REPLACE
                    raise SystemExit("unsupported op type %d" % op['type'])
                p = 0
                for s, nb in op['dst']:
                    out.seek(s * bs)
                    out.write(d[p:p + nb * bs])
                    p += nb * bs
        print("extracted %s: %d bytes -> %s" % (name, size, outp))
        return
    raise SystemExit("partition %r not in payload" % want)


if __name__ == '__main__':
    main()
