@echo off
rem Magisk install of @RELEASE@. Extra options: -DryRun -Wipe -NoWipe -ConfirmDevice
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" -Magisk %*
pause
