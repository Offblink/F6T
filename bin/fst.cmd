@echo off
set FST_SCRIPT=%LOCALAPPDATA%\F6T\src\fst.ps1
if not exist "%FST_SCRIPT%" (
    echo F6T not found. Run install.ps1 from the F6T source directory.
    exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%FST_SCRIPT%" %*
