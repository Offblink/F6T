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

## 9. kernel32.WriteFile 在 ConPTY 中吞 ESC 字符

**现象**：Windows Terminal 中播视频，ANSI 转义序列全部显示为可见文本：`[38;2;37;37;37m▄[38;2;82;82;82m▄...`，终端疯狂滚动，每"像素"都是乱码。

**排查**：视频输出链路是 `python play_video.py → kernel32.WriteFile(GetStdHandle(-11))`。`GetStdHandle(-11)` 在 WT 的 ConPTY 中返回 pipe 端句柄，`WriteFile` 写入的数据经 ConPTY 转发时 ESC 字符 (`0x1B`) 被剥离或替换为 `?`。

**根因**：ConPTY 对 `WriteFile` 写入的二进制数据可能有转义过滤机制。`WriteFile` 对大数据块的写入行为与 `WriteConsole` 不同，后者才正确触发 ConPTY 的转义序列处理。

**方案**：放弃 `kernel32.WriteFile`，统一用 `sys.stdout.buffer.write()` + `sys.stdout.buffer.flush()`。Python 的 stdout 通过 ConPTY 时 ESC 不会被吞。

---

## 10. PowerShell here-string 嵌套限制

**现象**：`$fstFunc = @"..."@` 内的帮助文本用 `Write-Host @"..."@`，解析时报大量语法错误。

**根因**：PowerShell 的 `@"..."@`（双引号 here-string）不可嵌套。内层 `"@` 直接终止外层 here-string，后续 PS 代码裸露在外导致解析失败。

**方案**：内层改用 `@'...'@`（单引号 here-string）。`'@` 不匹配外层的 `"@`，安全嵌套。

---

## 11. PowerShell 不支持方法参数中的 inline if

**现象**：`$Width = [Math]::Min($tw, if ($Sixel) { 500 } else { 300 })` 解析失败。

**根因**：PowerShell 的表达式语法不允许 `if` 语句出现在方法调用的参数位置。

**方案**：先算出来再传参：
```powershell
$cap = if ($Sixel) { 500 } else { 300 }
$Width = [Math]::Min($tw, $cap)
```

---

## 12. Python 路径：硬编码版本号 + `ErrorActionPreference Stop`

**现象**：`install.ps1` 在 Python 3.14 环境直接崩溃——`$pyCandidates` 只枚举 3.11-3.13，首个路径不存在触发 `CommandNotFoundException`，`$ErrorActionPreference = "Stop"` 导致脚本终止。

**根因**：两个设计缺陷叠加：(1) 硬编码版本号，任何新版本都崩；(2) `Stop` 模式让一个无害的"路径不存在"变成致命错误。

**方案**：
- `Test-Path` 预检候选路径，不存在就跳过
- glob `Python3*` 和 `pythoncore-3*` 目录，按版本降序取第一个
- 降级 `ErrorActionPreference` 为 `Continue`
- PATH 回退时用 `Get-Command -All` 并跳过 `WindowsApps` 存根

---

## 13. `cmd /c` 直出管道在 ConPTY 中不可靠

**现象**：尝试去掉临时文件，改成 `cmd /c "python encoder.py ..."` 直出，结果 Sixel 图片无渲染。

**根因**：Pitfall #2 已验证的"`cmd /c type` 可靠"方案被当作"可优化的临时文件"，替换为 `cmd /c python | stdout`。但 `cmd /c` 启动的子进程通过 ConPTY 的管道行为与 `type` 不同，Sixel 二进制数据未正确到达终端渲染层。

**教训**：已验证的 workaround 不要轻易"优化"。临时文件确实是 hack，但它能 work。

---

## 14. Windows Terminal 1.24 Sixel 设置不可见

**现象**：WT 1.24 设置 UI 中找不到 Sixel 开关，手动写 `experimental.enableSixel: true` 到 settings.json 也不生效。

**排查**：WT 1.22 引入 Sixel 为实验特性，需手动开启。1.24 移除了 UI 开关但可能保留了 JSON key——然而手动添加后仍不渲染，说明该 key 已失效或实现有 bug。

**方案**：不依赖 WT 的 Sixel。默认走 ANSI，`-Sixel` 检测终端自报的 env（`$env:TERM` / `$env:TERM_PROGRAM`），不信任手动修改的 JSON。xterm/WezTerm/foot 用户自动放行。

---

## 15. Sixel 能力检测的误判

**现象**：手动给 WT settings.json 加了 `experimental.enableSixel: true` 后，`-Sixel` 检测读 JSON 认为支持 → 输出 Sixel 数据 → 终端不渲染 → 用户看到的是静默失败。

**根因**：JSON 里的 setting 是手动加的，不代表终端真的支持。检测逻辑信任了不可靠的数据源。

**方案**：只信任终端自己设置的 env 变量（`TERM`、`TERM_PROGRAM`），不读配置文件。检测不到就回退 ANSI + 明确提示。

---

## 16. PS 5.1 不支持 `??` null-coalescing 运算符

**现象**：`[Environment]::GetEnvironmentVariable("Path", "User") ?? ""` 在 PS 5.1 报语法错误。

**根因**：`??` 是 PowerShell 7+ 的特性，PS 5.1（Windows 自带）不认。

**方案**：
```powershell
$val = [Environment]::GetEnvironmentVariable("Path", "User")
if (-not $val) { $val = "" }
```

---

## 17. 图片 Sixel 模式"无输出"——不是 bug，是终端不支持

**现象**：`fst photo.jpg -Sixel` 在 cmd.exe / 旧 WT 中静默无输出，用户以为坏了。

**根因**：Sixel 数据正确生成并写入终端，但终端不支持 Sixel 时二进制转义序列被忽略/丢弃，没有任何可见渲染。

**方案**：默认改为 ANSI。`-Sixel` 加能力检测（见 #15），不满足时明确提示并回退。

---


---

## 18. `total_frames` 未定义 NameError

**现象**：`play_video.py` 播到第一个进度条检查时崩溃：`NameError: name 'total_frames' is not defined`。

**根因**：进度条逻辑引用了 `total_frames` 但从未赋值。`get_video_info()` 已返回 `duration` 字段，只需 `int(duration * fps)`。

**方案**：
```python
total_frames = int(info["duration"] * fps) if info["duration"] else 0
```

---

## 19. ANSI 图片编码"只显示上半部分"

**现象**：`show_img_ansi.py` 对大图缩放后只渲染上半截，下半截直接消失。

**根因**：缩放逻辑把高度 `h` 改成字符行数（`h * ratio * 0.5`），但渲染循环 `range(0, h, 2)` 仍把 `h` 当像素高度，导致只遍历一半像素。

**方案**：统一缩放——先算像素高度（`h = int(h * ratio)`），偶数化（`h // 2 * 2`），一次 `resize`。渲染循环基于像素高度，全程一致。

---

## 20. `fst.ps1` dispatch 丢失 `else` 导致图片无输出

**现象**：`fst photo.jpg` 在 PowerShell 中静默无输出。

**根因**：PowerShell 解析 `} else {` 时，`}` 配给外层 `if ($Sixel)` 而非内层 `if ($isVideo)`，导致 ANSI 图片分支被吞进视频分支内。图片是 `$isVideo=False` → 两个分支都不执行 → 无输出。

**方案**：显式闭合内层再写外层 `else`：
```powershell
        }    # closes if ($isVideo)
    }        # closes if ($Sixel) body
} else {     # else for if ($Sixel)
```

---

## 21. 视频 `max_h = 60` 硬限制分辨率

**现象**：ctrl+- 缩字后视频清晰度不变，始终糊。

**根因**：`_compute_dims` 硬编码 `max_h = 60`（像素行 → 30 字符行）。终端再宽，高度被压死，宽高比把宽度拖下来。16:9 视频在 200 列终端 → 112 行像素 → 被截到 60 → 宽度从 200 缩到 106。

**方案**：去掉硬编码，动态获取终端行数：`max_h = terminal_rows * 2`（ANSI 每字符 2 像素）。

---

## 22. 进度条占行导致视频滚动闪烁

**现象**：去掉 `max_h=60` 后视频填满终端，但底部进度条让总输出超出 → 滚动 → 闪烁。F11 全屏不闪（终端更高 → 不超界）。

**根因**：`\x1b[H` 只归位不清屏。帧 + 进度条 > 终端行数时自动滚动。

**方案**：进度条移到标题栏（`\x1b]0;title\x07` OSC 转义序列）。零占用，视频完整填满终端。

---

## 23. cmd.exe 拉起 WT 时传错终端宽度

**现象**：cmd.exe 跑 `fst video.mp4` → WT 打开 → 视频只用了一半宽度。

**根因**：`fst.ps1` 在 cmd.exe 测出宽度（如 120），写进 WT 的启动参数。WT 实际 200 列，但 `-Width 120` 已固定，跳过自动检测。

**方案**：区分"用户显式指定"和"自动检测"的 Width。只传前者给 WT 子进程，后者让 WT 自己检测。用 `$explicitWidth` 变量隔离。

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
| ConPTY 吞 ESC | 🔴 | `WriteFile` → `sys.stdout`；conpty ≠ 真控制台 |
| here-string 嵌套 | 🟡 | 双层字符串用 `@"..."@` 套 `@'...'@` |
| inline if in method args | 🟡 | PS 不允许，先算再传参 |
| Python 路径硬编码 | 🔴 | glob 替代枚举，`Test-Path` 预检 |
| `cmd /c` 直出不可靠 | 🔴 | 已验证的 workaround 不要轻易"优化" |
| WT Sixel 设置不可见 | 🟡 | 不依赖 UI/json，信终端自报 env |
| 能力检测误判 | 🟡 | 不读配置文件做检测 |
| PS 5.1 `??` 不支持 | 🟡 | 用 `if` 替代 |
| Sixel 静默失败 | 🟡 | 默认 ANSI + 能力检测 + 明确提示 |
| `total_frames` 未定义 | 🟡 | 变量使用前检查是否赋值 |
| ANSI 图片半截渲染 | 🔴 | 缩放后高单位要一致（像素 vs 字符行） |
| PS 花括号歧义 | 🔴 | `} else {` 能配错层，显式分行闭合 |
| `max_h=60` 限制分辨率 | 🟡 | 硬编码上限是过早优化，动态测更好 |
| 进度条导致滚动闪烁 | 🟡 | 标题栏 OSC 可替代占行 UI |
| cmd.exe 传错终端宽 | 🟡 | 跨进程不要传自检值，让子进程重测 |

*记录于 2026-06-27 · 更新于 2026-07-19 · F6T 项目*
