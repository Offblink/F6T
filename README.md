# F6T — FFmpeg + Sixel → Terminal

> 在终端里看图、播视频。基于 Sixel 协议，用 FFmpeg 解码、Python 编码、stdout 直出。

```
fst photo.jpg                     # 图片 → 终端（ANSI，零配置）
fst video.mp4                     # 视频 → 终端（ANSI，零配置）
fst photo.jpg -Sixel              # 图片 → Sixel 高清
fst video.mp4 -Res 480            # 指定解码分辨率
```

## 安装

```powershell
powershell -ExecutionPolicy Bypass -File install.ps1
```

依赖：Python 3 + Pillow + FFmpeg。`install.ps1` 自动检查并提示缺失项。

安装后：
- **PowerShell**：`fst` 函数写入 profile，新开即用
- **cmd.exe**：自动注册 `%LOCALAPPDATA%\F6T\bin` 到 PATH，新开即用
  - cmd.exe 播视频会自动拉起 Windows Terminal 窗口播放
- 源文件拷贝到 `%LOCALAPPDATA%\F6T`，删掉 clone 的目录不受影响

> **注意** PowerShell 需允许脚本执行：
> ```powershell
> Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
> ```

## 用法

```
fst <文件> [-Sixel] [-Width N] [-Res N] [-Fps N] [-Colors N] [-Help]
```

`fst` 根据文件后缀自动区分图片/视频。默认 ANSI 半块字符模式，无需任何配置。

### 参数

| 参数 | 适用 | 默认值 | 说明 |
|---|---|---|---|
| `-Width` | 图/视频 | 自动适配终端 | 输出宽度（高度等比） |
| `-Res` | 全部 | — | 输出宽度——无上限，突破默认 cap |
| `-Fps` | 视频 | 15 | 目标帧率 |
| `-Colors` | Sixel 模式 | 32 | 调色板颜色数 (8-256) |
| `-Sixel` | 全部 | 否 | 切到 Sixel 模式（需终端支持） |
| `-Help` | — | — | 显示帮助 |

### 示例

```powershell
# 图片（默认 ANSI，自动适配窗口宽度）
fst C:\photo.jpg
fst C:\photo.jpg -Sixel              # Sixel 高清
fst C:\photo.jpg -Width 500          # 指定宽度

# 视频（默认 ANSI，填满终端窗口，缩放终端时实时跟随）
fst C:\video.mp4
fst C:\video.mp4 -Width 80           # 小窗播放
fst C:\video.mp4 -Res 480            # 高分辨率解码
fst C:\video.mp4 -Sixel              # Sixel 模式
```

### 卸载

```powershell
fst-uninstall
```

清除 profile 函数、安装目录和 PATH 条目。

## 原理

```
FFmpeg 解码                          Python 编码                   终端渲染
─────────────            ─────────────           ─────────
video.mp4  →  rawvideo   →  Pillow 量化  →  Sixel 转义码  →  Windows Terminal
             rgb24 bytes     + Sixel 编码     (ESC P q ...)    / xterm / WezTerm
                                                 │
                             ANSI 备选:           ├  cmd /c type
                             每▄ = 2像素          │  (图片: 临时文件→终端)
                             前景+背景真彩色        │
                                                 └  sys.stdout
                                                    (视频: 逐帧直写)
```

## 终端支持

| 终端 | 默认 ANSI | Sixel |
|---|---|---|
| Windows Terminal | ✅ | 需终端支持 |
| xterm / WezTerm / foot | ✅ | ✅（自动检测） |
| VS Code / Alacritty | ✅ | ❌ |
| cmd.exe（图片） | ✅ | ❌ |
| cmd.exe（视频） | 自动拉起 WT | ❌ |

- 默认 ANSI 模式，所有现代终端通用
- `-Sixel` 会检测终端能力，不支持时自动回退并提示
- cmd.exe 视频自动拉起 Windows Terminal 播放

## 特性

- **自动适配终端尺寸**：图片和视频默认填满终端窗口，缩放窗口/ctrl+- 实时跟随
- **视频高度动态适配**：根据终端行数自动调整，不滚动、不闪烁
- **标题栏进度条**：视频播放进度显示在窗口标题栏，不占用屏幕空间
- **cmd.exe 自动拉起 WT**：在 cmd.exe 中播视频自动打开 Windows Terminal
- **Python 路径智能探测**：自动跳过 WindowsApps 存根，支持 pythoncore 和 Python3 安装
- **Sixel 能力检测**：`-Sixel` 在无支持终端会自动回退并提示
- **一键卸载**：`fst-uninstall` 清理所有痕迹

## 对比 FFmpeg 原生的 iterm2 muxer

[quink](https://zhuanlan.zhihu.com/p/2051813744573953093)（FFmpeg 维护者）的方案是将 Sixel/iTerm2 编码写进 FFmpeg C 源码，零拷贝，性能极致。

F6T 是外部脚本调用 FFmpeg 管道，有进程间数据拷贝和 Pillow 量化开销。优点是不用编译 FFmpeg，任何环境跑。

## 踩坑记录

见 [`docs/pitfalls.md`](docs/pitfalls.md) — 20+ 个坑的完整复盘。

## 限制

- 无音频
- Sixel 需终端支持（`-Sixel` 模式下自动检测并回退）
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
│   ├── play_video.py        # 视频播放器（复用 sixel_encoder，支持实时缩放）
│   ├── show_img.ps1         # Sixel 图片显示（cmd /c type 直出二进制）
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
