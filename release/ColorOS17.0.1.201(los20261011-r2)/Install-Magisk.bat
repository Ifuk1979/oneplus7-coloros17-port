@echo off
rem Magisk install of ColorOS17.0.1.201(los20261011-r2). Extra options: -DryRun -Wipe -NoWipe -ConfirmDevice
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" -Magisk %*
pause
