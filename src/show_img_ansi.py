"""ANSI 半块字符图片显示 — 零配置保底方案
用法: python show_img_ansi.py <image> [-w 150]
每个 ▄ 字符承载 2 像素（前景+背景 24bit 真彩色）
"""
import sys
from PIL import Image


def encode_ansi(path, max_width=150):
    img = Image.open(path).convert("RGB")
    w, h = img.size
    if w > max_width:
        ratio = max_width / w
        w = max_width
        h = max(int(h * ratio * 0.5), 1)
        img = img.resize((w, h * 2), Image.LANCZOS)
    else:
        h = max(h // 2 * 2, 2)
        img = img.resize((w, h), Image.LANCZOS)

    pixels = img.load()
    lines = []
    for y in range(0, h, 2):
        line = ""
        for x in range(w):
            r1, g1, b1 = pixels[x, y]
            r2, g2, b2 = pixels[x, y + 1]
            line += f"\x1b[38;2;{r1};{g1};{b1}m\x1b[48;2;{r2};{g2};{b2}m\u2584"
        lines.append(line + "\x1b[0m")
    return "\n".join(lines)


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Display image in terminal via ANSI half-block")
    parser.add_argument("image", help="image file path")
    parser.add_argument("-w", "--width", type=int, default=150, help="max output width (default 150)")
    args = parser.parse_args()
    print(encode_ansi(args.image, args.width))
