# F6T — Install Script
# Run: powershell -ExecutionPolicy Bypass -File install.ps1
# 
# Installs F6T by adding the `fst` function to your PowerShell profile
# and ensuring Python + Pillow dependencies are met.

$ErrorActionPreference = "Stop"
Write-Host "=== F6T Installer ===" -ForegroundColor Cyan

# 1. Find Python
$pyCandidates = @(
    "C:\Users\$env:USERNAME\AppData\Local\Programs\Python\Python313\python.exe",
    "C:\Users\$env:USERNAME\AppData\Local\Programs\Python\Python312\python.exe",
    "C:\Users\$env:USERNAME\AppData\Local\Programs\Python\Python311\python.exe",
    "python.exe"
)

$python = $null
foreach ($c in $pyCandidates) {
    $result = & $c --version 2>$null
    if ($LASTEXITCODE -eq 0) {
        $python = (Get-Command $c).Source
        break
    }
}

if (-not $python) {
    Write-Error "Python not found. Install from https://python.org"
    exit 1
}
Write-Host "Python: $python" -ForegroundColor Green

# 2. Check Pillow
$pillowOk = & $python -c "from PIL import Image" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "Installing Pillow..." -ForegroundColor Yellow
    & $python -m pip install Pillow
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

# 4. Get install directory
$installDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $installDir) { $installDir = "." }
$installDir = (Resolve-Path $installDir).Path
Write-Host "Source: $installDir" -ForegroundColor Green

# 5. Add to profile
$profileDir = Split-Path $PROFILE -Parent
if (-not (Test-Path $profileDir)) {
    New-Item -ItemType Directory -Force -Path $profileDir | Out-Null
}

$fstFunc = @"

##### F6T — FFmpeg + Sixel -> Terminal #####
function global:fst {
    param(
        [Parameter(Mandatory=`$true)]
        [string]`$Path,
        [int]`$Width,
        [int]`$Fps = 15,
        [int]`$Colors = 32,
        [switch]`$Ansi
    )
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
            & `$src\show_img_ansi.ps1 -ImagePath `$Path -MaxWidth `$w
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

# Check if already installed
$existing = if (Test-Path $PROFILE) { Get-Content $PROFILE -Raw } else { "" }
if ($existing -match "##### F6T") {
    Write-Host "F6T already in profile. Updating..." -ForegroundColor Yellow
    $lines = $existing -split "`r`n"
    $start = -1; $end = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match "##### F6T") { $start = $i }
        if ($start -ge 0 -and $i -gt $start -and $lines[$i] -match "^##### ") { $end = $i - 1; break }
    }
    if ($end -lt 0) { $end = $lines.Count - 1 }
    $newContent = ($lines[0..($start-1)] + $fstFunc.Trim() -split "`r`n" + $lines[($end+1)..($lines.Count-1)]) -join "`r`n"
    [IO.File]::WriteAllText($PROFILE, $newContent)
} else {
    Add-Content $PROFILE "`r`n$fstFunc"
}

Write-Host "Profile updated: $PROFILE" -ForegroundColor Green
Write-Host ""
Write-Host "=== Done! Restart PowerShell, then: ===" -ForegroundColor Cyan
Write-Host "  fst $installDir\examples\demo.png" -ForegroundColor White
Write-Host "  fst C:\path\to\video.mp4" -ForegroundColor White
Write-Host "  fst C:\path\to\image.jpg -Ansi" -ForegroundColor White
