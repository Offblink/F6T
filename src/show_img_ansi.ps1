<#
.SYNOPSIS
    用 Unicode 半块字符 + ANSI 24bit 颜色在终端显示图片
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ImagePath,
    [int]$MaxWidth = 200
)
$pyExe = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $pyExe) { $pyExe = (Get-ChildItem "C:\Users\$env:USERNAME\AppData\Local\Programs\Python\Python3*\python.exe" -ErrorAction SilentlyContinue | Select-Object -First 1).FullName }
if (-not (Test-Path $pyExe)) { Write-Error "Python not found"; return }

# Write Python code to temp file with proper variable substitution
$pyCode = @'
from PIL import Image

img = Image.open(r"IMAGEPATH_PLACEHOLDER").convert("RGB")
w, h = img.size
MAXW = MAXW_PLACEHOLDER
if w > MAXW:
    ratio = MAXW / w
    w = MAXW
    h = int(h * ratio * 0.5)
    img = img.resize((w, h * 2), Image.LANCZOS)
else:
    h = h // 2 * 2
    img = img.resize((w, h), Image.LANCZOS)

pixels = img.load()
lines = []

for y in range(0, h, 2):
    line = ""
    for x in range(w):
        r1, g1, b1 = pixels[x, y]
        r2, g2, b2 = pixels[x, y+1]
        line += f"\x1b[38;2;{r1};{g1};{b1}m\x1b[48;2;{r2};{g2};{b2}m\u2584"
    lines.append(line + "\x1b[0m")

print("\n".join(lines))
'@

$pyCode = $pyCode.Replace("IMAGEPATH_PLACEHOLDER", $ImagePath)
$pyCode = $pyCode.Replace("MAXW_PLACEHOLDER", $MaxWidth)

$tmpPy = [System.IO.Path]::GetTempFileName() + ".py"
[System.IO.File]::WriteAllText($tmpPy, $pyCode)
& $pyExe $tmpPy
Remove-Item $tmpPy -Force
