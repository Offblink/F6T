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
    [switch]$Sixel,
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
F6T -- FFmpeg + Sixel -> Terminal

Usage:  fst <file> [-Sixel] [-Width N] [-Fps N] [-Colors N] [-Help]

  <file>        Image or video file path
  -Sixel        Use Sixel mode (requires Sixel-capable terminal)
  -Width N      Output width in characters (ANSI: 150, Sixel: 300 default)
  -Fps N        Target frame rate for video (default 15)
  -Colors N     Palette size for Sixel mode, 8-256 (default 32)
  -Help         Show this help

Default is ANSI half-block mode (works everywhere).
Use -Sixel in Windows Terminal 1.22+, xterm, WezTerm, or foot.

Examples:
  fst photo.jpg                     # ANSI (universal)
  fst photo.jpg -Sixel              # Sixel (high quality)
  fst video.mp4                     # ANSI video
  fst video.mp4 -Sixel -Width 300   # Sixel video HD

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

# ---- Sixel capability check ----
if ($Sixel) {
    $sixelOk = $false
    # Only trust env vars the terminal itself sets
    if ($env:TERM -match 'xterm|wezterm|foot') { $sixelOk = $true }
    if ($env:TERM_PROGRAM -eq 'WezTerm') { $sixelOk = $true }

    if (-not $sixelOk) {
        Write-Host "[Sixel not available -- your terminal does not report Sixel support.]" -ForegroundColor Yellow
        Write-Host "[Falling back to ANSI. Remove -Sixel flag to suppress this message.]" -ForegroundColor DarkGray
        Write-Host ""
        $Sixel = $false
    }
}

# ---- Dispatch ----
$ext = [IO.Path]::GetExtension($Path).ToLower()
$isVideo = @('.mp4','.mkv','.avi','.mov','.webm','.flv','.wmv','.ts') -contains $ext

if ($Sixel) {
    if ($isVideo) {
        $w = if ($Width) { $Width } else { 200 }
        & $py "$src\play_video.py" $Path -w $w -f $Fps -c $Colors
    } else {
        $w = if ($Width) { $Width } else { 300 }
        & "$src\show_img.ps1" -ImagePath $Path -MaxWidth $w -MaxColors $Colors
    }
} else {
    if ($isVideo) {
        if (-not $env:WT_SESSION -and -not ($env:TERM -match 'xterm|wezterm|foot')) {
            Write-Host "[Video needs a modern terminal (Windows Terminal, xterm, WezTerm). cmd.exe will not render correctly.]" -ForegroundColor Red
            Write-Host "[Install Windows Terminal: winget install Microsoft.WindowsTerminal]" -ForegroundColor DarkGray
            exit 1
        }
        $w = if ($Width) { $Width } else { 120 }
        & $py "$src\play_video.py" $Path -a -w $w -f $Fps
    } else {
        $w = if ($Width) { $Width } else { 150 }
        & $py "$src\show_img_ansi.py" $Path -w $w
    }
}
