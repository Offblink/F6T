import json, math, sys
from PIL import Image

def encode_sixel(img_path, max_w, max_colors):
    img = Image.open(img_path).convert("RGB")
    w, h = img.size
    if w > max_w:
        ratio = max_w / w
        w = max_w
        h = int(h * ratio)
        img = img.resize((w, h), Image.LANCZOS)
    if max_colors < 256:
        img = img.quantize(colors=max_colors, method=Image.Quantize.MEDIANCUT)
    img = img.convert("RGB")
    pixels = img.load()

    cmap = {}
    pal = []
    for y in range(h):
        for x in range(w):
            c = pixels[x, y]
            if c not in cmap:
                cmap[c] = len(pal)
                pal.append(c)

    def sc(bits):
        return chr(0x3F + (bits & 0x3F))

    parts = ["\033Pq"]
    for i, (r, g, b) in enumerate(pal):
        parts.append(f"#{i};2;{r};{g};{b}")
    parts.append(f'"{w};{h};1')

    for band in range((h + 5) // 6):
        y0 = band * 6
        freq = {}
        for y in range(y0, min(y0 + 6, h)):
            for x in range(w):
                c = pixels[x, y]
                freq[c] = freq.get(c, 0) + 1
        for color in sorted(freq, key=lambda c: -freq[c]):
            ci = cmap[color]
            parts.append(f"#{ci}")
            for x in range(w):
                bits = 0
                for dy in range(6):
                    y = y0 + dy
                    if y < h and pixels[x, y] == color:
                        bits |= (1 << dy)
                parts.append(sc(bits))
            parts.append("$")
        parts.append("-")
    parts.append("\033\\")
    return "".join(parts).encode("latin-1")

if __name__ == "__main__":
    path = sys.argv[1]
    max_w = int(sys.argv[2])
    max_colors = int(sys.argv[3])
    out = sys.argv[4] if len(sys.argv) > 4 else None
    
    data = encode_sixel(path, max_w, max_colors)
    
    if out:
        with open(out, "wb") as f:
            f.write(data)
        print(f"OK {max_w}px {max_colors}c -> {out}", file=sys.stderr)
    else:
        sys.stdout.buffer.write(data)
        sys.stdout.buffer.flush()
