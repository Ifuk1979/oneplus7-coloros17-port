# OnePlus 7 Pro — ColorOS17.0.1.201(los20261011-r2)

ColorOS 17 (OnePlus PYB110, 17.0.1.201) ported to the OnePlus 7 Pro (GM1910, `guacamole`, Snapdragon 855) on the
LineageOS 24 (20261011) vendor and kernel. About phone shows **ColorOS 17.0.1 / GM1910_17.0.1.201(los20261011-r2)**.

**Complete package:** everything the phone needs is in `images/`; no earlier port release (17d … 17k-r3) has to be flashed
first. One zip, two install variants: **NoRoot** and **Magisk** (Magisk v31.0).

## Requirements

- OnePlus 7 Pro GM1910 (fastboot product `msmnile`), **unlocked bootloader**.
- Android platform-tools (`adb`, `fastboot`) on `PATH`. Windows: PowerShell 5+ (built in). Linux/macOS: bash.
- About 13 GB free on the PC for the extracted zip, 8 GB free in the phone's storage (the my_stock image lives in `/data/port`).
- Firmware: the package carries the OxygenOS 11 **H.40** firmware (`images/firmware`). Most OnePlus 7 Pro bootloaders refuse to
  write these "critical" partitions unless `fastboot flashing unlock_critical` was run; the installer then skips them with a
  warning. That is fine on a phone that already runs H.40 firmware (latest OxygenOS 11, or a LineageOS install made on it).
  On older firmware, update to OxygenOS 11 H.40 first or unlock critical partitions.

## Install

Extract the zip completely, connect exactly one phone, then:

| | Windows | Linux / macOS |
|---|---|---|
| NoRoot | `Install-NoRoot.bat` | `bash ./install.sh` |
| Magisk | `Install-Magisk.bat` | `bash ./install.sh --magisk` |
| Check only (changes nothing) | add `-DryRun` | add `--dry-run` |

**Upgrade (keeps all data):** start with the phone booted into this port (any earlier ColorOS 17 port build) with USB debugging on.
The installer copies `my_stock-pyb201.img` to `/data/port` first (checksum verified on the phone; the old one is kept as
`my_stock-pyb201-prev.img`), reboots to fastboot and flashes the **active slot**: firmware, dtbo, vbmeta, boot, vendor, system.
Answer Enter (or pass `--no-wipe` / `-NoWipe`) at the WIPE question.

**Clean install / coming from another ROM (OxygenOS, LineageOS, other ports):** put the phone in fastboot mode (or boot it with USB
debugging on) and run the installer; type `WIPE` at the question (or pass `--wipe` / `-Wipe`). Data from another ROM cannot be read by
this port, so the wipe is required. After the reboot the installer waits for the first boot, copies `my_stock` to `/data/port` over
adb (this build has adb root) and reboots once more. The very first boot without my_stock can look stuck; that is expected.

Only the active slot is written; the other slot keeps whatever it had (a fallback).

## After the first boot

- Phones that had the ColorOS camera installed in `/data` by earlier live tests: run once
  `adb shell pm uninstall-system-updates com.oplus.camera` (keeps the camera's data), so the patched system camera is used.
- Magisk variant: the installer installs the Magisk app; open it once and let it finish its setup.

## What is in this release (since the last published build)

**Re-release 2026-11-20 (same name, replaces the first r2 package; only `system.img` and `my_stock-pyb201.img` changed):**

- **WeChat video call: the other side's video is no longer stretched** when its aspect ratio changes mid-call (e.g. 20:9 to 4:3).
  The Qualcomm decoders reported a stale width/height after a resolution change; `MediaCodec` now takes them from the crop for
  video sent to a Surface. This patches `framework.jar`, so the system boot image is rebuilt to match. Apps' prebuilt code no
  longer matches that boot image, and Android re-optimises them in the background (idle + charging): some apps may start a bit
  slower for the first day.
- **The OnePlus 7 Pro's own H.40 camera (OnePlus Camera 7.2.47, the video-fixed build of earlier releases) is back**, next to the
  ColorOS camera. Its helper service used to crash at start on this base; its signer is now mapped to the platform SELinux
  context.
- Phones with the first r2: run the installer again as an upgrade (Enter at the WIPE question), data is kept.

First r2 (2026-11-20 morning):

- **Camera: OnePlus 16's own ColorOS camera 7.012.185**, ported to this phone (replaces the 7.006 port). Works: photo (rear
  wide / 0.6× ultra-wide / 2× / 3× tele / front), portrait photo (without background blur), video 1080p, filters (preview and
  photo), Live Photo, slow motion 1080p 240 fps, time-lapse (fixed speeds, recorded like the OnePlus 7 Pro's original camera).
  Removed because the hardware/HAL cannot do them (no NPU, no concurrent cameras, no native ColorOS photo engine): Dual-view
  video, Long exposure (light trails), face beauty, background blur in video/portrait.
- **Wireless charging entries removed** (the OnePlus 7 Pro has no coil): Charging settings "Wireless charging" / "Reverse
  wireless charging" and the reverse-charging Quick Settings tile.
- Fingerprint now lights in battery-saver mode; IR proximity emitter no longer blinks after a framework restart; Breeno
  wake-word no longer crash-loops (custom LPI model removed).
- Everything from earlier builds (calls/IMS state, audio, sensors, display, charging, GPS, …), see `docs/`.

## Known limitations

- Development build: SELinux is permissive and adb runs as root (`ro.debuggable=1`). Do not use it where that matters.
- VoLTE/IMS calling and incoming SMS limits as in earlier builds; see `docs/`.
- The other slot is not updated.

## Rollback

Flash the previous build's `boot`, `vendor`, `system` (and its `my_stock` back to `/data/port/my_stock-pyb201.img`; the installer
keeps the previous one as `my_stock-pyb201-prev.img`).

## Files

- `images/SHA256SUMS` — every image is checked by the installer before anything is written.
- `images/firmware/` — OxygenOS 11 H.40 firmware (abl, aop, bluetooth, cmnlib, cmnlib64, devcfg, dsp, hyp, keymaster, modem,
  qupfw, storsec, tz, xbl, xbl_config). The boot logo is never touched.
- `images/boot.img` (NoRoot), `images/boot-magisk31.img` (Magisk v31.0 patch of the same boot), `images/Magisk-v31.0.apk`.
- `images/dtbo.img`, `vbmeta.img`, `vendor.img`, `system.img`, `my_stock-pyb201.img`.

Credits: LineageOS (vendor, kernel), OnePlus/OPLUS (ColorOS, firmware), Magisk (topjohnwu).
