@echo off
setlocal
cd /d "%~dp0"
echo Dreamcast CDI to CHD
echo.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0cdi2chd.ps1"
echo.
if errorlevel 1 (
  echo The converter returned an error. Check journal\cdi2chd_log.txt.
) else (
  echo Conversion finished. Check journal\cdi2chd_log.txt.
)
pause
