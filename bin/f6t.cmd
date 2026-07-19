@echo off
set F6T_SCRIPT=%LOCALAPPDATA%\F6T\src\f6t.ps1
if not exist "%F6T_SCRIPT%" (
    echo F6T not found. Run install.ps1 from the F6T source directory.
    exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%F6T_SCRIPT%" %*
