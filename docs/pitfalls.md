# F6T 踩坑全记录

开发过程中遇到的每个障碍、排查过程和最终方案。

---

## 1. Sixel 色彩空间：`;1;` vs `;2;`

**现象**：图片颜色全反/发白/只剩轮廓。

**排查**：DEC 标准规定 `#<id>;<space>;<R>;<G>;<B>` 中 `<space>` 取值：
- `0` 或省略 = HLS
- `1` = RGB
- `2` = CMY

最初用 `;2;`，显示"一片黄"（CMY 色彩空间）。换成 DEC 标准的 `;1;`，变成"白白的只有轮廓"（HLS 色彩空间）。

**根因**：Windows Terminal 和 xterm 不跟 DEC 标准——它们把 `;1;` 当 HLS，`;2;` 当 RGB。libsixel 等主流实现也都用 `;2;` 表示 RGB。

**方案**：用 `;2;`，早期"一片黄"是因为转义字符被多一层引号破坏了（见第 5 条），修复转义后 `;2;` 正确渲染。

---

## 2. WriteConsole vs cmd /c type

**现象**：PowerShell 中调用 `kernel32!WriteFile` 输出 Sixel 数据，终端要么不渲染，要么渲染异常（过曝/留白）。

**排查过程**：
1. 手写最小 Sixel 二进制文件 `sixel_diag.bin`
2. `cmd /c type sixel_diag.bin` → 正常渲染 ✅
3. 同样的字节通过 `WriteFile` API 输出 → 异常 ❌

**根因假说**：
- `GetStdHandle(-11)` 在 PowerShell 进程中拿到的句柄可能指向 ConPTY 的 pipe 端而非真实控制台
- `WriteFile` 对大数据块的写入行为与 `type` 的逐块输出不同，可能触发 ConPTY 的缓冲区限制或转义过滤

**方案**：图片场景改用 `python encoder.py img.jpg w c tmp.bin && cmd /c type tmp.bin`，让 `type` 命令直接输出二进制到终端。视频场景仍用 `WriteFile`（帧数据量小，已验证可用）。

---

## 3. PowerShell 子进程的控制台句柄

**现象**：`powershell -File script.ps1` 中 `GetStdHandle` 拿到的句柄不指向用户的可见终端窗口。

**根因**：`powershell -File` 创建子进程。子进程的 `STD_OUTPUT_HANDLE` 可能被重定向到父进程的管道或新的控制台缓冲区，与用户看到的窗口不同。

**方案**：用 `. script.ps1`（dot-source）或 `& script.ps1`（调用运算符）在当前会话中执行，避免子进程。这两种方式继承当前控制台句柄。

---

## 4. 编码问题：UTF-8 vs GBK

**现象**：中文输出乱码 `鏂囦欢`。

**根因**：Windows PowerShell 5.1 默认用系统 ANSI 代码页（简体中文 = GBK/CP936）解释脚本文件。Python 输出的 UTF-8 中文在 GBK 终端中显示为乱码。

**方案**：
- `.ps1` 文件必须保存为 **UTF-8 with BOM**（`\xEF\xBB\xBF`）——BOM 告诉 PowerShell 这是 UTF-8
- Python 脚本中的用户可见文本改用英文
- 或调用前 `chcp 65001` 切到 UTF-8 代码页

---

## 5. 转义字符在 .ps1 内嵌 Python 中的序列化

**现象**：Python 代码模板中的 `\x1b` 经过多层编码后变成字面量 `\033` 或直接消失。

**完整链路**：
```
Python eval 写 .ps1 → Python 字面量 "\x1b" 被解释为 ESC 字节 (0x1B)
    → 写入 .ps1 文件（UTF-8 + BOM）
    → PowerShell 读取 @'...'@ here-string（单引号，不展开）
    → PowerShell .Replace() 参数占位符
    → WriteAllText 写到 .py 临时文件（UTF-8 无 BOM）
    → Python 读取 .py 并执行
```

当尝试用 `"\\033"` 替代时，`\\` 在 Python 源里是转移后的单反斜杠，`033` 是字面量——整个变成了 `\033`（6 个字符）而非 ESC 字符。

**方案**：把 Sixel 编码逻辑抽成独立 `sixel_encoder.py` 文件，不再内嵌在 `.ps1` 中。`.py` 文件直接用 `\033` 八进制转义或 `\x1b` 十六进制转义，正常执行。

---

## 6. Python 路径：WindowsApps 存根拦截

**现象**：`python` 命令有时命中 `C:\Users\...\WindowsApps\python.exe`（Microsoft Store 存根），打开应用商店而非运行 Python。

**根因**：Windows 10/11 预装的 App Execution Alias。即使真正的 Python 在 PATH 前面，PowerShell 的命令解析可能优先命中 App Alias。

**方案**：写死绝对路径 `C:\Users\<user>\AppData\Local\Programs\Python\Python313\python.exe`。安装脚本自动探测。

---

## 7. FFmpeg 版本与 HEVC/H.265

**现象**：`play-video.py` 输出 0 帧，无报错。

**排查**：
```
ffmpeg -i video.mp4
→ Video: none (hvc1 / 0x31637668), 960x544: unknown codec
```

**根因**：用户环境的 FFmpeg 是 2013 年构建的（版本 N-55702），不支持 HEVC/H.265 解码。

**方案**：安装新版 FFmpeg（`winget install ffmpeg`）。2013 版本能解 H.264，所以用内置测试视频 (`testsrc`) 仍然能播。

---

## 8. ANSI 模式的行尾残留

**现象**：ANSI 模式播视频时，上一帧的底部会残留到下一帧。

**根因**：`\x1b[H` 只归位光标不擦除。新帧行数少时旧行留在屏幕上。

**方案**：ANSI 每帧后加 `\x1b[J`（擦除从光标到屏底），下一帧再 `\x1b[H` 归位。

---

## 总结

| 坑 | 级别 | 核心教训 |
|---|---|---|
| 色彩空间 ;1;/;2; | 🔴 | DEC 标准 ≠ 实际实现，以 xterm/libsixel 为准 |
| WriteFile vs type | 🔴 | 终端二进制输出，`cmd /c type` 比 API 稳定 |
| PowerShell 子进程句柄 | 🟡 | 别用 `powershell -File`，用 `&` 或 dot-source |
| UTF-8 BOM | 🟡 | Windows PS 5.1 写脚本必带 BOM |
| 内嵌 Python 转义 | 🔴 | .ps1 里不要内嵌代码，抽独立 .py |
| WindowsApps 存根 | 🟡 | 写死 Python 绝对路径 |
| 旧 FFmpeg 无 HEVC | 🟡 | 检测 + 提示升级 |

*记录于 2026-06-27 · F6T 项目*
