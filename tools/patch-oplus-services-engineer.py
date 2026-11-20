#!/usr/bin/env python3
"""Production-boot fix (17j-r2): OplusEngineerFwService.getEngineerService() calls ServiceManager.waitForService(
"vendor.oplus.hardware.engineer.IEngineer/default") whenever OplusEngineerServiceUtils.isRootVersion() is false, i.e. whenever
ro.adb.secure=1 (production). That HAL does not exist on this phone, so the call blocks forever and the system_server watchdog
kills it every ~70 s (bootloop). Patch: at that single call site isRootVersion() is replaced by `true`, so the non-blocking
initHalService() (ServiceManager.getService) path is always used. isRootVersion() itself and ro.adb.secure are untouched.

usage: patch-oplus-services-engineer.py IN.jar OUT.jar        (needs baksmali + smali on PATH; run as python3 -I)
"""
import os, shutil, subprocess, sys, tempfile, zipfile

src, dst = sys.argv[1:3]
CLS = 'com/android/server/engineering/OplusEngineerFwService.smali'
OLD = ('    :try_start_0\n    invoke-static {}, Lcom/android/server/engineering/OplusEngineerServiceUtils;->isRootVersion()Z\n\n'
       '    move-result v0\n\n    if-eqz v0, :cond_13\n')
NEW = ('    :try_start_0\n    # OnePlus7Port 17j-r2: always the non-blocking getService path (no waitForService on a missing HAL)\n'
       '    const/4 v0, 0x1\n\n    if-eqz v0, :cond_13\n')
tmp = tempfile.mkdtemp()
try:
    zin = zipfile.ZipFile(src)
    hit = None
    for n in sorted(i for i in zin.namelist() if i.startswith('classes') and i.endswith('.dex')):
        if b'OplusEngineerFwService' in zin.read(n):
            assert hit is None, 'class in several dex files'
            hit = n
    assert hit, 'OplusEngineerFwService not found'
    d = os.path.join(tmp, 'in.dex'); open(d, 'wb').write(zin.read(hit))
    sm = os.path.join(tmp, 'sm')
    subprocess.check_call(['baksmali', 'd', '-o', sm, d])
    f = os.path.join(sm, CLS); t = open(f).read()
    # only inside getEngineerService
    head, sep, rest = t.partition('.method private getEngineerService()Lvendor/oplus/hardware/engineer/IEngineer;')
    assert sep and rest.count(OLD) == 1, 'getEngineerService smali changed'
    body, end, tail = rest.partition('.end method')
    assert body.count(OLD) == 1
    open(f, 'w').write(head + sep + body.replace(OLD, NEW) + end + tail)
    out = os.path.join(tmp, 'out.dex')
    subprocess.check_call(['smali', 'a', '-a', '36', '-o', out, sm])
    with zipfile.ZipFile(dst, 'w') as zo:
        for i in zin.infolist():
            data = open(out, 'rb').read() if i.filename == hit else zin.read(i.filename)
            ni = zipfile.ZipInfo(i.filename, i.date_time); ni.compress_type = i.compress_type
            ni.external_attr = i.external_attr; ni.create_system = i.create_system
            zo.writestr(ni, data)
    print('patched %s in %s' % (CLS, hit))
finally:
    shutil.rmtree(tmp, ignore_errors=True)
