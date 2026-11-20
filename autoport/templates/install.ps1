# OnePlus 7 Pro (GM1910, guacamole) ColorOS @RELEASE_SHORT@ - complete fastboot package installer (Windows).
# Same steps as install.sh. Complete package: firmware (OxygenOS 11 H.40), dtbo, vbmeta, boot, vendor, system and
# @MYSTOCK@ (mounted from /data/port). No earlier port package is needed. Only the ACTIVE slot is written.
#   .\install.ps1                  NoRoot install (asks the WIPE question after flashing)
#   .\install.ps1 -Magisk          Magisk v31.0 install
#   .\install.ps1 -DryRun          check everything, change nothing
#   .\install.ps1 -Wipe | -NoWipe  answer the WIPE question in advance
#   .\install.ps1 -ConfirmDevice   accept a fastboot product other than msmnile
param([switch]$Magisk, [switch]$DryRun, [switch]$Wipe, [switch]$NoWipe, [switch]$ConfirmDevice)
$ErrorActionPreference = 'Stop'
$Release = '@RELEASE@'
$MyStock = '@MYSTOCK@'
$Firmware = 'abl aop bluetooth cmnlib cmnlib64 devcfg dsp hyp keymaster modem qupfw storsec tz xbl xbl_config'.Split(' ')
function Die($m) { Write-Host "ERROR: $m" -ForegroundColor Red; exit 1 }
if ($Wipe -and $NoWipe) { Die '-Wipe and -NoWipe cannot be combined.' }
Set-Location -LiteralPath $PSScriptRoot
foreach ($t in 'adb', 'fastboot') { if (-not (Get-Command $t -ErrorAction SilentlyContinue)) { Die "$t is not on PATH (install Android platform-tools)." } }
$BootImg = if ($Magisk) { 'boot-magisk31.img' } else { 'boot.img' }
$sums = @{}
foreach ($l in Get-Content -LiteralPath 'images\SHA256SUMS') { if ($l -match '^([0-9a-fA-F]{64})\s+\*?(.+)$') { $sums[$Matches[2]] = $Matches[1].ToLower() } }
function Check-Image($f) {
  $p = Join-Path 'images' $f
  if (-not (Test-Path -LiteralPath $p)) { Die "Missing image: $p" }
  if (-not $sums.ContainsKey($f)) { Die "images\SHA256SUMS has no entry for $f" }
  Write-Host ("Checking {0,-26} " -f $f) -NoNewline
  $h = (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLower()
  if ($h -ne $sums[$f]) { Write-Host; Die "SHA-256 mismatch for ${p}: $h" }
  Write-Host 'OK'
}
Write-Host "== $Release, $(if ($Magisk) {'magisk'} else {'noroot'}) install =="
$list = @($Firmware | ForEach-Object { "firmware/$_.img" }) + @('dtbo.img', 'vbmeta.img', $BootImg, 'vendor.img', 'system.img', $MyStock)
if ($Magisk) { $list += 'Magisk-v31.0.apk' }
foreach ($f in $list) { Check-Image $f }
$MyStockSha = $sums[$MyStock]; $MyStockSize = (Get-Item -LiteralPath "images\$MyStock").Length

function Ash([string]$c) { ((& adb shell $c 2>$null) -join "`n").Replace("`r", '').Trim() }
$script:UseSu = $false
function Detect-Root {
  if ((Ash 'id -u') -eq '0') { $script:UseSu = $false; return $true }
  & adb root 2>$null | Out-Null; Start-Sleep 3; & adb wait-for-device
  if ((Ash 'id -u') -eq '0') { $script:UseSu = $false; return $true }
  if ((Ash 'su -c id -u') -eq '0') { $script:UseSu = $true; return $true }
  return $false
}
function Rsh([string]$c) { if ($script:UseSu) { Ash "su -c '$c'" } else { Ash $c } }
function Stage-MyStock {
  Rsh 'mkdir -p /data/port && chmod 0750 /data/port' | Out-Null
  $cur = ((Rsh "[ -f /data/port/$MyStock ] && sha256sum /data/port/$MyStock") -split '\s+')[0]
  if ($cur -eq $MyStockSha) { Write-Host "/data/port/$MyStock is already this release's my_stock; not copied again."; $script:Copied = $false; return }
  $free = [int64](((Rsh 'df -k /data | tail -1') -split '\s+')[3])
  if ($free * 1024 -le $MyStockSize + 1073741824) { Die "Not enough free space in /data for my_stock." }
  Write-Host "Pushing $MyStock ($([int]($MyStockSize / 1MB)) MiB) ..."
  & adb push "images\$MyStock" "/data/local/tmp/$MyStock.new"; if ($LASTEXITCODE) { Die 'adb push failed.' }
  Rsh "mv /data/local/tmp/$MyStock.new /data/port/$MyStock.new" | Out-Null
  Write-Host 'Checking the copy on the phone ...'
  $h = ((Rsh "sha256sum /data/port/$MyStock.new") -split '\s+')[0]
  if ($h -ne $MyStockSha) { Die 'my_stock copy on the phone is corrupt; nothing was flashed.' }
  $prev = $MyStock -replace '\.img$', '-prev.img'
  Rsh "cd /data/port && { [ ! -f $MyStock ] || mv -f $MyStock $prev; } && mv $MyStock.new $MyStock && chown 0:0 $MyStock && chmod 0644 $MyStock && chcon u:object_r:system_file:s0 $MyStock && sync" | Out-Null
  $script:Copied = $true
  Write-Host "my_stock staged (previous one kept as $prev)."
}
function Get-Var($n) { $o = (& fastboot getvar $n 2>&1) -join "`n"; if ($o -match "(?m)^${n}:\s*(\S+)") { $Matches[1] } else { '' } }

$Staged = $false
if (((& adb get-state 2>$null) -join '') -match 'device') {
  $dev = Ash 'getprop ro.product.device'; $code = Ash 'getprop ro.boot.project_codename'
  if ($dev -ne 'guacamole' -and $code -ne 'guacamole' -and $dev -ne 'OnePlus7Pro') { Die "This is not a OnePlus 7 Pro (device '$dev')." }
  $shown = Ash 'getprop ro.build.display.id.show'; Write-Host "Phone runs: $shown"
  if ($shown -like 'GM1910_17.*' -and (Detect-Root)) {
    Write-Host 'Installed port with root found: upgrade, my_stock is staged now (data kept).'
    if ($DryRun) { Write-Host 'DRY RUN: would stage my_stock, reboot to fastboot and flash. Nothing changed.'; exit 0 }
    Stage-MyStock; $Staged = $true
  } else {
    Write-Host 'No rooted ColorOS 17 port running: flashing from fastboot, my_stock is staged on the first boot.'
    Write-Host 'Coming from another ROM (OxygenOS, LineageOS, ...) needs a WIPE.'
    if ($DryRun) { Write-Host 'DRY RUN: nothing changed.'; exit 0 }
  }
  & adb reboot bootloader
}
Write-Host 'Waiting for fastboot ...'
for ($i = 0; $i -lt 60; $i++) { if (((& fastboot devices) -join '') -match 'fastboot') { break }; Start-Sleep 2 }
if (-not (((& fastboot devices) -join '') -match 'fastboot')) { Die 'No phone in fastboot mode.' }
$product = Get-Var 'product'
if ($product -ne 'msmnile') {
  Write-Host "WARNING: fastboot product is '$product', expected 'msmnile'."
  if (-not $ConfirmDevice -and (Read-Host 'Type YES to continue anyway') -ne 'YES') { Die 'Stopped.' }
}
$slot = Get-Var 'current-slot'; if ($slot -ne 'a' -and $slot -ne 'b') { Die "Unknown active slot '$slot'." }
if ($DryRun) { Write-Host "DRY RUN: would flash slot $slot. Nothing changed."; & fastboot reboot; exit 0 }
function Flash($part, $img) { & fastboot flash $part $img; if ($LASTEXITCODE) { Die "fastboot flash $part failed." } }
Write-Host "Flashing the active slot _$slot ..."
# Firmware = OxygenOS 11 H.40. Bootloaders without 'fastboot flashing unlock_critical' refuse the critical ones: skipped with a warning.
$skipped = @()
foreach ($p in $Firmware) {
  $o = (& fastboot flash "${p}_$slot" "images\firmware\$p.img" 2>&1) -join "`n"
  if ($LASTEXITCODE -eq 0) { continue }
  if ($o -match '(?i)critical') { $skipped += $p; Write-Host "WARNING: ${p}_$slot is a critical partition the bootloader refuses: skipped." }
  else { Write-Host $o; Die "fastboot flash ${p}_$slot failed." }
}
if ($skipped) { Write-Host "Skipped critical firmware: $($skipped -join ' '). Fine if the phone already has OxygenOS 11 H.40 firmware; otherwise run 'fastboot flashing unlock_critical' and install again." }
Flash "dtbo_$slot" 'images\dtbo.img'; Flash "vbmeta_$slot" 'images\vbmeta.img'; Flash "boot_$slot" "images\$BootImg"
Flash "vendor_$slot" 'images\vendor.img'; Flash "system_$slot" 'images\system.img'
$Wiped = $false
if ($Wipe) { & fastboot -w; $Wiped = $true }
elseif (-not $NoWipe) {
  Write-Host 'Wipe /data now? Required when coming from another ROM; erases ALL apps, data and files.'
  if ((Read-Host 'Type WIPE to wipe, Enter to keep the data') -eq 'WIPE') { & fastboot -w; $Wiped = $true }
}
& fastboot reboot
if (-not $Staged -or $Wiped) {
  Write-Host 'First boot: waiting for adb to stage my_stock (the first boot without it can look stuck; expected) ...'
  & adb wait-for-device
  for ($i = 0; $i -lt 120; $i++) { if ((Ash 'test -d /data/system && echo y') -eq 'y') { break }; Start-Sleep 5 }
  if (-not (Detect-Root)) { Die "No root over adb on the first boot; copy images\$MyStock to /data/port by hand (see README)." }
  Stage-MyStock; if ($script:Copied) { & adb reboot; & adb wait-for-device }
}
if ($Magisk) {
  Write-Host 'Waiting for Android to finish booting to install the Magisk app ...'
  for ($i = 0; $i -lt 120; $i++) { if ((Ash 'getprop sys.boot_completed') -eq '1') { break }; Start-Sleep 5 }
  if (-not ((Ash 'pm list packages') -match 'package:com.topjohnwu.magisk')) { & adb install -r 'images\Magisk-v31.0.apk' }
}
Write-Host 'Done. If the camera was installed in /data by older live tests, run once: adb shell pm uninstall-system-updates com.oplus.camera'
