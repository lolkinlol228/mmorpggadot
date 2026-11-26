"""Equipment overlays drawn on top of the Dark World character (32x32 frames).

Coordinates follow the base sprite: head rows 3-11 (x 8-23), torso rows 12-25.
Directions: 0 = down (front), 1 = up (back), 2 = side (facing left, flipped in game).
"""
from pixel import blank, ellipse, rect, put, erase, outline

STEEL = [(54, 60, 78), (92, 102, 124), (140, 152, 172), (196, 206, 220)]
LEATHER_RED = [(60, 26, 30), (96, 40, 44), (134, 60, 60), (168, 88, 82)]
LEATHER = [(56, 38, 30), (90, 62, 44), (128, 90, 60), (164, 122, 82)]
CLOTH = [(40, 28, 58), (66, 46, 92), (98, 70, 128), (136, 104, 166)]
GOLD = [(110, 70, 20), (176, 122, 38), (230, 182, 80), (255, 236, 160)]
DARK = (26, 22, 34)


def _pts_ellipse(cx, cy, rx, ry, w=32, h=32):
    out = []
    for y in range(h):
        for x in range(w):
            nx, ny = (x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry
            if nx * nx + ny * ny <= 1.0:
                out.append((x, y))
    return out


def helm(d):
    img = blank(32, 32)
    if d == 2:
        ellipse(img, 15.0, 7.5, 8.5, 6.2, STEEL, clip=lambda x, y: y <= 11)
        rect(img, 15, 8, 22, 13, STEEL, bias=-0.15)          # neck guard at the back
    else:
        ellipse(img, 15.5, 7.2, 9.0, 6.2, STEEL, clip=lambda x, y: y <= 11)
        rect(img, 7, 8, 10, 13, STEEL, bias=0.05)            # cheek guards
        rect(img, 21, 8, 24, 13, STEEL, bias=-0.1)
        if d == 1:
            rect(img, 10, 10, 21, 13, STEEL, bias=-0.15)
    outline(img)
    if d == 0:
        for x in range(10, 22):
            put(img, x, 9, DARK)
        for y in range(5, 11):
            put(img, 15, y, STEEL[3])
            put(img, 16, y, STEEL[2])
    elif d == 1:
        for y in range(2, 11):
            put(img, 15, y, STEEL[3])
    else:
        for x in range(7, 13):
            put(img, x, 9, DARK)
        put(img, 12, 6, STEEL[3])
    return img


def hood(d):
    img = blank(32, 32)
    if d == 2:
        ellipse(img, 16.0, 7.5, 9.5, 7.0, LEATHER_RED, clip=lambda x, y: y <= 13)
        for y in range(9, 16):
            for x in range(22, 25 - (y - 9) // 3):
                put(img, x, y, LEATHER_RED[1])
        outline(img)
        erase(img, _pts_ellipse(10.0, 9.2, 3.4, 3.0))
    else:
        ellipse(img, 15.5, 7.5, 10.0, 7.0, LEATHER_RED, clip=lambda x, y: y <= 13)
        rect(img, 7, 12, 24, 14 if d == 0 else 18, LEATHER_RED, bias=-0.1)
        put(img, 15, 0, LEATHER_RED[2])
        put(img, 16, 0, LEATHER_RED[2])
        outline(img)
        if d == 0:
            erase(img, _pts_ellipse(15.5, 9.6, 5.0, 3.2))
    return img


def dawn_crown(d):
    img = blank(32, 32)
    x0, x1 = (9, 22) if d != 2 else (9, 20)
    rect(img, x0, 5, x1, 7, GOLD)
    spikes = [x0 + 1, (x0 + x1) // 2 - 3, (x0 + x1) // 2, (x0 + x1) // 2 + 1, (x0 + x1) // 2 + 4, x1 - 1]
    for i, sx in enumerate(spikes):
        hgt = 3 if i in (2, 3) else 2
        for y in range(5 - hgt, 5):
            put(img, sx, y, GOLD[2])
    outline(img)
    for gx in ((x0 + 3, x1 - 3) if d != 1 else ()):
        put(img, gx, 6, (220, 30, 50))
    if d != 1:
        put(img, (x0 + x1) // 2, 6, (255, 110, 120))
    for sx in spikes[2:4]:
        put(img, sx, 1, (255, 150, 40))
    return img


def armor(d):
    img = blank(32, 32)
    if d == 2:
        rect(img, 9, 12, 19, 21, STEEL)
        ellipse(img, 14.5, 13.5, 3.5, 2.8, STEEL, bias=0.15)
    else:
        rect(img, 9, 12, 22, 21, STEEL)
        ellipse(img, 7.5, 13.5, 3.2, 2.6, STEEL, bias=0.15)
        ellipse(img, 24.0, 13.5, 3.2, 2.6, STEEL, bias=0.05)
    for x in range(9, 23 if d != 2 else 20):
        put(img, x, 21, LEATHER[1])
        put(img, x, 22, LEATHER[0])
    outline(img)
    if d == 0:
        for y in range(13, 21):
            put(img, 15, y, STEEL[1])
        for x in (11, 20):
            put(img, x, 15, STEEL[3])
        put(img, 15, 21, GOLD[2])
        put(img, 16, 21, GOLD[2])
    return img


def robe(d):
    img = blank(32, 32)
    if d == 1:
        rect(img, 6, 12, 25, 25, CLOTH, bias=-0.05)
        for x in range(6, 26):
            if x % 3 == 0:
                put(img, x, 26, CLOTH[1])
    elif d == 0:
        for y in range(12, 26):
            spread = (y - 12) // 4
            for x in range(6 - spread // 2, 10):
                put(img, x, y, CLOTH[1] if x < 8 else CLOTH[2])
            for x in range(22, 26 + spread // 2):
                put(img, x, y, CLOTH[1] if x > 23 else CLOTH[0])
        rect(img, 8, 12, 23, 13, CLOTH, bias=0.1)
    else:
        for y in range(12, 27):
            for x in range(14, 22 + (y - 12) // 4):
                put(img, x, y, CLOTH[1] if x > 18 else CLOTH[2])
        rect(img, 9, 12, 19, 13, CLOTH, bias=0.1)
    outline(img)
    if d == 0:
        put(img, 15, 13, GOLD[2])
        put(img, 16, 13, GOLD[2])
    return img


def boots(d):
    img = blank(32, 32)
    if d == 2:
        rect(img, 8, 24, 14, 26, LEATHER)
        rect(img, 15, 24, 19, 26, LEATHER, bias=-0.2)
    else:
        rect(img, 9, 23, 12, 26, LEATHER)
        rect(img, 19, 23, 22, 26, LEATHER, bias=-0.1)
    outline(img)
    return img


GEAR_ROWS = [("helm", helm), ("hood", hood), ("dawn_crown", dawn_crown),
             ("armor", armor), ("robe", robe), ("boots", boots)]


def sheet():
    img = blank(32 * 3, 32 * len(GEAR_ROWS))
    for r, (_, fn) in enumerate(GEAR_ROWS):
        for d in range(3):
            img.alpha_composite(fn(d), (d * 32, r * 32))
    return img
