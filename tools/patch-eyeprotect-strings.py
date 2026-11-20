"""Rewrite the two ColorOS 17 low-flicker option strings in OplusEyeProtect.apk (resources.arsc string pool, in place).
The options are routed to the OnePlus 7 Pro panel's DC backlight (tools/live/display-dc/DcBridge.java), so the stock text
(144 Hz, 1 nit, "full-brightness DC") would be wrong. Same-size edit: each new string is no longer than the old one (the rest of the
entry is zero padded), so every offset stays valid; only the zip CRC32 is updated. The APK signature block is left as is
(same approach as the other patched port APKs). Usage: patch-eyeprotect-strings.py in.apk out.apk
"""
import struct, sys, zlib, zipfile, shutil

PAIRS = [  # (old, new) exactly as in the donor resources
    ('全亮度低频闪', 'DC调光'),
    ('经典低频闪', '标准调光'),
    ('中高亮度 DC 调光，降低屏幕闪烁。屏幕亮度最低可支持 1 nit。', '使用默认调光'),
    ('全亮度 DC 调光，降低屏幕闪烁。为保证高刷极致流畅和显示最优画质，开启 144 Hz 或以上刷新率时会自动切换至经典低频闪模式。',
     '亮度较低时开启DC调光'),
    ('全亮度低频闪模式为“护眼实验室”研发的探索性功能', ''),
    ('Beta', 'Port'),
    ('Extended anti-flicker', 'Low-light DC dimming'),
    ('Standard anti-flicker', 'Standard dimming'),
    ('Reduces screen flicker using DC dimming for medium-to-high brightness. The screen brightness can be as low as 1 nit.',
     'Default dimming'),
    ('Reduces screen flicker with DC dimming at all brightness levels. This will switch to "Standard anti-flicker" at a refresh rate of 144 Hz or higher to ensure smoothness and graphics quality.',
     'Enable DC dimming at low brightness'),
    ('Extended anti-flicker is an experimental feature developed by the Eye Care Lab.', ''),
]

def u8len(b, p):
    n = b[p]; p += 1
    if n & 0x80: n = ((n & 0x7f) << 8) | b[p]; p += 1
    return n, p

def enc_len(n):
    return bytes([n]) if n < 0x80 else bytes([0x80 | (n >> 8), n & 0xff])

src, dst = sys.argv[1:3]
shutil.copyfile(src, dst)
buf = bytearray(open(dst, 'rb').read())
zi = zipfile.ZipFile(src).getinfo('resources.arsc')
assert zi.compress_type == 0
lh = zi.header_offset
nlen, elen = struct.unpack_from('<HH', buf, lh + 26)
base = lh + 30 + nlen + elen
arsc = memoryview(buf)[base:base + zi.file_size]
assert struct.unpack_from('<H', arsc, 0)[0] == 0x0002
sp = struct.unpack_from('<H', arsc, 2)[0]          # first chunk = global string pool
assert struct.unpack_from('<H', arsc, sp)[0] == 0x0001
hdr, size = struct.unpack_from('<HxxI', arsc, sp + 2 - 2 + 0) if False else (struct.unpack_from('<H', arsc, sp + 2)[0], struct.unpack_from('<I', arsc, sp + 4)[0])
count, scount, flags, sstart = struct.unpack_from('<IIII', arsc, sp + 8)
assert flags & 0x100, 'pool is not UTF-8'
offs = struct.unpack_from('<%dI' % count, arsc, sp + hdr)
pool_end = sp + size
entries = []
for i, o in enumerate(offs):
    p = sp + sstart + o
    nchars, q = u8len(arsc, p)
    nbytes, q = u8len(arsc, q)
    entries.append((p, q, nbytes))
done = {}
for old, new in PAIRS:
    ob = old.encode(); nb = new.encode()
    hits = [i for i, (p, q, n) in enumerate(entries) if n == len(ob) and bytes(arsc[q:q + n]) == ob]
    assert hits, 'not found: ' + old[:30]
    assert len(nb) <= len(ob), ('new text longer than old (%d > %d): %s' % (len(nb), len(ob), new))
    for i in hits:
        p, q, n = entries[i]
        entry_size = (q - p) + n + 1
        newentry = enc_len(len(new)) + enc_len(len(nb)) + nb + b'\0'
        assert len(newentry) <= entry_size, ('entry overflow', new)
        arsc[p:p + entry_size] = newentry + b'\0' * (entry_size - len(newentry))
    done[old[:16]] = len(hits)
print('patched', done)
# CRC32 in the local header and the central directory
crc = zlib.crc32(bytes(arsc)) & 0xffffffff
struct.pack_into('<I', buf, lh + 14, crc)
cd = buf.rfind(b'PK\x01\x02' + b'', 0)
pos = 0; found = False
while True:
    pos = buf.find(b'PK\x01\x02', pos)
    if pos < 0: break
    fn_len, ex_len, cm_len = struct.unpack_from('<HHH', buf, pos + 28)
    if bytes(buf[pos + 46:pos + 46 + fn_len]) == b'resources.arsc':
        struct.pack_into('<I', buf, pos + 16, crc); found = True; break
    pos += 4
assert found
open(dst, 'wb').write(buf)
z = zipfile.ZipFile(dst); assert z.testzip() is None
print('ok, crc', hex(crc), 'size unchanged', len(buf) == len(open(src, 'rb').read()))
