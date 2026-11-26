"""World props (houses, walls, trees, town furniture). Origin = bottom centre (feet).
Palette: dark-fantasy, warm window light as the main accent."""
import math
import random
from pixel import blank, rect, ellipse, put, outline, line

OUT = (26, 22, 34)
WOOD = [(58, 38, 30), (88, 60, 42), (122, 86, 58), (156, 116, 80)]
STONE = [(56, 54, 66), (82, 80, 94), (110, 108, 122), (144, 142, 156)]
SLATE = [(36, 36, 54), (54, 56, 80), (76, 80, 108), (104, 110, 140)]
CLAY = [(66, 34, 32), (96, 48, 42), (128, 68, 54), (158, 94, 70)]
PLASTER = [(124, 110, 92), (150, 136, 112), (176, 162, 134)]
IRON = [(38, 40, 48), (66, 70, 82), (104, 110, 124)]
PINE = [(20, 38, 32), (30, 54, 42), (44, 76, 54), (62, 100, 68)]
LIGHT = [(255, 196, 104), (255, 228, 160)]
GOLD = [(150, 104, 36), (214, 170, 80), (250, 222, 140)]


def _roof(img, x0, x1, y0, y1, ramp, slope=0.55):
    mid = (x0 + x1) / 2
    for y in range(y0, y1 + 1):
        half = min((x1 - x0) / 2, 6 + (y - y0) * slope * 2)
        for x in range(int(mid - half), int(mid + half) + 1):
            k = 3 if x < mid - half + 2 else (1 if x > mid + half - 3 else 2)
            if (y - y0) % 4 == 3:
                k = max(0, k - 1)
            if (x + (y // 4) * 3) % 7 == 0 and (y - y0) % 4 != 3:
                k = max(0, k - 1)
            put(img, x, y, ramp[k])


def _window(img, x, y, w=7, h=7, lit=True):
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            c = LIGHT[1] if (lit and yy < y + 3) else (LIGHT[0] if lit else (30, 34, 48))
            put(img, xx, yy, c)
    for yy in range(y, y + h):
        put(img, x + w // 2, yy, WOOD[0])
    for xx in range(x, x + w):
        put(img, xx, y + h // 2, WOOD[0])
    for xx in range(x - 1, x + w + 1):
        put(img, xx, y + h, WOOD[1])


def house(roof=SLATE, w=64, h=76, sign=None):
    img = blank(w, h)
    wall_top, wall_bot = 34, h - 6
    rect(img, 5, wall_top, w - 6, wall_bot, PLASTER)
    for bx in (5, w // 3, 2 * w // 3, w - 6):
        for y in range(wall_top, wall_bot + 1):
            put(img, bx, y, WOOD[1])
            put(img, bx + 1, y, WOOD[0])
    for x in range(5, w - 5):
        put(img, x, wall_top + 18, WOOD[1])
    rect(img, 3, wall_bot, w - 4, h - 1, STONE)
    dx = w // 2 - 6
    rect(img, dx, wall_bot - 18, dx + 11, wall_bot, WOOD, bias=-0.2)
    put(img, dx + 9, wall_bot - 9, GOLD[1])
    _window(img, 11, wall_top + 7)
    _window(img, w - 19, wall_top + 7)
    rect(img, w - 20, 2, w - 14, 16, STONE)        # chimney
    _roof(img, 0, w - 1, 0, wall_top + 2, roof)
    if sign:
        rect(img, dx - 10, wall_top + 3, dx - 2, wall_top + 9, WOOD)
        for (sx, sy) in sign:
            put(img, dx - 9 + sx, wall_top + 4 + sy, GOLD[2])
    outline(img)
    return img


def forge():
    img = house(roof=CLAY, w=72, h=74, sign=[(2, 1), (3, 1), (4, 1), (3, 2), (3, 3)])
    # open forge bay with glowing coals on the left
    for y in range(50, 66):
        for x in range(9, 22):
            put(img, x, y, (40, 30, 30))
    for x in range(10, 21):
        put(img, x, 64, (255, 120, 40))
        put(img, x, 63, (255, 170, 60) if x % 2 else (230, 90, 30))
    return img


def tavern():
    return house(roof=SLATE, w=76, h=78, sign=[(1, 2), (2, 1), (3, 1), (4, 1), (5, 2), (3, 3)])


def stall():
    img = blank(52, 46)
    for px in (4, 46):
        rect(img, px, 12, px + 2, 44, WOOD)
    rect(img, 2, 28, 49, 38, WOOD)
    for x in range(1, 51):
        for y in range(2, 14):
            stripe = (x // 6) % 2
            c = (150, 52, 46) if stripe else (196, 180, 146)
            if y > 10:
                c = tuple(int(v * 0.8) for v in c)
            put(img, x, y, c)
    for x in range(1, 51, 6):
        put(img, x + 2, 14, (150, 52, 46))
        put(img, x + 3, 14, (150, 52, 46))
    goods = [(200, 40, 50), (60, 120, 210), (90, 180, 90), (220, 180, 60)]
    for i, gx in enumerate(range(7, 46, 6)):
        put(img, gx, 26, goods[i % 4])
        put(img, gx + 1, 26, goods[i % 4])
        put(img, gx, 25, (230, 230, 230))
    outline(img)
    return img


def chest():
    img = blank(20, 16)
    rect(img, 1, 4, 18, 14, WOOD)
    rect(img, 1, 1, 18, 5, WOOD, bias=0.15)
    for x in (4, 15):
        for y in range(1, 15):
            put(img, x, y, IRON[1])
    for x in range(1, 19):
        put(img, x, 5, IRON[0])
    put(img, 9, 6, GOLD[2])
    put(img, 10, 6, GOLD[1])
    put(img, 9, 7, GOLD[1])
    outline(img)
    return img


def board():
    img = blank(28, 32)
    for px in (3, 23):
        rect(img, px, 6, px + 1, 31, WOOD)
    rect(img, 1, 4, 26, 20, WOOD, bias=0.1)
    notes = [(4, 7, 7, 6), (13, 6, 8, 7), (6, 14, 6, 5), (16, 14, 7, 5)]
    for (x, y, w, h) in notes:
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                put(img, xx, yy, (206, 194, 160) if (xx + yy) % 5 else (180, 166, 130))
        put(img, x + w // 2, y, (190, 40, 40))
    outline(img)
    return img


def well():
    img = blank(28, 32)
    ellipse(img, 14, 24, 12, 6, STONE)
    ellipse(img, 14, 23, 8, 3.5, [(18, 26, 40), (24, 36, 56)])
    for px in (4, 23):
        rect(img, px, 6, px + 1, 22, WOOD)
    _roof(img, 1, 26, 0, 7, CLAY, slope=1.2)
    line(img, 6, 13, 22, 13, WOOD[2])
    outline(img)
    return img


def lamp():
    img = blank(10, 32)
    rect(img, 4, 8, 5, 31, IRON)
    rect(img, 2, 29, 7, 31, IRON)
    rect(img, 1, 2, 8, 9, IRON)
    rect(img, 3, 4, 6, 7, [LIGHT[0], LIGHT[1]])
    outline(img)
    return img


def wall_h():
    img = blank(16, 22)
    rect(img, 0, 3, 15, 21, STONE)
    for y in range(8, 22, 5):
        for x in range(16):
            put(img, x, y, STONE[0])
    for y in range(3, 22, 5):
        off = 0 if (y // 5) % 2 else 8
        for yy in range(y, min(y + 5, 22)):
            put(img, (off + 3) % 16, yy, STONE[0])
    rect(img, 0, 0, 15, 3, STONE, bias=0.3)
    return img


def wall_v():
    img = blank(12, 16)
    rect(img, 0, 0, 11, 15, STONE, bias=0.15)
    for y in (5, 11):
        for x in range(12):
            put(img, x, y, STONE[0])
    for x in (0, 11):
        for y in range(16):
            put(img, x, y, STONE[0])
    return img


def tower():
    img = blank(22, 40)
    rect(img, 2, 10, 19, 39, STONE)
    for y in range(14, 40, 6):
        for x in range(2, 20):
            put(img, x, y, STONE[0])
    for cx in (2, 8, 14):
        rect(img, cx, 4, cx + 4, 10, STONE, bias=0.2)
    rect(img, 8, 18, 13, 24, [(20, 18, 26), (30, 26, 36)])
    put(img, 10, 21, LIGHT[0])
    outline(img)
    return img


def pine(seed=0, scale=1.0):
    rnd = random.Random(seed)
    h = int(50 * scale)
    w = int(34 * scale)
    img = blank(w, h)
    cx = w / 2
    trunk_top = h - int(10 * scale)
    rect(img, int(cx - 2), trunk_top, int(cx + 1), h - 1, WOOD)
    tiers = 4
    for t in range(tiers):
        top = int(t * (h - 12 * scale) / tiers)
        bot = top + int((h - 8 * scale) / tiers * 1.5)
        for y in range(top, min(bot, trunk_top + 2)):
            frac = (y - top) / max(1, bot - top)
            half = (3 + frac * (w / 2 - 3)) * (0.6 + 0.4 * (t + 1) / tiers)
            for x in range(int(cx - half), int(cx + half) + 1):
                k = 3 if x < cx - half * 0.4 else (2 if x < cx + half * 0.3 else 1)
                if y > bot - 3:
                    k = max(0, k - 1)
                if rnd.random() < 0.08:
                    k = max(0, k - 1)
                put(img, x, y, PINE[k])
    outline(img)
    return img


def bush(seed=0):
    rnd = random.Random(seed)
    img = blank(22, 16)
    for i in range(5):
        ellipse(img, 5 + i * 3 + rnd.random() * 2, 9 + rnd.random() * 2, 5, 5, PINE[1:])
    if rnd.random() < 0.5:
        for _ in range(3):
            put(img, rnd.randint(4, 17), rnd.randint(5, 11), (150, 40, 60))
    outline(img)
    return img


def campfire(frame):
    img = blank(18, 18)
    for (x0, y0, x1, y1) in ((2, 14, 15, 16), (4, 13, 13, 15)):
        line(img, x0, y0, x1, y1, WOOD[1])
        line(img, x0, y1, x1, y0, WOOD[2])
    flame = [(255, 210, 90), (255, 140, 40), (200, 60, 30)]
    shape = [(8, 4), (9, 3), (7, 6), (10, 6), (8, 8), (9, 9), (6, 9), (11, 9), (7, 11), (10, 11), (8, 12), (9, 12)]
    for i, (x, y) in enumerate(shape):
        yy = y + (1 if (frame and i % 3 == 0) else 0)
        put(img, x + (1 if frame and i % 2 else 0), yy, flame[min(2, (12 - y) // 4)])
    for y in range(6, 13):
        put(img, 8, y, flame[0] if y < 10 else flame[1])
        put(img, 9, y, flame[1])
    outline(img)
    return img


def pillar(broken=False):
    h = 24 if broken else 38
    img = blank(16, h)
    rect(img, 3, 4, 12, h - 3, STONE, bias=0.05)
    rect(img, 1, h - 4, 14, h - 1, STONE)
    if not broken:
        rect(img, 1, 0, 14, 4, STONE, bias=0.25)
    else:
        for x in range(3, 13):
            if (x * 7) % 5 < 2:
                put(img, x, 4, (0, 0, 0, 0))
    for y in range(8, h - 6, 5):
        put(img, 7, y, (120, 220, 200))
        put(img, 8, y + 1, (80, 170, 160))
    outline(img)
    return img


def anvil():
    img = blank(18, 12)
    rect(img, 1, 1, 16, 4, IRON, bias=0.2)
    rect(img, 6, 4, 11, 8, IRON)
    rect(img, 3, 8, 14, 11, IRON)
    outline(img)
    return img


def barrel():
    img = blank(14, 16)
    ellipse(img, 7, 8, 6, 7.5, WOOD)
    for y in (4, 11):
        for x in range(1, 13):
            put(img, x, y, IRON[1])
    outline(img)
    return img


def crate():
    img = blank(14, 14)
    rect(img, 1, 1, 12, 12, WOOD)
    line(img, 1, 1, 12, 12, WOOD[0])
    line(img, 12, 1, 1, 12, WOOD[0])
    outline(img)
    return img


def rock(seed=0):
    rnd = random.Random(seed)
    img = blank(20, 14)
    ellipse(img, 10, 8, 8 + rnd.random() * 2, 5.5, STONE)
    put(img, 6, 5, STONE[3])
    outline(img)
    return img


PROPS = {
    "house": house(), "forge": forge(), "tavern": tavern(), "stall": stall(), "chest": chest(),
    "board": board(), "well": well(), "lamp": lamp(), "wall_h": wall_h(), "wall_v": wall_v(),
    "tower": tower(), "pine": pine(1), "pine_big": pine(2, 1.35), "pine_small": pine(3, 0.8),
    "bush": bush(1), "bush_berry": bush(4), "campfire0": campfire(0), "campfire1": campfire(1),
    "pillar": pillar(), "pillar_broken": pillar(True), "anvil": anvil(), "barrel": barrel(),
    "crate": crate(), "rock": rock(1),
}


# 2.5D replacements for everything built (houses, walls, furniture); trees/bushes/rocks stay.
import props25d as p25
PROPS.update({
    "house": p25.building(76, p25.SLATE, seed=1), "forge": p25.building(80, p25.CLAY, sign=[(2, 1), (3, 1), (4, 1), (3, 2), (3, 3)], forge=True, seed=2),
    "tavern": p25.building(84, p25.SLATE, sign=[(1, 2), (2, 1), (3, 1), (4, 1), (5, 2), (3, 3)], seed=3),
    "stall": p25.stall(), "chest": p25.chest(), "board": p25.board(), "well": p25.well(), "lamp": p25.lamp(),
    "wall_h": p25.wall_h(), "wall_v": p25.wall_v(), "tower": p25.tower(), "campfire0": p25.campfire(0),
    "campfire1": p25.campfire(1), "pillar": p25.pillar(), "pillar_broken": p25.pillar(True), "anvil": p25.anvil(),
    "barrel": p25.barrel(), "crate": p25.crate(),
})
NO_SHADOW = {"wall_v", "campfire0", "campfire1"}

# Volumetric (lit) versions replace everything above.
import props_vol
PROPS.update(props_vol.build_all())
import props_life
PROPS.update(props_life.build_all())
NO_SHADOW = NO_SHADOW | {"lily"}
