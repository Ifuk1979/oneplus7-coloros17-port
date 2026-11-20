# OnePlus7Port AutoPort

[中文说明](自动移植脚本说明.md)

Turns a **OnePlus PYB110 (OnePlus 16, China) ColorOS 17 full OTA zip** into a flash-ready **OnePlus 7 Pro (GM1910)** fastboot
package: the same layout as the published `ColorOS17.0.1.201(los20261011-r2)` release (installers for Windows and
Linux/macOS, NoRoot and Magisk variants, firmware included, no earlier package needed).

It runs the same build stages that produced the published release (`tools-reforge/`), on top of LineageOS 24 (20261011)
vendor/kernel. Everything except the ColorOS ROM is in this archive.

## What you need

- Windows 10/11 with **WSL2** (Ubuntu 22.04 or 24.04), or an x86_64 Linux PC with root (Ubuntu/Debian).
- **80 GB free** on the Linux file system (inside WSL, not on `C:` / `/mnt/c`). 8 GB RAM is enough.
- Internet for the first run (apt packages).
- A **full** OTA zip of OnePlus PYB110 ColorOS 17 (has `payload.bin` inside, ~10 GB). Verified with
  **PYB110_17.0.1.201(CN01)**. Other 17.x builds may work: every patch is checked before it is applied, and the build stops with a
  message instead of producing a broken image.

## Run

```bash
# Windows: open "Ubuntu" from the Start menu, or in PowerShell:  wsl -u root
sudo -i                                   # (Linux / WSL as a normal user)
cd ~ && tar -xzf /mnt/c/Users/<you>/Downloads/OnePlus7Port-AutoPort-*.tar.gz
cd OnePlus7Port-AutoPort-*
bash autoport.sh /mnt/c/Users/<you>/Downloads/<PYB110 full OTA>.zip
```

Extract the archive inside Linux (`~`), not on a Windows drive: the build needs Linux file permissions and SELinux labels.

The first run installs the toolchain (apt packages, and secilc 3.11 built from the bundled SELinux sources), checks the ROM,
then builds for about 1–2 hours. The result:

```
/root/op7-autoport/release/ColorOS17.0.1.201(los20261011-r2)/          the release folder (installers + images)
/root/op7-autoport/release/OnePlus7Pro-ColorOS17.0.1.201(los20261011-r2).zip
```

Copy the zip to Windows (for example `cp … /mnt/c/Users/<you>/Desktop/`), extract it and follow its `README.md`
(`Install-NoRoot.bat` / `Install-Magisk.bat`, or `install.sh` on Linux/macOS).

### Options

| Option | |
|---|---|
| `--check` | only check the PC, install the tools and read the ROM; builds nothing |
| `--base DIR` | work / tool / output folder (default `/root/op7-autoport`, must be ext4) |
| `--rev N` | rebuild number in the version name (default 2) |
| `--from NN` | resume at stage NN (`01 10 11 12 13 14 18 20 30`) or `package` after fixing a failure |
| `--no-zip` | stop at the release folder |
| `--no-apt` | do not run apt (install the packages listed in `autoport/lib/bootstrap.sh` yourself) |

Logs: `docs/logs/<date>-autoport.log` and one log per stage next to it.

## Notes

- Each build signs `system` with its **own** new AVB key (`/root/op7-autoport/work/avb/port_key.pem`); the phone's vbmeta has
  verification disabled, so no key needs to match.
- The boot image does not depend on the ROM. When the built one has the same content as the phone-tested boot of the published
  release, the tested `boot.img` and its Magisk v31.0 patch are used; otherwise the package is NoRoot only (a warning says so).
- Development build like the published release: SELinux permissive, adb root.
- If a stage stops with "... changed" or "not found", the ROM differs from 17.0.1.201 in a file the port patches. The
  message names the file; that ROM version needs a port update.

## 中文快速说明

1. Windows 装好 WSL2 的 Ubuntu，Linux 分区留 80 GB 空间。
2. 准备一加 16（PYB110）ColorOS 17 **全量** OTA 包（里面有 payload.bin），已验证 17.0.1.201。
3. 以 root 打开 Ubuntu，在 `~` 里解压本压缩包，执行 `bash autoport.sh <全量包路径>`。首次会自动安装工具。
4. 大约 1–2 小时后，在 `/root/op7-autoport/release/` 得到刷机包 zip，复制到 Windows，解压后按里面的 README 用
   `Install-NoRoot.bat` 或 `Install-Magisk.bat` 刷机。不需要先刷任何底包。

Credits: LineageOS (vendor, kernel), OnePlus/OPLUS (ColorOS, firmware), Magisk (topjohnwu), SELinux project (secilc).
