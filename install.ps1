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
}

# 5. Set up uninstall function
$uninstallFunc = @"

##### F6T-Uninstall #####
function global:fst-uninstall {
    Write-Host "Removing F6T..." -ForegroundColor Yellow
    if (Test-Path "$installDir") {
        Remove-Item "$installDir" -Recurse -Force
        Write-Host "  Removed $installDir" -ForegroundColor Green
    }
    `$profile = `$PROFILE
    if (Test-Path `$profile) {
        `$content = Get-Content `$profile -Raw
        # Remove F6T block
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
    Write-Host "F6T uninstalled. Restart PowerShell." -ForegroundColor Cyan
}
"@

# 6. Build fst function
$fstFunc = @"

##### F6T — FFmpeg + Sixel -> Terminal #####
function global:fst {
    param(
        [string]`$Path,
        [int]`$Width,
        [int]`$Fps = 15,
        [int]`$Colors = 32,
        [switch]`$Ansi,
        [switch]`$Help
    )
    if (`$Help -or `$Path -eq "-h" -or `$Path -eq "--help" -or `$Path -eq "/?") {
        Write-Host @'
F6T — FFmpeg + Sixel -> Terminal

Usage:  fst <file> [-Ansi] [-Width N] [-Fps N] [-Colors N] [-Help]

  <file>        Image or video file path
  -Ansi         Use ANSI half-block mode (universal, no Sixel terminal needed)
  -Width N      Output width in characters (image: 300, video: 200 default)
  -Fps N        Target frame rate for video (default 15)
  -Colors N     Palette size for Sixel mode, 8-256 (default 32)
  -Help         Show this help

Examples:
  fst photo.jpg                    # Sixel image display
  fst photo.jpg -Ansi              # ANSI image (zero config)
  fst video.mp4                    # Sixel video playback
  fst video.mp4 -Ansi -Width 100   # ANSI video, compact
  fst video.mp4 -Width 300 -Fps 24 # Sixel HD

Uninstall:  fst-uninstall
'@
        return
    }
    if (-not `$Path) {
        Write-Host "Usage: fst <file> [-Ansi] [-Width N] [-Fps N] [-Colors N]"
        Write-Host "       fst -Help"
        return
    }
    `$py = "$python"
    `$src = "$installDir\src"
    `$ext = [IO.Path]::GetExtension(`$Path).ToLower()
    `$isVideo = @('.mp4','.mkv','.avi','.mov','.webm','.flv','.wmv','.ts') -contains `$ext

    if (`$Ansi) {
        if (`$isVideo) {
            `$w = if (`$Width) { `$Width } else { 120 }
            & `$py `$src\play_video.py `$Path -a -w `$w -f `$Fps
        } else {
            `$w = if (`$Width) { `$Width } else { 150 }
            & `$py `$src\show_img_ansi.py `$Path -w `$w
        }
    } else {
        if (`$isVideo) {
            `$w = if (`$Width) { `$Width } else { 200 }
            & `$py `$src\play_video.py `$Path -w `$w -f `$Fps -c `$Colors
        } else {
            `$w = if (`$Width) { `$Width } else { 300 }
            & `$src\show_img.ps1 -ImagePath `$Path -MaxWidth `$w -MaxColors `$Colors
        }
    }
}
"@

# 7. Add to profile
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
Write-Host "=== Done! Restart PowerShell, then: ===" -ForegroundColor Cyan
Write-Host "  fst $installDir\examples\demo.png" -ForegroundColor White
Write-Host "  fst C:\path\to\video.mp4" -ForegroundColor White
Write-Host "  fst C:\path\to\image.jpg -Ansi" -ForegroundColor White
Write-Host "  fst -Help" -ForegroundColor White
Write-Host ""
Write-Host "Uninstall:  fst-uninstall" -ForegroundColor DarkGray
