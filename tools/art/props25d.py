"""2.5D (3/4 top-down) props: every object shows a top face + front face, roofs have a horizontal
ridge (front slope visible), eaves cast a shadow band on the wall, recesses for doors/windows.
Light comes from the upper-left. Ground shadows are generated separately by shadow_of()."""
import math
import random
from PIL import Image
from pixel import blank, put, outline, ellipse

OUT = (22, 18, 28)
WOOD = [(52, 34, 26), (80, 54, 38), (112, 78, 52), (146, 106, 72), (176, 136, 96)]
STONE = [(48, 46, 58), (70, 68, 82), (96, 94, 108), (126, 124, 138), (158, 156, 170)]
SLATE = [(30, 32, 48), (44, 48, 68), (62, 68, 92), (84, 92, 120), (112, 120, 150)]
CLAY = [(58, 30, 30), (86, 42, 38), (116, 60, 48), (146, 84, 62), (176, 112, 80)]
PLASTER = [(112, 98, 82), (138, 124, 102), (164, 150, 124), (186, 174, 148)]
IRON = [(32, 34, 42), (54, 58, 70), (84, 90, 104), (120, 126, 140)]
LIGHT = [(214, 140, 60), (255, 196, 104), (255, 232, 168)]
GOLD = [(140, 96, 32), (204, 158, 70), (246, 214, 130)]


def box(img, x0, y0, x1, y1, ramp, k):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            put(img, x, y, ramp[k])


def top_front(img, x0, x1, y_top, top_h, y_bottom, ramp, front_k=1, top_k=3):
    """A block seen in 3/4: lighter top face (top_h rows) above a darker front face."""
    box(img, x0, y_top, x1, y_top + top_h - 1, ramp, top_k)
    box(img, x0, y_top + top_h, x1, y_bottom, ramp, front_k)
    for y in range(y_top, y_bottom + 1):
        put(img, x0, y, ramp[min(len(ramp) - 1, (top_k if y < y_top + top_h else front_k) + 1)])
    for x in range(x0, x1 + 1):
        put(img, x, y_top + top_h, ramp[max(0, front_k - 1)])


# ---------------- buildings ----------------

def _roof(img, x0, x1, y_ridge, y_eave, ramp, back=5):
    """Horizontal ridge: thin dark back slope above, big front slope down to the eave."""
    for y in range(y_ridge - back, y_ridge):
        for x in range(x0 + 2, x1 - 1):
            put(img, x, y, ramp[1])
    for x in range(x0 + 1, x1):
        put(img, x, y_ridge, ramp[4])
        put(img, x, y_ridge + 1, ramp[3])
    rows = y_eave - y_ridge - 2
    for y in range(y_ridge + 2, y_eave + 1):
        r = (y - y_ridge - 2)
        band = r // 4
        depth = r / max(1, rows)
        base_k = 3 if depth < 0.35 else (2 if depth < 0.75 else 1)
        for x in range(x0, x1 + 1):
            k = base_k
            if r % 4 == 3:
                k = max(0, k - 1)                      # shingle row edge
            elif (x + band * 3) % 6 == 0:
                k = max(0, k - 1)                      # shingle seams, staggered
            put(img, x, y, ramp[k])
    for x in range(x0, x1 + 1):
        put(img, x, y_eave, ramp[0])


def _window(img, x, y, w=8, h=8, lit=True):
    box(img, x - 1, y - 1, x + w, y + h, WOOD, 1)                  # frame
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            c = LIGHT[2] if yy < y + 2 else LIGHT[1]
            if not lit:
                c = (28, 32, 46)
            if xx == x:                                              # recess shadow on the left
                c = LIGHT[0] if lit else (20, 22, 32)
            put(img, xx, yy, c)
    for yy in range(y, y + h):
        put(img, x + w // 2, yy, WOOD[1])
    for xx in range(x, x + w):
        put(img, xx, y + h // 2, WOOD[1])
    for xx in range(x - 2, x + w + 2):                               # sill: top face + front
        put(img, xx, y + h + 1, WOOD[4])
        put(img, xx, y + h + 2, WOOD[2])


def building(w=76, roof=SLATE, sign=None, forge=False, dormer=True, seed=0):
    rnd = random.Random(seed)
    roof_h = 40
    wall_h = 34
    found_h = 6
    h = roof_h + wall_h + found_h
    img = blank(w, h)
    wx0, wx1 = 5, w - 6
    wy0, wy1 = roof_h, roof_h + wall_h - 1
    # wall: plaster with timber frame
    for y in range(wy0, wy1 + 1):
        for x in range(wx0, wx1 + 1):
            k = 2 if (x * 7 + y * 3 + rnd.randint(0, 3)) % 13 else 1
            put(img, x, y, PLASTER[k])
    for bx in (wx0, wx0 + (wx1 - wx0) // 3, wx0 + 2 * (wx1 - wx0) // 3, wx1 - 1):
        box(img, bx, wy0, bx + 1, wy1, WOOD, 1)
        for y in range(wy0, wy1 + 1):
            put(img, bx, y, WOOD[2])
    box(img, wx0, wy0 + 14, wx1, wy0 + 15, WOOD, 1)
    # eave shadow band: makes the roof read as overhanging
    for y in range(wy0, wy0 + 4):
        for x in range(wx0, wx1 + 1):
            c = img.getpixel((x, y))
            put(img, x, y, tuple(int(v * (0.55 + 0.1 * (y - wy0))) for v in c[:3]))
    # door recess + step
    dx = w // 2 - 7
    box(img, dx - 1, wy1 - 20, dx + 14, wy1, WOOD, 0)
    for y in range(wy1 - 19, wy1 + 1):
        for x in range(dx, dx + 14):
            k = 2 if (x - dx) % 4 else 1
            if x == dx:
                k = 0
            put(img, x, y, WOOD[k])
    put(img, dx + 11, wy1 - 9, GOLD[2])
    # windows
    if forge:
        box(img, wx0 + 4, wy1 - 14, wx0 + 18, wy1, STONE, 0)
        for x in range(wx0 + 5, wx0 + 18):
            put(img, x, wy1 - 1, (255, 150, 50))
            put(img, x, wy1 - 2, (255, 200, 90) if x % 2 else (230, 100, 40))
            put(img, x, wy1 - 3, (160, 60, 30))
        _window(img, wx1 - 17, wy0 + 6)
    else:
        _window(img, wx0 + 6, wy0 + 6)
        _window(img, wx1 - 15, wy0 + 6)
    if sign:
        box(img, dx - 13, wy0 + 6, dx - 4, wy0 + 13, WOOD, 3)
        for x in range(dx - 13, dx - 3):
            put(img, x, wy0 + 14, WOOD[1])
        for (sx, sy) in sign:
            put(img, dx - 12 + sx, wy0 + 7 + sy, GOLD[2])
    # foundation: top face + front
    top_front(img, 2, w - 3, wy1 + 1, 2, h - 1, STONE, front_k=1, top_k=3)
    for x in range(2, w - 2, 7):
        put(img, x, h - 2, STONE[0])
    for x in range(dx - 2, dx + 16):                                  # door step
        put(img, x, wy1 + 1, STONE[4])
    # roof with ridge, dormer and chimney
    _roof(img, 0, w - 1, 7, roof_h, roof)
    if dormer:
        cx = w // 2
        box(img, cx - 7, 18, cx + 6, 30, PLASTER, 2)
        _window(img, cx - 4, 21, 7, 6)
        for y in range(13, 19):
            half = 9 - (18 - y)
            for x in range(cx - half, cx + half):
                put(img, x, y, roof[3 if x < cx else 2])
    ch = w - 18
    top_front(img, ch, ch + 8, 0, 3, 16, STONE, front_k=2, top_k=4)
    box(img, ch + 2, 0, ch + 6, 1, STONE, 0)                           # chimney mouth
    outline(img, OUT)
    return img


# ---------------- town furniture ----------------

def tower():
    img = blank(26, 52)
    top_front(img, 2, 23, 6, 8, 51, STONE, front_k=2, top_k=4)        # big top platform + face
    for cx in (2, 9, 16):                                               # merlons seen from above
        top_front(img, cx, cx + 5, 0, 3, 7, STONE, front_k=2, top_k=4)
    for y in range(18, 51, 6):
        for x in range(3, 23):
            put(img, x, y, STONE[1])
        off = 0 if (y // 6) % 2 else 5
        for x in range(3 + off, 23, 10):
            for yy in range(y, min(y + 6, 51)):
                put(img, x, yy, STONE[1])
    box(img, 10, 26, 15, 33, IRON, 0)
    put(img, 12, 29, LIGHT[1])
    outline(img, OUT)
    return img


def wall_h():
    img = blank(16, 26)
    top_front(img, 0, 15, 0, 6, 25, STONE, front_k=2, top_k=4)          # walkway on top
    for y in range(11, 26, 5):
        for x in range(16):
            put(img, x, y, STONE[1])
    for y in range(6, 26, 5):
        off = 0 if (y // 5) % 2 else 8
        for yy in range(y, min(y + 5, 26)):
            put(img, (off + 3) % 16, yy, STONE[1])
    for x in (2, 9):                                                     # crenels on the top edge
        box(img, x, 0, x + 4, 1, STONE, 3)
    return img


def wall_v():
    img = blank(14, 16)
    box(img, 0, 0, 13, 15, STONE, 3)
    for y in (5, 11):
        for x in range(1, 13):
            put(img, x, y, STONE[2])
    for y in range(0, 16, 6):
        put(img, 6, y + 2, STONE[2])
    for y in range(16):
        put(img, 0, y, STONE[2])
        put(img, 13, y, STONE[1])
    return img


def lamp():
    img = blank(12, 36)
    top_front(img, 2, 9, 30, 2, 35, STONE, 1, 3)                        # base block
    box(img, 5, 10, 6, 30, IRON, 1)
    put(img, 5, 12, IRON[3])
    for y in range(1, 4):                                               # pyramid cap
        for x in range(6 - y, 6 + y):
            put(img, x, y, IRON[2] if x < 6 else IRON[1])
    box(img, 2, 4, 9, 10, IRON, 1)
    box(img, 3, 5, 8, 9, LIGHT, 1)
    box(img, 3, 5, 8, 6, LIGHT, 2)
    outline(img, OUT)
    return img


def well():
    img = blank(34, 44)
    for px in (5, 27):
        box(img, px, 8, px + 1, 30, WOOD, 2)
    _roof(img, 1, 32, 5, 14, CLAY, back=4)
    box(img, 7, 16, 26, 16, WOOD, 3)
    ellipse(img, 17, 32, 15, 6, STONE[2:])                              # rim top face
    ellipse(img, 17, 32, 10.5, 3.6, [(14, 20, 34), (22, 34, 54)])       # water
    for y in range(33, 43):                                              # front of the cylinder
        for x in range(3, 31):
            nx = (x - 17) / 14
            if nx * nx + ((y - 33) / 18) ** 2 <= 1.2 and y > 32 + 6 * math.sqrt(max(0, 1 - nx * nx)) - 1:
                k = 2 if nx < -0.3 else (1 if nx < 0.4 else 0)
                if (y % 4 == 0) or ((x + (y // 4) * 3) % 7 == 0):
                    k = max(0, k - 1)
                put(img, x, y, STONE[k])
    outline(img, OUT)
    return img


def stall():
    img = blank(58, 50)
    for px in (5, 51):
        box(img, px, 10, px + 1, 46, WOOD, 2)
    for y in range(2, 16):                                              # sloped awning seen from above
        for x in range(1 + (15 - y) // 4, 57 - (15 - y) // 4):
            stripe = (x // 7) % 2
            base = (150, 50, 44) if stripe else (204, 188, 152)
            f = 0.75 + 0.25 * (16 - y) / 14
            put(img, x, y, tuple(int(v * f) for v in base))
    for x in range(1, 57, 7):
        put(img, x + 3, 16, (150, 50, 44))
    top_front(img, 2, 55, 30, 5, 44, WOOD, front_k=1, top_k=4)          # counter: top + front
    goods = [(200, 40, 50), (60, 120, 210), (90, 180, 90), (220, 180, 60), (180, 120, 220)]
    for i, gx in enumerate(range(6, 54, 6)):
        top_front(img, gx, gx + 2, 27, 1, 31, [goods[i % 5]] * 2 + [tuple(min(255, v + 50) for v in goods[i % 5])] * 3, 0, 2)
    outline(img, OUT)
    return img


def chest():
    img = blank(22, 20)
    top_front(img, 1, 20, 2, 6, 18, WOOD, front_k=2, top_k=4)
    for x in (5, 16):
        box(img, x, 2, x + 1, 18, IRON, 2)
    box(img, 1, 8, 20, 8, IRON, 1)
    box(img, 9, 9, 12, 12, GOLD, 1)
    put(img, 10, 10, GOLD[2])
    outline(img, OUT)
    return img


def barrel():
    img = blank(16, 20)
    for y in range(5, 19):
        for x in range(1, 15):
            nx = (x - 7.5) / 7
            if abs(nx) <= 1 - 0.15 * ((y - 12) / 7) ** 2:
                k = 3 if nx < -0.4 else (2 if nx < 0.3 else 1)
                put(img, x, y, WOOD[k])
    ellipse(img, 7.5, 5, 6.5, 3, WOOD[2:])                              # lid top
    for x in range(1, 15):
        put(img, x, 9, IRON[1])
        put(img, x, 15, IRON[1])
    outline(img, OUT)
    return img


def crate():
    img = blank(16, 18)
    top_front(img, 1, 14, 1, 5, 16, WOOD, front_k=2, top_k=4)
    for i in range(10):
        put(img, 2 + i, 7 + round(i * 0.9), WOOD[1])
    box(img, 1, 6, 14, 6, WOOD, 1)
    outline(img, OUT)
    return img


def anvil():
    img = blank(22, 16)
    top_front(img, 1, 20, 1, 3, 6, IRON, front_k=1, top_k=3)
    box(img, 8, 7, 13, 10, IRON, 1)
    top_front(img, 4, 17, 11, 1, 15, IRON, front_k=1, top_k=2)
    outline(img, OUT)
    return img


def board():
    img = blank(30, 36)
    for px in (4, 24):
        box(img, px, 10, px + 1, 35, WOOD, 2)
    top_front(img, 1, 28, 2, 2, 24, WOOD, front_k=2, top_k=4)           # board with a top edge
    box(img, 1, 0, 28, 1, WOOD, 3)
    notes = [(4, 6, 7, 6), (14, 5, 8, 7), (6, 15, 6, 5), (17, 15, 7, 6)]
    for (x, y, w, h) in notes:
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                put(img, xx, yy, (208, 196, 160) if (xx + yy) % 5 else (180, 166, 130))
        put(img, x + w // 2, y, (190, 40, 40))
    outline(img, OUT)
    return img


def pillar(broken=False):
    h = 28 if broken else 44
    img = blank(18, h)
    for y in range(5, h - 4):
        for x in range(3, 15):
            nx = (x - 8.5) / 6
            k = 3 if nx < -0.3 else (2 if nx < 0.4 else 1)
            if y % 7 == 0:
                k = max(0, k - 1)
            put(img, x, y, STONE[k])
    ellipse(img, 8.5, 5, 6.5, 2.6, STONE[3:] if not broken else STONE[1:3])
    top_front(img, 1, 16, h - 5, 2, h - 1, STONE, 1, 3)
    for y in range(10, h - 8, 6):
        put(img, 8, y, (120, 230, 210))
        put(img, 9, y + 1, (70, 170, 160))
    outline(img, OUT)
    return img


def campfire(frame):
    img = blank(22, 20)
    for i in range(9):
        a = i * math.tau / 9
        x, y = 11 + math.cos(a) * 8, 15 + math.sin(a) * 3
        box(img, int(x) - 1, int(y) - 1, int(x) + 1, int(y), STONE, 3 if math.sin(a) < 0 else 2)
    for (x0, y0, x1, y1) in ((5, 16, 16, 13), (6, 13, 17, 16)):
        n = 12
        for i in range(n):
            put(img, round(x0 + (x1 - x0) * i / n), round(y0 + (y1 - y0) * i / n), WOOD[2 if i % 2 else 1])
    flame = [(255, 226, 130), (255, 160, 50), (210, 70, 30)]
    pts = [(11, 3), (10, 5), (12, 5), (9, 7), (11, 7), (13, 7), (9, 9), (12, 9), (10, 11), (11, 11), (13, 10)]
    for i, (x, y) in enumerate(pts):
        dx = (1 if frame and i % 2 else 0)
        put(img, x + dx, y + (1 if frame and i % 3 == 0 else 0), flame[min(2, (12 - y) // 4)])
    for y in range(6, 13):
        put(img, 11, y, flame[0] if y < 10 else flame[1])
    outline(img, OUT)
    return img


# ---------------- ground shadows ----------------

def shadow_of(img, k=0.55, lift=0.18, alpha=95):
    """Projects the silhouette onto the ground: each pixel at height z (from the sprite bottom)
    lands at (x + z*k, bottom - z*lift). Light from the upper-left -> shadow to the right/back."""
    w, h = img.size
    sw = w + int(h * k) + 2
    sh = Image.new("RGBA", (sw, h), (0, 0, 0, 0))
    px = img.load()
    out = sh.load()
    for y in range(h):
        z = h - 1 - y
        for x in range(w):
            if px[x, y][3] > 0:
                sx = int(x + z * k)
                sy = int(h - 1 - z * lift)
                for dx in (0, 1):
                    if 0 <= sx + dx < sw and 0 <= sy < h:
                        out[sx + dx, sy] = (8, 10, 20, alpha)
    return sh
