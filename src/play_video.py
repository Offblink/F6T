
"""
Terminal Video Player — Sixel 终端视频播放器
用法: python play-video.py <video.mp4> [-w 200] [-f 15] [-c 32]

原理: FFmpeg 解码 → Python Sixel 编码 → 逐帧直写控制台
需要: Python 3 + Pillow + FFmpeg
终端: Windows Terminal 1.22+ (启用 Sixel) / xterm / WezTerm / foot
"""

import subprocess
import sys
import os
import math
import time
import json
import argparse
from PIL import Image

# ── Console Output (bypass stdout capture) ─────────────────────────
STD_OUTPUT_HANDLE = -11
if sys.platform == "win32":
    import ctypes
    from ctypes import wintypes
    kernel32 = ctypes.windll.kernel32
    
    def write_console(data: bytes):
        """用 WriteFile 直写控制台——不做字符处理，适合 Sixel 二进制"""
        handle = kernel32.GetStdHandle(STD_OUTPUT_HANDLE)
        written = wintypes.DWORD(0)
        buf = (ctypes.c_char * len(data))(*data)
        kernel32.WriteFile(handle, buf, len(data), ctypes.byref(written), None)
else:
    def write_console(data: bytes):
        sys.stdout.buffer.write(data)
        sys.stdout.buffer.flush()


# ── Sixel Encoder (per-frame) ──────────────────────────────────────
def sixel_char(bits):
    return chr(0x3F + (bits & 0x3F))

def encode_sixel_data(rgb_bytes, w, h, max_colors=32):
    img = Image.frombytes("RGB", (w, h), rgb_bytes)
    if max_colors < 256:
        img = img.quantize(colors=max_colors, method=Image.Quantize.MEDIANCUT)
    img = img.convert("RGB")
    pixels = img.load()
    
    color_to_idx = {}
    palette = []
    for y in range(h):
        for x in range(w):
            c = pixels[x, y]
            if c not in color_to_idx:
                color_to_idx[c] = len(palette)
                palette.append(c)
    
    parts = ["\x1bPq"]
    for i, (r, g, b) in enumerate(palette):
        parts.append(f"#{i};2;{r};{g};{b}")
    
    num_bands = math.ceil(h / 6)
    for band in range(num_bands):
        y0 = band * 6
        freq = {}
        for y in range(y0, min(y0 + 6, h)):
            for x in range(w):
                c = pixels[x, y]
                freq[c] = freq.get(c, 0) + 1
        sorted_colors = sorted(freq.keys(), key=lambda c: -freq[c])
        
        for color in sorted_colors:
            ci = color_to_idx[color]
            parts.append(f"#{ci}")
            for x in range(w):
                bits = 0
                for dy in range(6):
                    y = y0 + dy
                    if y < h and pixels[x, y] == color:
                        bits |= (1 << dy)
                parts.append(sixel_char(bits))
            parts.append("$")
        parts.append("-")
    
    parts.append("\x1b\\")
    return "".join(parts).encode("latin-1")

# ── ANSI Half-Block Encoder (per-frame) ─────────────────────────────
def encode_ansi_data(rgb_bytes, w, h):
    """用 Unicode ▄ + ANSI 24bit 真彩色编码一帧，每字符承载 2 像素"""
    img = Image.frombytes("RGB", (w, h), rgb_bytes)
    pixels = img.load()
    lines = []
    for y in range(0, h - 1, 2):
        line = ""
        for x in range(w):
            r1, g1, b1 = pixels[x, y]
            r2, g2, b2 = pixels[x, y + 1]
            line += f"\x1b[38;2;{r1};{g1};{b1}m\x1b[48;2;{r2};{g2};{b2}m\u2584"
        lines.append(line + "\x1b[0m")
    return ("\r\n".join(lines)).encode("utf-8")


# ── Video Probe ────────────────────────────────────────────────────
def get_video_info(path):
    """获取视频宽高和帧率，兼容新旧 ffprobe"""
    # 方法1: ffprobe JSON
    r = subprocess.run(
        ["ffprobe", "-v", "quiet", "-print_format", "json",
         "-show_streams", path],
        capture_output=True, text=True
    )
    if r.returncode == 0 and r.stdout.strip():
        try:
            info = json.loads(r.stdout)
            vs = next(s for s in info["streams"] if s["codec_type"] == "video")
            w, h = vs["width"], vs["height"]
            fps_s = vs.get("r_frame_rate", "30/1")
            if "/" in fps_s:
                a, b = fps_s.split("/", 1)
                fps = int(a) / int(b)
            else:
                fps = float(fps_s)
        except:
            pass
    
    # 方法2: ffmpeg 直接读
    r2 = subprocess.run(
        ["ffmpeg", "-i", path],
        capture_output=True, text=True
    )
    stderr = r2.stderr
    w = h = fps = dur = None
    for line in stderr.split("\n"):
        if "Stream #" in line and "Video:" in line:
            # 找分辨率
            import re
            m = re.search(r'(\d{2,4})x(\d{2,4})', line)
            if m:
                w, h = int(m.group(1)), int(m.group(2))
            # 找帧率
            m = re.search(r'(\d+\.?\d*)\s*fps', line)
            if m:
                fps = float(m.group(1))
            m = re.search(r'(\d+\.?\d*)\s*tbr', line)
            if m and not fps:
                fps = float(m.group(1))
        if "Duration:" in line:
            m = re.search(r'Duration:\s*(\d+):(\d+):(\d+)\.(\d+)', line)
            if m:
                dur = int(m.group(1))*3600 + int(m.group(2))*60 + int(m.group(3)) + int(m.group(4))/100
    
    if not w or not h:
        raise RuntimeError(f"无法解析视频信息。ffmpeg 输出:\n{stderr[:500]}")
    return {"width": w, "height": h, "fps": fps or 30, "duration": dur or 0}


# ── Player ─────────────────────────────────────────────────────────
def play_video(path, max_width=200, target_fps=15, max_colors=32, mode="sixel"):
    info = get_video_info(path)
    orig_w, orig_h = info["width"], info["height"]
    
    if orig_w > max_width:
        ratio = max_width / orig_w
        out_w = max_width
        out_h = int(orig_h * ratio) // 2 * 2
    else:
        out_w, out_h = orig_w, orig_h // 2 * 2
    fps = min(target_fps, info["fps"]) if info["fps"] > 0 else target_fps
    frame_time = 1.0 / fps
    frame_bytes = out_w * out_h * 3
    
    # 片头信息
    mode_label = "ANSI" if mode == "ansi" else "Sixel"
    write_console(b"\x1b[2J\x1b[H")
    lines = [
        f"  Terminal Video Player ({mode_label})",
        f"  File: {os.path.basename(path)}",
        f"  Source: {orig_w}x{orig_h} @ {info['fps']:.1f}fps",
        f"  Output: {out_w}x{out_h} @ {fps:.0f}fps, {max_colors} colors",
        f"  Press Ctrl+C to stop",
        f"",
    ]
    for line in lines:
        write_console((line + "\r\n").encode())
    time.sleep(1.5)
    
    # 清屏准备
    write_console(b"\x1b[2J\x1b[H")
    
    # FFmpeg 解码管道（不限速，Python 控帧率）
    ffmpeg_cmd = [
        "ffmpeg", "-v", "error",
        "-i", path,
        "-vf", f"scale={out_w}:{out_h},fps={fps}",
        "-pix_fmt", "rgb24",
        "-f", "rawvideo", "-"
    ]
    
    proc = subprocess.Popen(ffmpeg_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    
    frame_count = 0
    total_frames = int(info["duration"] * fps) if info["duration"] else None
    
    try:
        while True:
            t_start = time.perf_counter()
            
            raw = proc.stdout.read(frame_bytes)
            if len(raw) < frame_bytes:
                break
            
            if mode == "ansi":
                frame_data = encode_ansi_data(raw, out_w, out_h)
            else:
                frame_data = encode_sixel_data(raw, out_w, out_h, max_colors)
            
            write_console(b"\x1b[H")
            write_console(frame_data)
            
            frame_count += 1
            
            # 进度条
            if total_frames:
                pct = min(frame_count / total_frames * 100, 100)
                bar_w = 30
                filled = int(bar_w * frame_count / total_frames)
                bar = "█" * filled + "░" * (bar_w - filled)
                prog = f"  {bar} {pct:.0f}% [{frame_count}/{total_frames}]"
            else:
                prog = f"  [{frame_count} frames]"
            write_console((prog).encode())
            write_console(b"\x1b[K")  # 清行尾
            
            # 帧率控制
            elapsed = time.perf_counter() - t_start
            if elapsed < frame_time:
                time.sleep(frame_time - elapsed)
    
    except KeyboardInterrupt:
        pass
    finally:
        proc.terminate()
        try:
            _, stderr = proc.communicate(timeout=2)
        except:
            proc.kill()
            _, stderr = proc.communicate()
        write_console(b"\x1b[2J\x1b[H")
        if frame_count == 0 and stderr:
            err = stderr.decode("utf-8", errors="replace").strip().split("\n")[-3:]
            write_console(f"\r\nFFmpeg error ({frame_count} frames):\r\n".encode())
            for line in err:
                if line.strip():
                    write_console(f"  {line.strip()}\r\n".encode())
        else:
            write_console(f"\r\nDone. {frame_count} frames.\r\n".encode())


# ── CLI ────────────────────────────────────────────────────────────
if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Terminal Video Player (Sixel / ANSI)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python play-video.py video.mp4               # Sixel, 200px, 15fps
  python play-video.py video.mp4 -a             # ANSI (universal), 120px
  python play-video.py video.mp4 -w 300 -f 24   # Sixel HD
  python play-video.py video.mp4 -a -w 80 -f 8  # ANSI minimal
        """
    )
    parser.add_argument("video", help="video file path")
    parser.add_argument("-a", "--ansi", action="store_true", help="ANSI half-block mode (no Sixel required)")
    parser.add_argument("-w", "--width", type=int, default=None, help="output width (default: 200 sixel, 120 ansi)")
    parser.add_argument("-f", "--fps", type=int, default=15, help="target fps (default 15)")
    parser.add_argument("-c", "--colors", type=int, default=32, help="max colors, sixel only (default 32)")
    args = parser.parse_args()
    
    if not os.path.exists(args.video):
        print(f"Error: file not found: {args.video}")
        sys.exit(1)
    
    mode = "ansi" if args.ansi else "sixel"
    if args.width is None:
        args.width = 120 if mode == "ansi" else 200
    
    play_video(args.video, max_width=args.width, target_fps=args.fps, max_colors=args.colors, mode=mode)
