# F6T — Install Script
# Run: powershell -ExecutionPolicy Bypass -File install.ps1
#
# Installs F6T by copying source to a permanent location,
# adding the `fst` function to your PowerShell profile,
# and ensuring Python + Pillow dependencies are met.

$ErrorActionPreference = "Continue"
Write-Host "=== F6T Installer ===" -ForegroundColor Cyan

# 1. Find Python (multiple search paths, skip Store stubs)
$python = $null
$searchRoots = @(
    "C:\Users\$env:USERNAME\AppData\Local\Programs\Python",
    "C:\Users\$env:USERNAME\AppData\Local\Python"
)
foreach ($root in $searchRoots) {
    if (-not (Test-Path $root)) { continue }
    $pyDirs = Get-ChildItem $root -Directory -Filter "Python3*" -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending
    if (-not $pyDirs) {
        # Also try pythoncore-* pattern (python.org installer)
        $pyDirs = Get-ChildItem $root -Directory -Filter "pythoncore-3*" -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending
    }
    foreach ($dir in $pyDirs) {
        $candidate = Join-Path $dir.FullName "python.exe"
        if (Test-Path $candidate) {
            $python = $candidate
            break
        }
    }
    if ($python) { break }
}
if (-not $python) {
    # Fallback: python in PATH (but NOT the WindowsApps Store stub)
    $allPy = Get-Command python -ErrorAction SilentlyContinue -All
    foreach ($cmd in $allPy) {
        if ($cmd.Source -notmatch "WindowsApps") {
            $python = $cmd.Source
            break
        }
    }
}
if (-not $python) {
    Write-Error "Python not found. Install from https://python.org"
    exit 1
}
Write-Host "Python: $python" -ForegroundColor Green

# 2. Check Pillow
& $python -c "from PIL import Image" 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Installing Pillow..." -ForegroundColor Yellow
    & $python -m pip install Pillow
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to install Pillow"
        exit 1
    }
}
Write-Host "Pillow: OK" -ForegroundColor Green

# 3. Check FFmpeg
$ffmpegOk = ffmpeg -version 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "WARNING: FFmpeg not found. Video playback won't work." -ForegroundColor Yellow
    Write-Host "  Install: winget install ffmpeg" -ForegroundColor Yellow
} else {
    $ver = (ffmpeg -version | Select-Object -First 1) -replace 'ffmpeg version ',''
    Write-Host "FFmpeg: $ver" -ForegroundColor Green
}

# 4. Copy source to permanent location
$srcDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $srcDir) { $srcDir = "." }
$srcDir = (Resolve-Path $srcDir).Path

$installDir = "$env:LOCALAPPDATA\F6T"
if ($srcDir -ne $installDir) {
    Write-Host "Copying to $installDir ..." -ForegroundColor Cyan
    if (Test-Path $installDir) {
        Remove-Item $installDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    Copy-Item $srcDir $installDir -Recurse -Force

    # Ensure bin directory exists
    $binDir = "$installDir\bin"
    if (-not (Test-Path $binDir)) {
        New-Item -ItemType Directory -Force -Path $binDir | Out-Null
    }
}

# 5. Save Python path for fst.ps1
"$python" | Out-File -FilePath "$installDir\python.txt" -Encoding ascii -Force

# 6. Register bin directory in user PATH
$currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
if (-not $currentPath) { $currentPath = "" }
if ($currentPath -notlike "*$binDir*") {
    Write-Host "Adding $binDir to user PATH..." -ForegroundColor Cyan
    [Environment]::SetEnvironmentVariable("Path", "$currentPath;$binDir", "User")
    # Update current session too
    $env:Path = "$env:Path;$binDir"
}

# 7. Set up uninstall function (removes PATH entry too)
$uninstallFunc = @"

##### F6T-Uninstall #####
function global:fst-uninstall {
    Write-Host "Removing F6T..." -ForegroundColor Yellow
    if (Test-Path "$installDir") {
        Remove-Item "$installDir" -Recurse -Force
        Write-Host "  Removed $installDir" -ForegroundColor Green
    }
    # Remove from PATH
    `$currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if (-not `$currentPath) { `$currentPath = "" }
    `$newPath = (`$currentPath -split ";" | Where-Object { `$_ -notlike "*F6T\bin*" }) -join ";"
    [Environment]::SetEnvironmentVariable("Path", `$newPath, "User")
    Write-Host "  Removed F6T from PATH" -ForegroundColor Green
    # Remove from profile
    `$profile = `$PROFILE
    if (Test-Path `$profile) {
        `$content = Get-Content `$profile -Raw
        `$lines = `$content -split "\r?\n"
        `$start = -1; `$end = -1
        for (`$i = 0; `$i -lt `$lines.Count; `$i++) {
            if (`$lines[`$i] -match "^##### F6T ") { `$start = `$i }
            if (`$start -ge 0 -and `$i -gt `$start -and `$lines[`$i] -match "^##### ") { `$end = `$i - 1; break }
        }
        if (`$start -ge 0) {
            if (`$end -lt 0) { `$end = `$lines.Count - 1 }
            `$newContent = (`$lines[0..(`$start-1)] + `$lines[(`$end+1)..(`$lines.Count-1)]) -join "\`r\`n"
            [IO.File]::WriteAllText(`$profile, `$newContent.TrimEnd())
            Write-Host "  Removed F6T from profile" -ForegroundColor Green
        }
    }
    Write-Host "F6T uninstalled. Restart terminal." -ForegroundColor Cyan
}
"@

# 8. Build fst function (thin wrapper -> fst.ps1)
$fstFunc = @"

##### F6T — FFmpeg + Sixel -> Terminal #####
function global:fst {
    & "$installDir\src\fst.ps1" @args
}
"@

# 9. Add to profile
$profileDir = Split-Path $PROFILE -Parent
if (-not (Test-Path $profileDir)) {
    New-Item -ItemType Directory -Force -Path $profileDir | Out-Null
}

$existing = if (Test-Path $PROFILE) { Get-Content $PROFILE -Raw } else { "" }

# Remove old F6T block(s) if present
$hasF6T = $existing -match "##### F6T "
$hasUninstall = $existing -match "##### F6T-Uninstall"

if ($hasF6T -or $hasUninstall) {
    Write-Host "F6T already in profile. Updating..." -ForegroundColor Yellow
    $lines = $existing -split "`r`n"
    $newLines = @()
    $skip = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match "^##### F6T(-Uninstall)? ") {
            $skip = $true
        }
        if (-not $skip) {
            $newLines += $lines[$i]
        }
        if ($skip -and $lines[$i] -match "^##### " -and $lines[$i] -notmatch "^##### F6T") {
            $skip = $false
            $newLines += $lines[$i]
        }
    }
    $existing = ($newLines -join "`r`n").TrimEnd()
}

$fullBlock = "`r`n$uninstallFunc`r`n$fstFunc"
if ($existing) {
    [IO.File]::WriteAllText($PROFILE, $existing + $fullBlock)
} else {
    [IO.File]::WriteAllText($PROFILE, $fullBlock.TrimStart())
}

Write-Host "Profile updated: $PROFILE" -ForegroundColor Green
Write-Host ""
Write-Host "=== Done! Restart terminal, then: ===" -ForegroundColor Cyan
Write-Host "  fst $installDir\examples\demo.png" -ForegroundColor White
Write-Host "  fst C:\path\to\video.mp4" -ForegroundColor White
Write-Host "  fst C:\path\to\image.jpg -Ansi" -ForegroundColor White
Write-Host "  fst -Help" -ForegroundColor White
Write-Host ""
Write-Host "Works in PowerShell AND cmd.exe" -ForegroundColor Green
Write-Host "Uninstall:  fst-uninstall  (PowerShell)" -ForegroundColor DarkGray
