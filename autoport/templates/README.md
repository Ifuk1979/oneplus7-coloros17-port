# OnePlus 7 Pro — @RELEASE@

ColorOS 17 (@DONOR_DISPLAY@) ported to the OnePlus 7 Pro (GM1910, `guacamole`) by OnePlus7Port AutoPort on @DATE@.
About phone shows **GM1910_@RELEASE_SHORT@**. Complete fastboot package: no earlier port release is needed.

## Requirements
- OnePlus 7 Pro GM1910 (fastboot product `msmnile`) with an **unlocked bootloader**; platform-tools (`adb`, `fastboot`) on PATH.
- ~13 GB free on the PC, ~8 GB free in the phone storage.
- OxygenOS 11 **H.40** firmware on the phone (included in `images/firmware`; bootloaders without `fastboot flashing unlock_critical`
  refuse to write it, the installer then skips it with a warning).

## Install
| | Windows | Linux / macOS |
|---|---|---|
| NoRoot | `Install-NoRoot.bat` | `bash ./install.sh` |
| Magisk | `Install-Magisk.bat` | `bash ./install.sh --magisk` |
| Check only | add `-DryRun` | add `--dry-run` |

- **Upgrade** (keeps data): start with the phone booted into a ColorOS 17 port build with USB debugging on; answer Enter at the WIPE question.
- **Clean install / from another ROM**: phone in fastboot (or booted with USB debugging); type `WIPE` (required when coming from another
  ROM). The installer stages `@MYSTOCK@` into `/data/port` on the first boot over adb.
- Only the active slot is written.

## Notes
- Development build: SELinux permissive, adb root. 
- The camera is the OnePlus7Port build of ColorOS camera 7.012.185 (photo, ultra-wide/tele, video, filters, Live Photo, slow-mo,
  time-lapse). Dual-view, long exposure, face beauty and background blur are not available on this hardware.
- `images/SHA256SUMS` is checked by the installer before anything is written.
