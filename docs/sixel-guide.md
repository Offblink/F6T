# Sixel 终端图形协议详解

> 在命令行里显示高清图片和视频——不需要 X11，不需要 GUI，只靠 stdout。

---

## 1. 这是什么

**Sixel**（six pixels，六个像素）是一种将位图编码为可打印字符序列的终端图形协议。它的核心思路极其简单：

> 把图片的每 6 个纵向像素编码成一个 ASCII 字符（`?` `0x3F` ~ `~` `0x7E`），通过转义序列包裹输出到终端。终端识别到转义序列后，不把内容当文本显示，而是解码渲染成图像。

```
文本终端看到的：  ESC P q #0;2;255;0;0 ~?@ABC... ESC \
实际渲染结果：    [一个红色方块]
```

它诞生于 1980 年代的 DEC 打印机/终端（VT240、LA50），2010 年代后被现代终端模拟器重新实现，成为 **终端内联图片** 事实上的三大标准之一。

---

## 2. 和另外两大协议的对比

| | Sixel | iTerm2 Inline | Kitty Graphics |
|---|---|---|---|
| **出现时间** | 1983 (DEC) | ~2014 | 2019 |
| **编码方式** | 6 像素/字符 + 调色板 | base64 PNG/JPEG | 分块传输 + 压缩 |
| **传输效率** | 中等（原始像素编码） | 高（标准图片压缩） | 最高（支持 zlib） |
| **动画支持** | 无（可多帧模拟） | 无 | 原生支持 APNG/GIF |
| **终端兼容性** | xterm, mlterm, Windows Terminal, WezTerm, foot | iTerm2, WezTerm, warp | Kitty, WezTerm, Konsole |
| **协议复杂度** | 极简 | 简单 | 复杂 |

**Sixel 的独特优势**：
- 协议最简洁——核心转义序列不到 10 种
- xterm 内置支持（最广泛部署的终端）
- Windows Terminal 原生支持（1.22+）

---

## 3. 编码原理

### 3.1 六个像素一个字符

一个 Sixel 字符表示 **一列 6 个纵向像素**的点阵状态：

```
像素 0 (最上) → bit 0 (LSB)
像素 1        → bit 1
像素 2        → bit 2
像素 3        → bit 3
像素 4        → bit 4
像素 5 (最下) → bit 5 (MSB)

字符 = 0x3F + bitmask
```

6 位共 64 种组合，恰好映射到 ASCII 的 `?` (0x3F) 到 `~` (0x7E)：

| bits | 字符 | 含义 |
|---|---|---|
| 000000 (0) | `?` | 空列（无像素） |
| 000001 (1) | `@` | 仅顶部一点 |
| 111111 (63) | `~` | 满列 6 像素 |

**示意**：一个 6×6 的 "F" 字母，Sixel 编码如下：

```
列: 0  1  2  3  4  5
   █  █  █  █  █  █    bits=111111 → '~'
   █                          bits=000001 → '@'
   █  █  █  █  █         bits=111110 → '}'
   █                          bits=000001 → '@'
   █                          bits=000001 → '@'
                              bits=000000 → '?'

Sixel 数据: ~@}@@?
```

### 3.2 转义序列结构

```
ESC P q  <调色板>  <光栅属性>  <sixel数据>  ESC \
```

#### 完整示例

```
\x1bPq                           # DCS (Device Control String) 开始
#0;2;255;0;0                     # 颜色 0 = RGB(255,0,0) 红
#1;2;0;255;0                     # 颜色 1 = RGB(0,255,0) 绿
#2;2;0;0;255                     # 颜色 2 = RGB(0,0,255) 蓝
"100;50;1                        # 光栅: 宽100 高50 (逻辑像素)
#0~?@ABC...$                     # 颜色0的像素数据，$回到行首
#1???~???$                       # 颜色1的像素数据
#2~~~~~?$                        # 颜色2的像素数据
-                                # 移到下一个6像素带
#0...
\x1b\\                           # ST (String Terminator) 结束
```

### 3.3 颜色处理

Sixel 使用**调色板寻址**，不支持逐像素 RGB：

```
#<id>;2;<R>;<G>;<B>    — 定义调色板颜色
#<id>                   — 在像素数据中引用颜色
```

渲染时**逐色逐遍叠加**：同一 band 内，每种颜色画一遍，`$` 回到行首，下一种颜色叠在上面。先画的颜色会被后画的覆盖，所以通常**从最多像素的颜色开始画**以减少覆盖开销。

### 3.4 控制字符速查

| 字符 | 含义 |
|---|---|
| `#N;2;R;G;B` | 定义调色板颜色 N |
| `#N` | 切换当前颜色为 N |
| `$` | 回车——光标回到当前 band 最左列 |
| `-` | 换行——光标移到下一个 band |
| `!N<char>` | 重复符——`!10~` = 输出 10 个 `~` |
| `"W;H;D` | 光栅属性（宽/高/像素宽高比） |

---

## 4. 终端支持情况

| 终端 | 支持 | 备注 |
|---|---|---|
| **Windows Terminal** | ✅ 1.22+ | 要在设置里开 `experimental.sixelGraphics` |
| **xterm** | ✅ 原生 | 编译时需开启 `--enable-sixel-graphics` |
| **WezTerm** | ✅ | 开箱即用 |
| **foot** | ✅ | Wayland 下推荐方案 |
| **mlterm** | ✅ | 老牌多语言终端 |
| **iTerm2** | ❌ | 有自己的 Inline Images Protocol，不支持 Sixel |
| **Kitty** | ❌ | 有自己的 Graphics Protocol |
| **Alacritty** | ❌ | 明确不计划支持 |
| **macOS Terminal** | ❌ | — |
| **VS Code 终端** | ❌ | xterm.js 不支持 |

---

## 5. 超越静态图片：命令行播视频

这就是知乎文章 [quink](https://zhuanlan.zhihu.com/p/2051813744573953093) 的核心玩法——为 FFmpeg 写了一个 iterm2 muxer，把视频帧逐帧编码为终端图片协议，通过 `stdout` 输出：

```bash
ffmpeg -re -i video.mp4 -f iterm2 -tmux 1 -
```

- `-re`：按视频原速播放
- `-f iterm2`：输出格式 = iTerm2 Inline Images Protocol
- `-tmux 1`：穿透 tmux 的多路复用过滤
- `-`：输出到 stdout

**Sixel 同样可以做**：只要把每一帧编码为 Sixel 并逐帧输出，清除上一帧（或滚动），就能在终端里"播放"视频。只是没有音频——这方案解决的不是播放器替代问题，而是：

> 在远程服务器 / 跳板机 / 容器里，**不下载文件、不搭 Web 服务、不折腾端口转发**，只靠 SSH 里的 stdout 就能快速确认视频内容。

### 其他终端视频播放方案

```bash
mpv --vo=kitty video.mp4      # mpv 的 Kitty 协议后端
mpv --vo=sixel video.mp4       # mpv 的 Sixel 后端（需编译）
chafa --watch video.gif        # chafa 的字符画动画
```

---


## 6. F6T 项目

F6T (FFmpeg + Sixel → Terminal) 基于 Sixel 协议，实现了终端图片显示和视频播放。

```
f6t/src/
├── sixel_encoder.py    # Sixel 编码核心（Pillow → Sixel）
├── play_video.py       # 视频播放器（FFmpeg pipe → 逐帧编码）
├── show_img.ps1        # 图片显示
└── show_img_ansi.ps1   # ANSI 备选（Unicode 半块 + 真彩色）
```

### 技术链路

```
视频/图片文件
    ↓ FFmpeg 解码 → rawvideo rgb24 字节
    ↓ Pillow 量化 (median cut, 32-256 色)
    ↓ Python Sixel 编码
    ↓ cmd /c type（图片）/ WriteConsole（视频逐帧）
    ↓ Windows Terminal / xterm / WezTerm 渲染
```

### 关键细节

1. **调色板量化**：Sixel 使用调色板寻址（非逐像素 RGB）。Pillow `MEDIANCUT` 量化到 32-64 色，效果损失小但数据量降到 1/10。

2. **cmd /c type vs WriteConsole**：图片用 `cmd /c type` 输出二进制到终端更稳定；视频逐帧用 `WriteConsole` 配合 `\x1b[H` 光标归位覆盖。

3. **色彩空间兼容**：DEC 标准规定 `;1;` = RGB，但 Windows Terminal 和 xterm 实际使用 `;2;` = RGB。必须以实际实现为准。

4. **逐 band 逐色渲染**：每个 6 像素 band 内，从出现频率最高的颜色开始绘制，后绘颜色覆盖先绘颜色，减少重绘次数。

### 限制

- **无音频**：纯图形协议。
- **无交互**：纯输出，不能点击/缩放。
- **性能**：Python 编码为瓶颈，200px 约 15fps。

---

## 7. 参考资源

- [Sixel 协议规范 (VT330/VT340 手册)](https://vt100.net/docs/vt3xx-gp/)
- [libsixel — 参考实现](https://github.com/saitoha/libsixel)
- [Windows Terminal Sixel 支持公告](https://devblogs.microsoft.com/commandline/windows-terminal-preview-1-22/)
- [FFmpeg + iTerm2 在命令行播视频 (quink@知乎)](https://zhuanlan.zhihu.com/p/2051813744573953093)
- [mpv 终端视频播放](https://mpv.io/manual/stable/#video-output-drivers)
- [F6T 项目主页](https://github.com)

---

*F6T 项目 · 2026-06-27*
