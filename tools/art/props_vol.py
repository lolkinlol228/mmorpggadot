"""Volumetric props built from lit primitives (shade.py). Origin = bottom centre in game."""
import math
import random
from shade import Canvas, Mat, tex_bricks, tex_planks, tex_shingles, tex_noise, TOP

# materials
PLASTER = Mat((178, 162, 132), tex=tex_noise(0.2, 3))
TIMBER = Mat((112, 76, 50), tex=tex_planks(3))
STONE_B = Mat((120, 118, 132), tex=tex_bricks(7, 5))
STONE_FOUND = Mat((104, 100, 112), tex=tex_bricks(6, 4, 0.8))
STONE_TOP = Mat((124, 122, 134), tex=tex_noise(0.25, 5))
SLATE = Mat((76, 86, 118), tex=tex_shingles(5, 4))
CLAY = Mat((150, 76, 58), tex=tex_shingles(5, 4))
WOOD = Mat((128, 88, 58), tex=tex_planks(4))
WOOD_H = Mat((128, 88, 58), tex=tex_planks(3, horizontal=True))
DARK_WOOD = Mat((80, 54, 38), tex=tex_planks(3))
IRON = Mat((96, 100, 116), spec=0.7)
GOLD = Mat((214, 168, 72), spec=0.9)
GLASS_LIT = Mat((255, 206, 120), emissive=True)
GLASS_HI = Mat((255, 236, 180), emissive=True)
WATER = Mat((40, 62, 96), spec=0.9)
LEAF = Mat((58, 98, 64), tex=tex_noise(0.4, 7))
PINE_M = Mat((40, 78, 56), tex=tex_noise(0.35, 9))
BARK = Mat((92, 62, 44), tex=tex_planks(2))
ROCK = Mat((112, 110, 120), tex=tex_noise(0.4, 11))
AWN_R = Mat((168, 58, 50))
AWN_W = Mat((214, 200, 166))
PAPER = Mat((216, 204, 168), tex=tex_noise(0.4, 2))
FIRE = Mat((255, 170, 60), emissive=True)
FIRE_HI = Mat((255, 230, 140), emissive=True)
RUNE = Mat((120, 230, 210), emissive=True)


def window(c, x, y, w=8, h=8):
    c.box(x - 1, x + w, y - 1, 0, y + h, DARK_WOOD, z=3)
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            c.px(xx, yy, 5, (0, 0, 1), GLASS_HI if yy < y + 2 else GLASS_LIT)
    for yy in range(y, y + h):
        c.px(x + w // 2, yy, 6, (0, 0, 1), DARK_WOOD)
    for xx in range(x, x + w):
        c.px(xx, y + h // 2, 6, (0, 0, 1), DARK_WOOD)
    c.box(x - 2, x + w + 1, y + h + 1, 1, y + h + 2, WOOD, z=6)       # sill: top + front


def building(w=80, roof=SLATE, forge=False, sign=False, seed=0):
    roof_h, wall_h, found_h = 42, 34, 6
    h = roof_h + wall_h + found_h
    c = Canvas(w, h)
    wx0, wx1, wy0, wy1 = 5, w - 6, roof_h, roof_h + wall_h - 1
    c.box(wx0, wx1, wy0, 0, wy1, PLASTER, ao_bottom=True)
    for bx in (wx0, wx0 + (wx1 - wx0) // 3, wx0 + 2 * (wx1 - wx0) // 3, wx1 - 1):
        c.box(bx, bx + 1, wy0, 0, wy1, TIMBER, z=1)
    c.box(wx0, wx1, wy0 + 15, 0, wy0 + 16, TIMBER, z=1)
    dx = w // 2 - 7
    c.box(dx - 1, dx + 14, wy1 - 21, 0, wy1, DARK_WOOD, z=2)
    c.box(dx + 1, dx + 12, wy1 - 19, 0, wy1, WOOD, z=1)              # recessed door (lower z)
    c.occlude(dx + 1, wy1 - 19, dx + 3, wy1, 0.7)
    c.px(dx + 10, wy1 - 9, 3, (0, 0, 1), GOLD)
    if forge:
        c.box(wx0 + 3, wx0 + 19, wy1 - 15, 0, wy1, STONE_B, z=2)
        for x in range(wx0 + 5, wx0 + 18):
            for y in range(wy1 - 4, wy1):
                c.px(x, y, 4, (0, 0, 1), FIRE_HI if (x + y) % 3 == 0 else FIRE)
        window(c, wx1 - 17, wy0 + 6)
    else:
        window(c, wx0 + 6, wy0 + 6)
        window(c, wx1 - 16, wy0 + 6)
    if sign:
        c.box(dx - 13, dx - 4, wy0 + 5, 1, wy0 + 13, WOOD, z=4)
        for i in range(4):
            c.px(dx - 11 + i * 2, wy0 + 9, 6, (0, 0, 1), GOLD)
    c.occlude(wx0, wy0, wx1, wy0 + 4, 0.55)                          # eave shadow on the wall
    c.box(2, w - 3, wy1 + 1, 2, h - 1, STONE_FOUND, top_m=STONE_TOP)
    # roof: back slope (dark, facing away), ridge cap, big front slope facing up/at the viewer
    c.slope(2, w - 3, 2, 7, roof, n=(0, -0.9, -0.2), z=0)
    c.box(1, w - 2, 7, 2, 9, roof, z=2, ao_bottom=False)
    c.slope(0, w - 1, 10, roof_h, roof, n=(0, -0.62, 0.78), z=1)
    c.occlude(0, roof_h - 1, w - 1, roof_h, 0.6)
    # dormer
    cx = w // 2
    c.box(cx - 7, cx + 6, 20, 0, 32, PLASTER, z=3)
    window(c, cx - 4, 23, 7, 6)
    c.slope(cx - 9, cx + 8, 14, 20, roof, n=(0, -0.6, 0.8), z=4, taper=6)
    c.occlude(cx - 7, 32, cx + 6, 33, 0.6)
    # chimney
    ch = w - 20
    c.box(ch, ch + 8, 0, 3, 18, STONE_B, z=5, top_m=STONE_TOP)
    for x in range(ch + 2, ch + 7):
        c.px(x, 1, 7, (0, 0, 1), Mat((30, 26, 30)))
    return c.render()


def barrel():
    c = Canvas(18, 22)
    c.cylinder(9, 7, 5, 18, WOOD, cap_m=WOOD_H, cap_ry=3)
    for y in (9, 15):
        for x in range(2, 17):
            nx = (x + 0.5 - 9) / 7
            if abs(nx) <= 1:
                c.px(x, y, 3, (nx, 0.1, math.sqrt(max(0, 1 - nx * nx))), IRON)
    return c.render()


def crate():
    c = Canvas(18, 20)
    c.box(1, 16, 2, 6, 18, WOOD, top_m=WOOD_H)
    for i in range(12):
        c.px(3 + i, 9 + int(i * 0.75), 3, (0, 0.2, 1), DARK_WOOD)
    return c.render()


def chest():
    c = Canvas(24, 22)
    c.box(1, 22, 3, 7, 20, WOOD, top_m=WOOD_H)
    for x in (5, 17):
        c.box(x, x + 1, 3, 7, 20, IRON, z=1)
    c.box(1, 22, 10, 0, 10, IRON, z=1)
    c.box(10, 13, 11, 0, 14, GOLD, z=2)
    return c.render()


def lamp():
    c = Canvas(14, 40)
    c.box(3, 10, 33, 2, 39, STONE_FOUND, top_m=STONE_TOP)
    c.cylinder(6.5, 1.3, 12, 33, IRON)
    c.box(3, 10, 5, 2, 12, IRON, z=2)
    for y in range(7, 12):
        for x in range(4, 10):
            c.px(x, y, 4, (0, 0, 1), GLASS_HI if y < 9 else GLASS_LIT)
    c.cone(6.5, 0, 5, 4.5, IRON, z=3)
    return c.render()


def well():
    c = Canvas(36, 48)
    for px in (5, 29):
        c.box(px, px + 1, 10, 0, 32, WOOD, z=0)
    c.cylinder(18, 15, 33, 42, STONE_B, cap_m=STONE_TOP, cap_ry=6)
    c.sphere(18, 33, 10.5, 3.6, WATER, z=4)
    c.slope(2, 33, 4, 14, CLAY, n=(0, -0.62, 0.78), z=6)
    c.slope(4, 31, 1, 4, CLAY, n=(0, -0.9, -0.2), z=5)
    c.box(7, 28, 17, 1, 18, WOOD, z=5)
    return c.render()


def pine(scale=1.0, seed=0):
    rnd = random.Random(seed)
    w, h = int(36 * scale), int(56 * scale)
    c = Canvas(w, h)
    cx = w / 2
    c.cylinder(cx, 2.2 * scale, h - 12 * scale, h - 4, BARK, cap_ry=1)
    tiers = 4
    for t in range(tiers):
        top = (h - 14 * scale) * t / tiers
        base = top + (h - 10 * scale) / tiers * 1.55
        r = (w / 2 - 2) * (0.55 + 0.45 * (t + 1) / tiers)
        c.cone(cx + rnd.uniform(-0.5, 0.5), top, base, r, PINE_M, z=t)
        if t > 0:
            c.occlude(0, int(top), w - 1, int(top) + 2, 0.7)   # shade cast by the tier above
    return c.render()


def bush(seed=0):
    rnd = random.Random(seed)
    c = Canvas(24, 18)
    for i in range(5):
        c.sphere(5 + i * 3.4 + rnd.random(), 10 + rnd.random() * 2, 5, 4.5, LEAF, z=rnd.random())
    return c.render()


def rock(seed=0):
    rnd = random.Random(seed)
    c = Canvas(22, 16)
    c.sphere(11, 10, 9 + rnd.random(), 6, ROCK)
    c.sphere(15, 11, 5, 4, ROCK, z=2)
    return c.render()


def anvil():
    c = Canvas(24, 18)
    c.box(1, 22, 1, 3, 6, IRON)
    c.box(8, 15, 7, 0, 11, IRON)
    c.box(4, 19, 11, 2, 17, IRON)
    return c.render()


def pillar(broken=False):
    h = 30 if broken else 46
    c = Canvas(20, h)
    c.box(1, 18, h - 6, 2, h - 1, STONE_FOUND, top_m=STONE_TOP)
    c.cylinder(9.5, 6.5, 6, h - 8, STONE_B, cap_m=STONE_TOP, cap_ry=2.6)
    for y in range(12, h - 10, 7):
        c.px(9, y, 9, (0, 0, 1), RUNE)
        c.px(10, y + 1, 9, (0, 0, 1), RUNE)
    return c.render()


def stall():
    c = Canvas(60, 52)
    for px in (5, 53):
        c.box(px, px + 1, 12, 0, 48, WOOD)
    for y in range(2, 17):
        for x in range(1 + (16 - y) // 4, 59 - (16 - y) // 4):
            c.px(x, y, 3, (0, -0.5, 0.86), AWN_R if (x // 7) % 2 else AWN_W)
    c.box(2, 57, 31, 6, 47, WOOD, z=4, top_m=WOOD_H)
    colors = [(200, 40, 50), (60, 120, 210), (90, 180, 90), (220, 180, 60), (180, 120, 220)]
    for i, gx in enumerate(range(7, 55, 6)):
        c.sphere(gx, 30, 2, 2.4, Mat(colors[i % 5], spec=0.8), z=6)
    return c.render()


def board():
    c = Canvas(32, 38)
    for px in (5, 25):
        c.box(px, px + 1, 10, 0, 37, WOOD)
    c.box(1, 30, 1, 2, 25, DARK_WOOD, z=1, top_m=WOOD_H)
    for (x, y, w, h) in [(4, 6, 7, 6), (14, 5, 8, 7), (6, 15, 6, 5), (17, 15, 7, 6)]:
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                c.px(xx, yy, 3, (0.1, -0.05, 1), PAPER)
        c.px(x + w // 2, y, 4, (0, 0, 1), Mat((200, 40, 40), spec=0.6))
    return c.render()


def tower():
    c = Canvas(28, 56)
    c.box(2, 25, 8, 8, 55, STONE_B, top_m=STONE_TOP)
    for cx in (2, 10, 18):
        c.box(cx, cx + 6, 0, 4, 9, STONE_B, z=2, top_m=STONE_TOP)
    c.box(11, 16, 28, 0, 36, DARK_WOOD, z=2)
    c.px(13, 31, 4, (0, 0, 1), GLASS_LIT)
    return c.render()


def wall_h():
    c = Canvas(16, 28, pad=0)
    c.box(0, 15, 0, 7, 27, STONE_B, top_m=STONE_TOP)
    return c.render(outline=False)


def wall_v():
    c = Canvas(14, 16, pad=0)
    for y in range(16):
        for x in range(14):
            c.px(x, y, 0, (0.0, 0.25, 0.97) if 1 < x < 12 else ((-0.8 if x < 2 else 0.8), -0.4, 0.4), STONE_FOUND)
    return c.render(outline=False)


def campfire(frame):
    c = Canvas(24, 22)
    for i in range(10):
        a = i * math.tau / 10
        c.sphere(12 + math.cos(a) * 8.5, 16 + math.sin(a) * 3.2, 2.2, 1.7, ROCK, z=math.sin(a))
    for k in range(10):
        c.px(6 + k, 16 - k * 0.3, 2, (0, -0.3, 1), BARK)
        c.px(7 + k, 13 + k * 0.3, 2, (0, -0.3, 1), BARK)
    pts = [(12, 3), (11, 5), (13, 5), (10, 7), (12, 7), (14, 7), (10, 9), (13, 9), (11, 11), (12, 11), (14, 10)]
    for i, (x, y) in enumerate(pts):
        dx = 1 if frame and i % 2 else 0
        c.px(x + dx, y + (1 if frame and i % 3 == 0 else 0), 5, (0, 0, 1), FIRE_HI if y < 7 else FIRE)
    for y in range(6, 13):
        c.px(12, y, 6, (0, 0, 1), FIRE_HI)
    return c.render()


def build_all():
    return {
        "house": building(80, SLATE, seed=1), "forge": building(84, CLAY, forge=True, sign=True, seed=2),
        "tavern": building(88, SLATE, sign=True, seed=3), "barrel": barrel(), "crate": crate(), "chest": chest(),
        "lamp": lamp(), "well": well(), "pine": pine(1.0, 1), "pine_big": pine(1.3, 2), "pine_small": pine(0.8, 3),
        "bush": bush(1), "bush_berry": bush(4), "rock": rock(1), "anvil": anvil(), "pillar": pillar(),
        "pillar_broken": pillar(True), "stall": stall(), "board": board(), "tower": tower(), "wall_h": wall_h(),
        "wall_v": wall_v(), "campfire0": campfire(0), "campfire1": campfire(1),
    }
