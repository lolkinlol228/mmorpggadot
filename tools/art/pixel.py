"""Small pixel-art toolkit: text maps, shaded shapes, outlines. Used by gen_art.py."""
from PIL import Image

OUTLINE = (26, 22, 34, 255)


def blank(w: int, h: int) -> Image.Image:
    return Image.new("RGBA", (w, h), (0, 0, 0, 0))


def from_map(text: str, pal: dict, width: int | None = None) -> Image.Image:
    rows = [r for r in text.strip("\n").split("\n")]
    w = width or max(len(r) for r in rows)
    img = blank(w, len(rows))
    for y, r in enumerate(rows):
        for x, ch in enumerate(r):
            c = pal.get(ch)
            if c is not None:
                img.putpixel((x, y), c if len(c) == 4 else c + (255,))
    return img


def shade(ramp: list, nx: float, ny: float, bias: float = 0.0) -> tuple:
    """Light from top-left. nx, ny in [-1, 1] relative to shape centre."""
    v = 0.55 - 0.35 * nx - 0.5 * ny + bias
    i = max(0, min(len(ramp) - 1, int(v * len(ramp))))
    c = ramp[i]
    return c if len(c) == 4 else c + (255,)


def ellipse(img, cx, cy, rx, ry, ramp, clip=None, bias=0.0):
    for y in range(img.height):
        for x in range(img.width):
            nx, ny = (x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry
            if nx * nx + ny * ny <= 1.0 and (clip is None or clip(x, y)):
                img.putpixel((x, y), shade(ramp, nx, ny, bias))


def rect(img, x0, y0, x1, y1, ramp, bias=0.0):
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    rx, ry = max(1, (x1 - x0) / 2), max(1, (y1 - y0) / 2)
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if 0 <= x < img.width and 0 <= y < img.height:
                img.putpixel((x, y), shade(ramp, (x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry, bias))


def put(img, x, y, c):
    if 0 <= x < img.width and 0 <= y < img.height:
        img.putpixel((x, y), c if len(c) == 4 else c + (255,))


def erase(img, pts):
    for x, y in pts:
        if 0 <= x < img.width and 0 <= y < img.height:
            img.putpixel((x, y), (0, 0, 0, 0))


def outline(img, color=OUTLINE):
    """1px outline around every opaque pixel (4-neighbourhood)."""
    src = img.copy()
    for y in range(img.height):
        for x in range(img.width):
            if src.getpixel((x, y))[3]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                xx, yy = x + dx, y + dy
                if 0 <= xx < img.width and 0 <= yy < img.height and src.getpixel((xx, yy))[3] > 200:
                    img.putpixel((x, y), color)
                    break
    return img


def line(img, x0, y0, x1, y1, c):
    n = max(abs(x1 - x0), abs(y1 - y0), 1)
    for i in range(n + 1):
        put(img, round(x0 + (x1 - x0) * i / n), round(y0 + (y1 - y0) * i / n), c)


def hstack(frames):
    w = sum(f.width for f in frames)
    h = max(f.height for f in frames)
    out = blank(w, h)
    x = 0
    for f in frames:
        out.alpha_composite(f, (x, h - f.height))
        x += f.width
    return out


def flip_h(img):
    return img.transpose(Image.FLIP_LEFT_RIGHT)
