"""Village clutter and nature detail, built with the same lit primitives as props_vol.
Each function returns an RGBA image; origin in game = bottom centre (minus the canvas pad)."""
import math
import random
from shade import Canvas, Mat, tex_noise, tex_planks
from props_vol import WOOD, WOOD_H, DARK_WOOD, IRON, ROCK, LEAF, BARK, STONE_FOUND, STONE_TOP

HAY = Mat((214, 178, 86), tex=tex_noise(0.6, 31))
SOIL = Mat((96, 70, 50), tex=tex_noise(0.5, 32))
SACK = Mat((176, 150, 110), tex=tex_noise(0.3, 33))
CLOTH_COLORS = [(190, 70, 64), (80, 120, 190), (220, 210, 180), (110, 160, 90)]
FLOWER_COLORS = [(220, 90, 120), (240, 200, 90), (150, 120, 230), (240, 240, 240)]
MUSH = Mat((200, 70, 60), spec=0.4)
MUSH_STEM = Mat((224, 214, 190))
LILY = Mat((78, 140, 86))


def fence(n=3):
    """Fence section: n posts + two rails, top faces lit."""
    w = 6 + (n - 1) * 8
    c = Canvas(w, 16)
    for i in range(n):
        x = 1 + i * 8
        c.box(x, x + 2, 1, 2, 15, WOOD, top_m=WOOD_H)
    c.box(0, w - 1, 5, 1, 6, WOOD_H, z=2)
    c.box(0, w - 1, 10, 1, 11, WOOD_H, z=2)
    return c.render()


def planter(seed=0):
    rnd = random.Random(seed)
    c = Canvas(22, 16)
    c.box(1, 20, 7, 3, 15, WOOD, top_m=SOIL)
    for i in range(7):
        x = 3 + i * 2.6 + rnd.random()
        col = Mat(rnd.choice(FLOWER_COLORS), spec=0.3)
        c.capsule(x, 9, x + rnd.uniform(-0.5, 0.5), 5, 0.5, LEAF, z=3)
        c.sphere(x, 4 + rnd.random(), 1.4, 1.2, col, z=5)
    return c.render()


def bench():
    c = Canvas(26, 14)
    for x in (3, 20):
        c.box(x, x + 2, 7, 0, 13, DARK_WOOD)
    c.box(0, 25, 4, 3, 8, WOOD, z=2, top_m=WOOD_H)
    c.box(0, 25, 0, 1, 3, WOOD_H, z=1)
    return c.render()


def haybale():
    c = Canvas(20, 16)
    c.cylinder(10, 9, 4, 13, HAY, cap_ry=3)
    for x in (5, 14):
        for y in range(3, 15):
            c.px(x, y, 9, (0, 0.1, 1), Mat((150, 110, 60)))
    return c.render()


def cart():
    c = Canvas(40, 30)
    c.box(3, 32, 8, 6, 20, WOOD, top_m=WOOD_H)
    for x in (8, 26):
        c.sphere(x, 22, 5, 5.5, DARK_WOOD, z=4)
        c.sphere(x, 22, 1.4, 1.4, IRON, z=8)
    c.capsule(32, 15, 39, 19, 0.8, DARK_WOOD, z=2)
    for i, x in enumerate((8, 15, 22)):
        c.sphere(x, 9, 3.2, 2.6, SACK, z=6 + i)
    return c.render()


def laundry():
    c = Canvas(44, 34)
    for x in (2, 40):
        c.box(x, x + 1, 2, 0, 33, DARK_WOOD)
    for x in range(3, 40):
        sag = 3 + 3 * math.sin((x - 3) / 37 * math.pi)
        c.px(x, 3 + sag, 2, (0, -0.2, 1), Mat((200, 196, 180)))
    for i, x0 in enumerate((7, 17, 28)):
        col = Mat(CLOTH_COLORS[i % len(CLOTH_COLORS)])
        top = int(4 + 3 * math.sin((x0 - 3) / 37 * math.pi)) + 1
        for y in range(top, top + 9 - i):
            for x in range(x0, x0 + 7):
                c.px(x, y, 3, (0.15 * math.sin(x), 0.1, 1), col)
    return c.render()


def signpost():
    c = Canvas(26, 30)
    c.box(11, 13, 4, 0, 29, DARK_WOOD)
    c.box(2, 24, 5, 1, 10, WOOD, z=2, top_m=WOOD_H)
    c.box(13, 25, 13, 1, 17, WOOD, z=2, top_m=WOOD_H)
    for x in range(5, 20, 3):
        c.px(x, 8, 4, (0, 0, 1), Mat((60, 44, 34), emissive=True))
    return c.render()


def stump():
    c = Canvas(16, 12)
    c.cylinder(8, 6, 4, 9, BARK, cap_m=Mat((176, 140, 96), tex=tex_noise(0.4, 34)), cap_ry=2.6)
    return c.render()


def log():
    c = Canvas(30, 12)
    c.capsule(4, 7, 25, 7, 3.6, BARK)
    c.sphere(26, 7, 2.2, 3.4, Mat((176, 140, 96)), z=4)
    return c.render()


def mushrooms(seed=0):
    rnd = random.Random(seed)
    c = Canvas(18, 12)
    for i in range(4):
        x, h = 3 + i * 3.6 + rnd.random(), rnd.uniform(3, 6)
        c.capsule(x, 11, x, 11 - h, 0.7, MUSH_STEM, z=i)
        c.sphere(x, 11 - h, 2.2, 1.5, MUSH, z=i + 2)
    return c.render()


def scarecrow():
    c = Canvas(26, 40)
    c.box(12, 13, 10, 0, 39, DARK_WOOD)
    c.capsule(2, 15, 23, 15, 1, DARK_WOOD, z=1)
    c.box(7, 18, 13, 0, 25, Mat((150, 70, 60)), z=2)
    c.sphere(12.5, 8, 4.5, 4.5, SACK, z=3)
    c.slope(4, 21, 1, 4, HAY, n=(0, -0.6, 0.8), z=5)
    c.box(7, 18, 4, 0, 5, Mat((90, 60, 40)), z=5)
    for x in range(8, 18, 2):
        c.px(x, 26, 4, (0, 0.2, 1), HAY)
    return c.render()


def sacks():
    c = Canvas(22, 16)
    for i, (x, y) in enumerate(((6, 10), (15, 10), (10.5, 5))):
        c.sphere(x, y, 5, 4.5, SACK, z=i)
    return c.render()


def rail():
    """Bridge railing section seen from above-front."""
    c = Canvas(24, 12)
    for x in (1, 11, 21):
        c.box(x, x + 1, 1, 1, 11, DARK_WOOD, top_m=WOOD_H)
    c.box(0, 23, 3, 1, 4, WOOD_H, z=2)
    return c.render()


def lily():
    c = Canvas(14, 8)
    c.sphere(6, 4, 5, 2.6, LILY, keep=lambda x, y: not (x > 6 and abs(y - 4) < 1))
    c.sphere(9, 3, 1.2, 1, Mat((240, 180, 200)), z=3)
    return c.render(outline=False)


def build_all():
    return {
        "fence": fence(3), "fence_long": fence(5), "planter": planter(1), "planter2": planter(5), "bench": bench(),
        "haybale": haybale(), "cart": cart(), "laundry": laundry(), "signpost": signpost(), "stump": stump(),
        "log": log(), "mushrooms": mushrooms(2), "scarecrow": scarecrow(), "sacks": sacks(), "rail": rail(),
        "lily": lily(),
    }
