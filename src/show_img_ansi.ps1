<#
.SYNOPSIS
    Display image in terminal via ANSI half-block characters
.DESCRIPTION
    Thin wrapper around show_img_ansi.py — each ▄ character = 2 pixels with 24bit true color.
    Zero config; works in any terminal (VS Code, Alacritty, ConEmu, etc.)
#>
param(
    [Parameter(Mandatory=$true)]
    [string]$ImagePath,
    [int]$MaxWidth = 150
)

$pyExe = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $pyExe) {
    $pyExe = (Get-ChildItem "C:\Users\$env:USERNAME\AppData\Local\Programs\Python\Python3*\python.exe" -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
}
if (-not (Test-Path $pyExe)) {
    Write-Error "Python not found. Install from https://python.org"
    exit 1
}

$pyScript = Join-Path $PSScriptRoot "show_img_ansi.py"
& $pyExe $pyScript $ImagePath -w $MaxWidth
