<#
.SYNOPSIS
    Display image in terminal via Sixel protocol
#>
param(
    [Parameter(Mandatory=$true)]
    [string]$ImagePath,
    [int]$MaxWidth = 500,
    [int]$MaxColors = 32
)

if (-not (Test-Path $ImagePath)) {
    Write-Error "File not found: $ImagePath"
    return
}

$pyExe = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $pyExe) { $pyExe = (Get-ChildItem "C:\Users\$env:USERNAME\AppData\Local\Programs\Python\Python3*\python.exe" -ErrorAction SilentlyContinue | Select-Object -First 1).FullName }
if (-not (Test-Path $pyExe)) { Write-Error "Python not found"; return }
$pyScript = Join-Path $PSScriptRoot "sixel_encoder.py"
$tmpBin = Join-Path $env:TEMP "_sixel_tmp.bin"

$err = & $pyExe $pyScript $ImagePath $MaxWidth $MaxColors $tmpBin 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "Python error: $err"
    return
}

Write-Host ($err -replace '\s+$','')

cmd /c type $tmpBin
Write-Host ""

Remove-Item $tmpBin -Force -ErrorAction SilentlyContinue
