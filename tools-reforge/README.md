# tools-reforge - build the port images from raw sources

Current state and rebuild/flash commands: `docs/2026-11-10-handoff-ota105-build.md`. Plan and decisions: `docs/2026-11-10-reforge-plan.md`. Audit behind it: `docs/research/2026-11-07-scratch-build-audit.md`. Phone checklist: `docs/2026-11-10-r3-fix-checklist.md`.

Sources (all under `StockRom/`, read only): the **PLK110 17.0.0.105 full OTA** (system, system_ext, product, my_*; the AxisGSI is no longer used), LineageOS 24 guacamole (baseline payload of 20261011, nightly 20261109 later) and the OnePlus 7 Pro H.40 stock (camera stack, SoundTrigger). Paths and sha256 pins are in `config.env`; the release name (`17.0.0.105-los20261011-r1`) is derived there too.

```
wsl -u root                                  # everything runs as root in WSL
bash tools-reforge/run.sh --list             # list stages
bash tools-reforge/run.sh 00                 # preflight (read only); add --hash for the full sha256 check
bash tools-reforge/run.sh 01                 # extract my_stock/product/my_product/small my_* from the OTA into /root/reforge-work/cache
bash tools-reforge/run.sh 10 11 12 13 14 18 20 30 35    # full image set -> release/trial/reforge-out/smoke{,-debug}
```

| Stage | Output / job |
| --- | --- |
| 10 | assemble the system tree (resets `$WORK/tree`), identity, dev props, CIL fixes, tethering APEX |
| 11 | system-side BAKE-LIST fixes (ported from tools/build-port-b.sh) |
| 12 | re-patches on the .105 files: services.jar fpcmd, oplus-services, SystemUI dim, WallpaperChooser |
| 13 | camera system side + `my_stock-105.img` (slow) |
| 14 | property pins (B16 keys that ColorOS would override) |
| 18 | pack `system.img` (size cuts, EROFS, AVB) |
| 20 | `vendor.img` (+ `lib/vendor-fixes.inc.sh`, permissive policy, two secilc compile gates) |
| 30 | `boot.img`, `dtbo.img`, `vbmeta.img`, SHA256SUMS |
| 35 | debug-only: logger boot, vendor with logcat and props dump |

Re-running 11-13 on an existing tree fails by design (patches assert their inputs): run 10 first. Status: smoke scope, dev props, SELinux permissive (release blockers listed in the handoff, section 6). Not yet: production variant, eSE/Magisk boots, packaging, comparison step, LineageOS 20261109.
`fixes.tsv` lists every BAKE-LIST fix with the stage that produces it and the proof so far ("user-observed" = tested by hand, no automated check yet).
Logs: `docs/logs/YYYY-MM-DD-reforge-<stage>.log` (overwritten when a stage reruns the same day). Outputs: `release/trial/reforge-out/` (promoted to `release/<ver>/` only after approval).
Credits: LineageOS and Axis GSI (earlier builds), see the root README.
