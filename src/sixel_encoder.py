"""Sixel 终端图像编码器

用法:
  python sixel_encoder.py <image> <max_w> <max_colors> [output.bin]
  python -c "from sixel_encoder import encode_sixel_bytes; ..."
"""
import math
import sys
from PIL import Image


def _sixel_char(bits: int) -> str:
    """将 6-bit 值编码为 Sixel 字符 (0x3F + bits)"""
    return chr(0x3F + (bits & 0x3F))


def encode_sixel_bytes(rgb_bytes: bytes, w: int, h: int, max_colors: int = 32) -> bytes:
    """从原始 RGB 字节编码 Sixel 数据（内存输入，供视频逐帧调用）

    Args:
        rgb_bytes: w*h*3 原始 RGB 字节
        w, h: 图像宽高
        max_colors: 调色板最大颜色数 (8-256)

    Returns:
        Sixel 二进制数据（可直接写入控制台）
    """
    img = Image.frombytes("RGB", (w, h), rgb_bytes)
    if max_colors < 256:
        img = img.quantize(colors=max_colors, method=Image.Quantize.MEDIANCUT)
    img = img.convert("RGB")
    pixels = img.load()

    # 构建调色板
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
    parts.append(f'"{w};{h};1')

    # 6 行一组带状编码
    num_bands = (h + 5) // 6
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
                    yy = y0 + dy
                    if yy < h and pixels[x, yy] == color:
                        bits |= (1 << dy)
                parts.append(_sixel_char(bits))
            parts.append("$")
        parts.append("-")
    parts.append("\x1b\\")
    return "".join(parts).encode("latin-1")


def encode_sixel_file(path: str, max_w: int, max_colors: int) -> bytes:
    """从图片文件编码 Sixel 数据（磁盘文件输入）

    Args:
        path: 图片文件路径
        max_w: 最大输出宽度（等比缩放）
        max_colors: 调色板颜色数 (8-256)

    Returns:
        Sixel 二进制数据
    """
    img = Image.open(path).convert("RGB")
    w, h = img.size
    if w > max_w:
        ratio = max_w / w
        w = max_w
        h = int(h * ratio)
        img = img.resize((w, h), Image.LANCZOS)
    return encode_sixel_bytes(img.tobytes(), w, h, max_colors)


# 兼容旧调用方的别名
encode_sixel = encode_sixel_file


if __name__ == "__main__":
    path = sys.argv[1]
    max_w = int(sys.argv[2])
    max_colors = int(sys.argv[3])
    out = sys.argv[4] if len(sys.argv) > 4 else None

    data = encode_sixel_file(path, max_w, max_colors)

    if out:
        with open(out, "wb") as f:
            f.write(data)
        print(f"OK {max_w}px {max_colors}c -> {out}", file=sys.stderr)
    else:
        sys.stdout.buffer.write(data)
        sys.stdout.buffer.flush()
