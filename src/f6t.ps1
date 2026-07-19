<#
.SYNOPSIS
    F6T — FFmpeg + Sixel -> Terminal
    Display images and video in the terminal via Sixel or ANSI.
.DESCRIPTION
    Both PowerShell and cmd.exe compatible.
    PowerShell:  f6t <file> [-Ansi] [-Width N] ...
    cmd.exe:     f6t <file> [-Ansi] [-Width N] ...
#>
param(
    [string]$Path,
    [int]$Width,
    [int]$Res,
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

if ($Help -or $Path -eq "-h" -or $Path -eq "--help" -or $Path -eq "/?") {
    Write-Host @'
F6T -- FFmpeg + Sixel -> Terminal

Usage:  f6t <file> [-Sixel] [-Width N] [-Res N] [-Fps N] [-Colors N] [-Help]

  <file>        Image or video file path
  -Sixel        Use Sixel mode (requires Sixel-capable terminal)
  -Width N      Output width in characters (default: fits terminal)
  -Res N        Output width in pixels — higher = better quality (no cap)
  -Fps N        Target frame rate for video (default 15)
  -Colors N     Palette size for Sixel mode, 8-256 (default 32)
  -Help         Show this help

Default is ANSI half-block mode (works everywhere).
Width auto-fits your terminal window. Use -Width or -Res to override.
-Res allows higher decode resolution (e.g. -Res 720 for HD quality).
Use -Sixel in Windows Terminal 1.22+, xterm, WezTerm, or foot.

Examples:
  f6t photo.jpg                     # ANSI (universal)
  f6t photo.jpg -Sixel              # Sixel (high quality)
  f6t video.mp4                     # ANSI video, auto-fit
  f6t video.mp4 -Width 80           # ANSI video, smaller
  f6t video.mp4 -Res 480            # ANSI video, SD decode
  f6t photo.jpg -Res 720            # ANSI, HD decode quality

Uninstall:  f6t-uninstall  (PowerShell only)
'@
    exit 0
}
# ---- No input ----
if (-not $Path) {
    Write-Host "Usage: f6t <file> [-Ansi] [-Width N] [-Fps N] [-Colors N]"
    Write-Host "       f6t -Help"
    exit 0
}

# ---- Detect file type ----
$ext = [IO.Path]::GetExtension($Path).ToLower()
$isVideo = @('.mp4','.mkv','.avi','.mov','.webm','.flv','.wmv','.ts') -contains $ext

# ---- Auto-detect terminal width ----
function Get-TermWidth {
    try { return (Get-Host).UI.RawUI.WindowSize.Width - 4 }
    catch { try { return [Console]::WindowWidth - 4 } catch { return 120 } }
}

$explicitWidth = $Width
if (-not $Width) {
    $tw = Get-TermWidth
    if ($isVideo) {
        $Width = $tw
    } else {
        $cap = if ($Sixel) { 800 } else { 600 }
        $Width = [Math]::Min($tw, $cap)
    }
}

# ---- Resolution override ----
if ($Res) { $Width = $Res }

# ---- Sixel capability check ----
if ($Sixel) {
    $sixelOk = $false
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
if ($Sixel) {
    if ($isVideo) {
        & $py "$src\play_video.py" $Path -w $Width -f $Fps -c $Colors
    } else {
        & "$src\show_img.ps1" -ImagePath $Path -MaxWidth $Width -MaxColors $Colors
    }
} else {
    if ($isVideo) {
        if (-not $env:WT_SESSION -and -not ($env:TERM -match 'xterm|wezterm|foot')) {
            # Not in a modern terminal — auto-launch one
            $launchArgs = "& '$src\f6t.ps1' -Path '$Path'"
            if ($explicitWidth) { $launchArgs += " -Width $explicitWidth" }
            if ($Fps -and $Fps -ne 15) { $launchArgs += " -Fps $Fps" }
            if ($Res) { $launchArgs += " -Res $Res" }
            if (Get-Command wt.exe -ErrorAction SilentlyContinue) {
                Write-Host "[Video] Launching in Windows Terminal..." -ForegroundColor Yellow
                Start-Process wt.exe -ArgumentList "powershell -NoExit -NoProfile -ExecutionPolicy Bypass -Command `"$launchArgs`""
            } else {
                Write-Host "[Video] Launching in new PowerShell window..." -ForegroundColor Yellow
                Start-Process powershell.exe -ArgumentList "-NoExit -NoProfile -ExecutionPolicy Bypass -Command `"$launchArgs`""
            }
            exit 0
        }
        & $py "$src\play_video.py" $Path -a -w $Width -f $Fps
    } else {
        & $py "$src\show_img_ansi.py" $Path -w $Width
    }
}
