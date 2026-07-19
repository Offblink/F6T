# F6T — FFmpeg + Sixel → Terminal

> 在终端里看图、播视频。基于 Sixel 协议，用 FFmpeg 解码、Python 编码、stdout 直出。

```
fst video.mp4                     # 视频 → 终端
fst photo.jpg                      # 图片 → 终端
fst video.mp4 -Ansi                 # 零配置 ANSI 保底
fst video.mp4 -Width 300 -Fps 24    # 调参数
```

## 安装

```powershell
powershell -ExecutionPolicy Bypass -File install.ps1
```

依赖：Python 3 + Pillow + FFmpeg。`install.ps1` 自动检查并提示缺失项。

安装后：
- **PowerShell**：`fst` 函数写入 profile，新开即用
- **cmd.exe**：自动注册 `%LOCALAPPDATA%\F6T\bin` 到 PATH，新开即用
- 源文件拷贝到 `%LOCALAPPDATA%\F6T`，删掉 clone 的目录不受影响

> **注意** PowerShell 需允许脚本执行：
> ```powershell
> Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
> ```

## 用法

```
fst <文件> [-Ansi] [-Width N] [-Fps N] [-Colors N] [-Help]
```

`fst` 根据文件后缀自动区分图片/视频。非 Windows Terminal 环境自动切 ANSI 模式（可强制用 `-Ansi`）。

### 参数

| 参数 | 适用 | 默认值 | 说明 |
|---|---|---|---|
| `-Width` | 图/视频 | 图300, 视频200 | 输出宽度（高度等比） |
| `-Fps` | 视频 | 15 | 目标帧率 |
| `-Colors` | Sixel 模式 | 32 | 调色板颜色数 (8-256) |
| `-Ansi` | 全部 | 自动检测 | 切到 ANSI 半块字符模式 |
| `-Help` | — | — | 显示帮助 |

### 示例

```powershell
# 图片
fst C:\photo.jpg
fst C:\photo.jpg -Width 500 -Colors 64
fst C:\photo.jpg -Ansi                   # 零配置

# 视频
fst C:\video.mp4
fst C:\video.mp4 -Width 300 -Fps 24
fst C:\video.mp4 -Ansi -Width 100 -Fps 10  # 低配流畅
```

### 卸载

```powershell
fst-uninstall
```

清除 profile 中的函数、安装目录和 PATH 条目。

## 原理

```
FFmpeg 解码                Python 编码            终端渲染
─────────────            ─────────────           ─────────
video.mp4  →  rawvideo   →  Pillow 量化  →  Sixel 转义码  →  Windows Terminal
             rgb24 bytes     + Sixel 编码     (ESC P q ...)    / xterm / WezTerm
                                                 │
                             ANSI 备选:          ├  cmd /c type
                             每▄ = 2像素          │  (图片: 二进制文件→终端)
                             前景+背景真彩色      │
                                                 └  WriteConsole
                                                    (视频: 逐帧直写)
```

## 终端支持

| 终端 | Sixel | ANSI |
|---|---|---|
| Windows Terminal 1.22+ | ✅（需启用） | ✅ |
| xterm | ✅ | ✅ |
| WezTerm | ✅ | ✅ |
| foot | ✅ | ✅ |
| VS Code / Alacritty | ❌ | ✅ |
| ConEmu / cmd.exe | ❌ | ✅ |

Windows Terminal 启用 Sixel：`设置 → 呈现 → 启用 Sixel 图形支持`。

非 Windows Terminal 环境（cmd.exe、ConEmu 等）`fst` 会自动回退到 ANSI 模式，显示 `[Auto ANSI ...]` 提示。

## 对比 FFmpeg 原生的 iterm2 muxer

[quink](https://zhuanlan.zhihu.com/p/2051813744573953093)（FFmpeg 维护者）的方案是将 Sixel/iTerm2 编码写进 FFmpeg C 源码，零拷贝，性能极致。

F6T 是外部脚本调用 FFmpeg 管道，有进程间数据拷贝和 Pillow 量化开销。优点是不用编译 FFmpeg，任何环境跑。

## 踩坑记录

见 [`docs/pitfalls.md`](docs/pitfalls.md) — 8 个坑的完整复盘：色彩空间不兼容、控制台输出方式、PowerShell 子进程句柄、UTF-8 BOM、转义字符序列化、Python 路径冲突、旧 FFmpeg 无 HEVC 支持、ANSI 行尾残留。

## 限制

- 无音频
- Sixel 需终端支持（没开用 `-Ansi` 或等自动回退）
- Python 编码瓶颈：200px 约 15fps

## 文件结构

```
f6t/
├── README.md
├── install.ps1              # 安装脚本
├── .gitignore
├── bin/
│   └── fst.cmd              # cmd.exe 入口
├── src/
│   ├── fst.ps1              # 主入口（PS & cmd 共用）
│   ├── sixel_encoder.py     # Sixel 编码核心（支持文件和内存输入）
│   ├── play_video.py        # 视频播放器（复用 sixel_encoder）
│   ├── show_img.ps1         # Sixel 图片显示（cmd /c 直出二进制）
│   ├── show_img_ansi.ps1    # ANSI 图片显示（薄 wrapper）
│   └── show_img_ansi.py     # ANSI 图片编码（Python CLI）
├── docs/
│   ├── pitfalls.md          # 踩坑全记录
│   └── sixel-guide.md       # Sixel 协议科普
└── examples/
    └── demo.png
```

## License

MIT
