<#
.SYNOPSIS
    F6T — FFmpeg + Sixel -> Terminal
    Display images and video in the terminal via Sixel or ANSI.
.DESCRIPTION
    Both PowerShell and cmd.exe compatible.
    PowerShell:  fst <file> [-Ansi] [-Width N] ...
    cmd.exe:     fst <file> [-Ansi] [-Width N] ...
#>
param(
    [string]$Path,
    [int]$Width,
    [int]$Fps = 15,
    [int]$Colors = 32,
    [switch]$Ansi,
    [switch]$Help
)

# ---- Resolve install paths ----
$installDir = "$env:LOCALAPPDATA\F6T"
if (-not (Test-Path $installDir)) {
    $installDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}
$pyFile = "$installDir\python.txt"
if (Test-Path $pyFile) {
    $py = (Get-Content $pyFile).Trim()
}
if (-not $py -or -not (Test-Path $py)) {
    # Discover: glob install dirs, PATH (skip WindowsApps)
    $searchRoots = @(
        "$env:LOCALAPPDATA\Programs\Python",
        "$env:LOCALAPPDATA\Python"
    )
    foreach ($root in $searchRoots) {
        if (-not (Test-Path $root)) { continue }
        $pyDirs = Get-ChildItem $root -Directory -Filter "Python3*" -ErrorAction SilentlyContinue | Sort-Object Name -Descending
        if (-not $pyDirs) {
            $pyDirs = Get-ChildItem $root -Directory -Filter "pythoncore-3*" -ErrorAction SilentlyContinue | Sort-Object Name -Descending
        }
        foreach ($dir in $pyDirs) {
            $c = Join-Path $dir.FullName "python.exe"
            if (Test-Path $c) { $py = $c; break }
        }
        if ($py) { break }
    }
    if (-not $py) {
        $all = Get-Command python -ErrorAction SilentlyContinue -All
        foreach ($cmd in $all) {
            if ($cmd.Source -notmatch "WindowsApps") { $py = $cmd.Source; break }
        }
    }
}
$src = "$installDir\src"

# ---- Help ----
if ($Help -or $Path -eq "-h" -or $Path -eq "--help" -or $Path -eq "/?") {
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

Uninstall:  fst-uninstall  (PowerShell only)
'@
    exit 0
}

# ---- No input ----
if (-not $Path) {
    Write-Host "Usage: fst <file> [-Ansi] [-Width N] [-Fps N] [-Colors N]"
    Write-Host "       fst -Help"
    exit 0
}

# ---- Dispatch ----
$ext = [IO.Path]::GetExtension($Path).ToLower()
$isVideo = @('.mp4','.mkv','.avi','.mov','.webm','.flv','.wmv','.ts') -contains $ext

if ($Ansi) {
    if ($isVideo) {
        $w = if ($Width) { $Width } else { 120 }
        & $py "$src\play_video.py" $Path -a -w $w -f $Fps
    } else {
        $w = if ($Width) { $Width } else { 150 }
        & $py "$src\show_img_ansi.py" $Path -w $w
    }
} else {
    if ($isVideo) {
        $w = if ($Width) { $Width } else { 200 }
        & $py "$src\play_video.py" $Path -w $w -f $Fps -c $Colors
    } else {
        $w = if ($Width) { $Width } else { 300 }
        & "$src\show_img.ps1" -ImagePath $Path -MaxWidth $w -MaxColors $Colors
    }
}
