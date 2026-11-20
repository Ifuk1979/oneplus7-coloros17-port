# Test status — ColorOS17.0.1.201(los20261011-r2)

## Re-release 2026-11-20 evening (this package)

Only `system.img` (`5df57c17…`) and `my_stock-pyb201.img` (`126e2c43…`) are new; boot, boot-magisk31, vendor, dtbo, vbmeta,
firmware and Magisk are the files of the first r2 package listed below.

Verified on the author's phone with **these two images** (flashed `system_a` + staged my_stock, booted with the first r2's
boot/vendor, data kept):

- Boots; About phone `GM1910_17.0.1.201(los20261011-r2)`; zygote runs on the new `/system/framework/arm64/boot.art` boot image
  (no imageless fallback).
- WeChat video call: the remote video is no longer stretched (user test). Decoder test: `c2.qti.hevc.decoder` with a Surface
  reports 640x480 after a 640x288 -> 640x480 change (was 640x288); ByteBuffer output and the software decoder unchanged.
- H.40 OnePlus Camera 7.2.47: app and `com.oneplus.camera.service` run (service as `system_app`, uid 1000, no zygote abort);
  photo, video and lens switching work (user test). The ColorOS camera 7.012 is still installed.

## First r2 package (2026-11-20 morning)

Verified with that package (Magisk variant, upgrade from the r1 PYB build, data kept; NoRoot variant also flashed and booted):

- Installer: images checked, my_stock staged and verified on the phone, fastboot flash of the active slot, reboot. The bootloader
  (critical partitions locked) refused all firmware writes except `modem`; the installer skipped them with a warning as designed.
- Boots; Magisk root active (Magisk variant); no su, adb root (NoRoot); `/my_stock` mounted.
- Camera 7.012 from the system image: rear photo, front photo, 1080p video. Wireless charging feature absent.

Verified live before the bake, not re-tested on a built image: camera 0.6x / 3x, portrait, filters, Live Photo, slow motion
1080p240, time-lapse v1; charging settings and Quick Settings without wireless entries; fingerprint in battery saver (B31), IR
proximity after a framework restart (B32), Breeno wake-word.

Not tested: clean install / WIPE path and installing from another ROM; Windows installer (`install.ps1`) end to end.
