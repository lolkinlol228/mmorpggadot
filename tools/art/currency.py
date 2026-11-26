"""Coin icons 32x32 (copper, silver, gold, platinum shard) + small 16x16 HUD versions.
Lit stacks of coins drawn with shade.py so they match the rest of the art."""
from PIL import Image
from shade import Canvas, Mat

METALS = [
    ("copper", (196, 112, 64)),
    ("silver", (196, 204, 216)),
    ("gold", (236, 190, 74)),
]


def coin_stack(color, n=3):
    c = Canvas(26, 26)
    m = Mat(color, spec=0.9)
    rim = Mat(tuple(int(v * 0.75) for v in color), spec=0.5)
    for i in range(n):
        y = 18 - i * 3
        c.cylinder(13 + (i % 2) * 1.5 - 0.7, 8, y, y + 2, rim, cap_m=m, cap_ry=3.2, z=i * 3)
    top = 18 - (n - 1) * 3
    for x in range(10, 16):                                   # stamped mark on the top coin
        c.px(x + (n - 1) % 2, top, 20, (0, -0.2, 1), rim)
    return c.render()


def shard():
    """Platinum 'Shard of Fortune': a faceted rhombus crystal with a sparkle."""
    c = Canvas(26, 26)
    m = Mat((200, 232, 246), spec=1.0)
    cx, cy, rx, ry = 13, 12.5, 8.5, 11.5
    normals = {(0, 0): (-0.7, -0.6, 0.5), (1, 0): (0.5, -0.7, 0.55), (0, 1): (-0.5, 0.55, 0.65), (1, 1): (0.7, 0.6, 0.4)}
    for y in range(26):
        for x in range(26):
            dx, dy = (x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry
            if abs(dx) + abs(dy) <= 1.0:
                inner = abs(dx) + abs(dy) <= 0.45
                n = (0, 0, 1) if inner else normals[(int(dx > 0), int(dy > 0))]
                c.px(x, y, 1, n, m)
    img = c.render()
    for (x, y) in ((11, 7), (12, 6), (10, 8), (12, 8), (11, 9)):
        img.putpixel((x + 3, y + 3), (255, 255, 255, 255))
    return img

def sheet():
    icons = [coin_stack(col, 3) for _, col in METALS] + [shard()]
    out = Image.new("RGBA", (32 * len(icons), 32), (0, 0, 0, 0))
    for i, ic in enumerate(icons):
        out.alpha_composite(ic, (i * 32 + (32 - ic.width) // 2, (32 - ic.height) // 2))
    return out
