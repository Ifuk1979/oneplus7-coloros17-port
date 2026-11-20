#!/bin/bash
# Stage 14: property precedence. ro.* is write-once and the .105 init loads the ColorOS partitions (my_manifest, my_product, system_ext, ...)
# BEFORE the LineageOS vendor, so a value the B16 block appends to /vendor/build.prop loses against a ColorOS definition of the same key
# (the GSI init let the vendor win). Found on slot A: ro.sf.lcd_density 560 (want 600), ro.density.screenzoom.qdh/fdh, ro.oplus.radio.lte_rsrp_thresholds.
# Fix: every definition of a B16 key in the ColorOS partition build.props is rewritten to the B16 value (in place, labels kept).
# Runs on $WORK/tree after stages 10-13; re-runnable.
set -euo pipefail
. "$HERE/config.env"; . "$HERE/lib/common.sh"
need_root
T="$WORK/tree"; B16="$PROJECT/tools/live/prop-compare/b16/vendor-build.prop.b16-block"
[ -d "$T/system" ] || die "run stage 10 first"
python3 -I - "$T" "$B16" <<'PY'
import sys, re, os
T, B16 = sys.argv[1:3]
want = {}
for l in open(B16, encoding="utf-8", errors="replace"):
    l = l.strip()
    if l and not l.startswith("#") and "=" in l:
        k, v = l.split("=", 1); want[k] = v
files = ["system/build.prop", "system_ext/etc/build.prop", "product/etc/build.prop", "my_product/build.prop", "my_manifest/build.prop",
         "my_region/build.prop", "my_heytap/build.prop", "my_carrier/build.prop", "my_bigball/build.prop", "my_engineering/build.prop"]
changed = 0
for rel in files:
    p = os.path.join(T, rel)
    if not os.path.isfile(p): continue
    s = open(p, encoding="utf-8", errors="surrogateescape").read(); o = s
    for k, v in want.items():
        pat = re.compile(r"^%s=(.*)$" % re.escape(k), re.M)
        for m in pat.finditer(s):
            if m.group(1) != v:
                print(f"{rel}: {k}: {m.group(1)!r} -> {v!r}"); changed += 1
        s = pat.sub(lambda m: f"{k}={v}", s)
    if s != o:
        with open(p, "r+", encoding="utf-8", errors="surrogateescape") as f:
            f.seek(0); f.write(s); f.truncate()
print(f"{changed} ColorOS definitions pinned to the B16 values")
PY
say "stage 14 done"
