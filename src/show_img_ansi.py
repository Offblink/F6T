"""ANSI 半块字符图片显示 — 零配置保底方案
用法: python show_img_ansi.py <image> [-w 150]
每个 ▄ 字符承载 2 像素（前景+背景 24bit 真彩色）

管线与视频路径完全一致:
  FFmpeg (缩放+解码) → raw RGB bytes → PIL frombytes → 编码 → sys.stdout.buffer.write
"""
import json
import subprocess
import sys
from PIL import Image


def encode_ansi(path, max_width=150):
    # ── 1. ffprobe: 获取原始尺寸 ──
    probe = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0",
         "-show_entries", "stream=width,height", "-of", "json", path],
        capture_output=True, text=True
    )
    info = json.loads(probe.stdout)["streams"][0]
    orig_w, orig_h = info["width"], info["height"]

    # ── 2. 计算输出尺寸（等比缩放 + 高度对齐偶数）──
    ratio = min(1.0, max_width / orig_w)
    out_w = int(orig_w * ratio)
    out_h = int(orig_h * ratio)
    out_h = max(out_h // 2 * 2, 2)

    # ── 3. FFmpeg 缩放 + 解码为 raw RGB24（与视频路径完全相同）──
    result = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path,
         "-vf", f"scale={out_w}:{out_h}",
         "-pix_fmt", "rgb24", "-f", "rawvideo", "-"],
        capture_output=True
    )

    # ── 4. 编码 ANSI（与视频 encode_ansi_data 完全相同）──
    img = Image.frombytes("RGB", (out_w, out_h), result.stdout)
    pixels = img.load()
    lines = []
    for y in range(0, out_h - 1, 2):
        line = ""
        for x in range(out_w):
            r1, g1, b1 = pixels[x, y]
            r2, g2, b2 = pixels[x, y + 1]
            line += f"\x1b[38;2;{r1};{g1};{b1}m\x1b[48;2;{r2};{g2};{b2}m\u2584"
        lines.append(line + "\x1b[0m")
    return ("\r\n".join(lines)).encode("utf-8")


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Display image in terminal via ANSI half-block")
    parser.add_argument("image", help="image file path")
    parser.add_argument("-w", "--width", type=int, default=150, help="max output width (default 150)")
    args = parser.parse_args()
    data = encode_ansi(args.image, args.width)
    sys.stdout.buffer.write(data)
    sys.stdout.buffer.flush()
