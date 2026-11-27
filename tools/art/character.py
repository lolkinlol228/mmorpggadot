"""Modular character on one skeleton, rendered with lighting (shade.py) + hand-placed face details.

Cells are 48x48 (a 32x32 body box with an 8px margin for weapon swings); feet at y=30 of the box.
Columns: idle0, idle1, walk0..walk3, atk0..atk2. Rows: down, up, side (side faces RIGHT).
Layer order (bottom -> top) - see LAYERS. Hair/skin variants are separate sheets, picked at bake time.
"""
import math
from PIL import Image
from shade import Canvas, Mat, tex_noise

DIRS = ["down", "up", "side"]
CELL_PAD = 8
CELL = 32 + 2 * CELL_PAD
# 0-1 стойка, 2-5 ходьба, 6-9 бег, 10-12 рубящий удар, 13-15 удар сверху, 16-18 укол, 19 взаимодействие, 20 урон
FRAMES = ["idle0", "idle1", "walk0", "walk1", "walk2", "walk3", "run0", "run1", "run2", "run3",
          "slash0", "slash1", "slash2", "chop0", "chop1", "chop2", "stab0", "stab1", "stab2", "use", "hurt"]
LAYERS = ["hair_back", "weapon_back", "legs", "feet", "arms_back", "hands_back", "skirt", "torso", "tail", "weapon",
          "arms_front", "hands", "head", "marks", "beard", "headgear", "ears", "hat"]
SEX = "m"                # текущий пол при генерации: "m" / "f" (влияет на фигуру и лицо)
EYE_KEY = (255, 0, 255)  # цвет-ключ радужки: в игре заменяется выбранным цветом глаз
BEARDS = ["full", "moustache", "stubble", "goatee", "braided"]
MARKS = ["scar", "freckles", "warpaint", "leafmark", "soot", "runes", "tribal", "stitches", "bones",
         "whiskers", "stripes", "earrings"]

SKIN_TONES = {"light": (232, 184, 150), "mid": (204, 146, 108), "dark": (132, 90, 66),
              "pale": (226, 220, 210), "green": (128, 168, 88), "olive": (170, 172, 106),
              "moss": (98, 132, 80), "ash": (168, 168, 176), "bluish": (150, 168, 190),
              "lime": (158, 186, 84), "khaki": (172, 162, 104), "greygreen": (128, 148, 118)}
RACES = {
    # dy — рост (сдвиг верха тела), w — ширина фигуры в пикселях (игра растягивает/сужает собранный кадр).
    # hair / beards / marks / eyes — что доступно расе в создании героя (первое — по умолчанию).
    "human": {"tones": ["light", "mid", "dark"],
              "hair": ["short", "crop", "slick", "straight", "long", "tail", "spiky", "braid", "bob", "bun", "bald"],
              "beards": ["none", "full", "moustache", "stubble", "goatee"],
              "marks": ["none", "scar", "freckles", "warpaint"],
              "eyes": ["brown", "blue", "green", "grey", "amber"]},
    "elf": {"tones": ["light", "pale", "mid"], "dy": -1, "w": -1,
            "hair": ["straight", "long", "slick", "tail", "braid", "bun", "bob", "short"],
            "beards": ["none"],
            "marks": ["none", "leafmark", "freckles", "scar"],
            "eyes": ["green", "blue", "violet", "grey", "amber"]},
    "dwarf": {"tones": ["light", "mid", "dark"], "dy": 2, "w": 2,
              "hair": ["crop", "short", "braid", "long", "topknot", "bald", "bun"],
              "beards": ["full", "braided", "moustache"],
              "marks": ["none", "soot", "runes", "scar"],
              "eyes": ["brown", "blue", "grey", "amber", "green"]},
    "orc": {"tones": ["green", "olive", "moss"], "w": 4,
            "hair": ["mohawk", "topknot", "crop", "bald", "tail", "braid", "spiky"],
            "beards": ["none", "goatee", "stubble", "moustache"],
            "marks": ["none", "warpaint", "tribal", "scar"],
            "eyes": ["red", "amber", "yellow", "brown"]},
    "undead": {"tones": ["pale", "ash", "bluish"], "w": -1,
               "hair": ["wisps", "bald", "slick", "straight", "long", "short", "spiky"],
               "beards": ["none", "stubble"],
               "marks": ["none", "stitches", "bones", "scar"],
               "eyes": ["cyan", "red", "green", "violet"]},
    "felin": {"tones": ["light", "mid", "dark"],
              "hair": ["short", "crop", "straight", "spiky", "long", "tail", "bob", "bun", "braid"],
              "beards": ["none"],
              "marks": ["none", "whiskers", "stripes", "freckles"],
              "eyes": ["amber", "green", "yellow", "blue"]},
    "goblin": {"tones": ["lime", "khaki", "greygreen"], "dy": 3, "w": -1,
               "hair": ["tufts", "bald", "slick", "mohawk", "topknot", "spiky", "tail"],
               "beards": ["none", "goatee", "moustache"],
               "marks": ["none", "earrings", "warpaint", "scar"],
               "eyes": ["yellow", "red", "amber", "green"]},
}
HAIR_COLORS = {"brown": (112, 72, 46), "black": (50, 46, 60), "blond": (226, 188, 112),
               "red": (180, 80, 46), "white": (214, 214, 226)}
HAIR_STYLES = ["short", "long", "tail", "spiky", "braid", "bob", "bun", "bald", "mohawk", "tufts", "topknot", "wisps",
               "crop", "slick", "straight"]
FLAT_STYLES = ["crop", "slick", "straight"]   # гладкие: облегают череп, без пышной «шапки»
BARE_STYLES = ["bald", "mohawk", "tufts", "topknot", "wisps"]     # без «шапки» волос: голый череп и пряди

HOLD_ANGLE = {0: 72, 1: 100, 2: 38}
FACING = {0: 90, 1: -90, 2: 0}
ATTACKS = {   # углы оружия по кадрам удара для каждого направления
    "slash": {0: [-150, -70, 45], 1: [-55, -100, -155], 2: [-115, -40, 35]},
    "chop": {0: [-95, -70, 80], 1: [-85, -95, -100], 2: [-100, -60, 60]},
    "stab": {0: [90, 90, 90], 1: [-90, -90, -90], 2: [8, 0, 4]},
}
STAB_REACH = [1.0, 6.5, 4.0]

TUNIC = Mat((142, 122, 94), tex=tex_noise(0.2, 6))
TUNIC_DARK = Mat((104, 86, 66))
PANTS = Mat((64, 68, 98))
SHOES = Mat((84, 58, 42))
BELT = Mat((92, 60, 40))
BUCKLE = Mat((226, 184, 92), spec=0.9)

STEEL = Mat((152, 162, 182), spec=0.8)
LEATHER = Mat((132, 90, 58))
HOODC = Mat((132, 58, 60), tex=tex_noise(0.2, 8))
CLOTH = Mat((104, 74, 146), tex=tex_noise(0.2, 9))
GOLD = Mat((224, 178, 82), spec=0.9)
GEM = Mat((232, 40, 62), spec=1.0)


def tex_strands(x, y):
    k = (x + y // 3) % 3
    return (-0.9 if k == 0 else 0.3, 0.0, 0.0)


def skel(d, f):
    walk = 2 <= f <= 5
    run = 6 <= f <= 9
    style = "slash" if 10 <= f <= 12 else ("chop" if 13 <= f <= 15 else ("stab" if 16 <= f <= 18 else None))
    k = (f - 10) % 3 if style else 0
    use = f == 19
    hurt = f == 20
    phase = (f - 2) if walk else ((f - 6) if run else 0)
    step = [1, 0, -1, 0][phase] if walk else ([2, 0, -2, 0][phase] if run else 0)
    bob = [0, 1, 0, 1][phase] if walk else ([0, 2, 0, 2][phase] if run else (1 if f == 1 else 0))
    if style == "chop" and k == 2:
        bob = 1                                                  # приседает на ударе
    lean = 0
    if d == 2:
        lean = 1 if walk else (2 if run else 0)
        if style == "stab":
            lean = [0, 2, 1][k]
        elif style == "chop":
            lean = [-1, 0, 1][k]
    hx = lean + (-1 if (hurt and d == 2) else 0)
    hy = bob + (-1 if hurt else 0)
    g = {"bob": bob, "step": step, "dir": d, "walk": walk, "run": run, "hurt": hurt, "head": (16 + hx, 8 + hy)}
    stride = 2.2 if run else 2.5
    fem = SEX == "f"
    if d == 2:
        g["torso"] = (16 + lean * 0.5, 14 + bob, 21, 3.4 if fem else 3.7, 3.0 if fem else 3.3)   # cx, top, bottom, плечи, талия
        g["legs"] = [(15.5 - step * stride, 22, 1.5, 1 if (walk and step == 0) else (2 if run and step == 0 else 0)),
                     (16.5 + step * stride, 22, 1.5, 0)]
        g["arms"] = [(15.5 + step * 2.5, 15 + bob, 1.35, 0), (17 + lean * 0.5 - step * 2.5, 15 + bob, 1.35, 0)]
    else:
        g["torso"] = (15.5, 14 + bob, 21, 4.7 if fem else 5.3, 3.6 if fem else 4.2)
        g["legs"] = [(13.5, 22, 1.7, -step), (17.5, 22, 1.7, step)]
        spread = 1 if hurt else 0
        ax = 0.6 if fem else 0.0                                    # у женщин руки ближе к телу
        g["arms"] = [(9.3 + ax - spread, 15 + bob, 1.3 if fem else 1.45, step - spread),
                     (21.7 - ax + spread, 15 + bob, 1.3 if fem else 1.45, -step - spread)]
    sx, sy = g["arms"][1][0], g["arms"][1][1]
    g["attack"] = False
    if style:
        ang = ATTACKS[style][d][k]
        reach = STAB_REACH[k] if style == "stab" else 3.5
        a = math.radians(ang)
        g["hand"] = (sx + math.cos(a) * reach, sy + 1 + math.sin(a) * reach)
        g["attack"] = True
    elif use:
        a = math.radians(FACING[d])
        ang = HOLD_ANGLE[d]
        g["hand"] = (sx + math.cos(a) * 4.5, sy + 1 + math.sin(a) * 4.5)
        g["attack"] = True
    else:
        ang = HOLD_ANGLE[d] + step * (10 if run else 8)
        g["hand"] = (sx, sy + (4.6 if run else 6.0) + g["arms"][1][3])
    g["angle"] = ang
    return g

def _tapered(c, cx, top, bot, r_top, r_bot, m, z=0.0):
    """Torso column whose radius tapers from the shoulders to the waist (gives a real silhouette)."""
    for y in range(int(top), int(bot) + 1):
        t = (y - top) / max(1, bot - top)
        r = r_top + (r_bot - r_top) * min(1.0, t * 1.4)
        if y == int(top):
            r -= 1.0                                         # rounded shoulders
        for x in range(int(cx - r) - 1, int(cx + r) + 2):
            nx = (x + 0.5 - cx) / r
            if abs(nx) <= 1:
                nz = math.sqrt(max(0, 1 - nx * nx))
                ny = -0.5 if y == int(top) else 0.12
                c.px(x, y, z + nz, (nx, ny, nz), m)


def _part(layer, d, f, m_torso=TUNIC, m_arm=None, skirt_m=None, feet_m=SHOES, details=True):
    g = skel(d, f)
    c = Canvas(32, 32, pad=CELL_PAD)
    m_arm = m_arm or m_torso
    if layer == "legs":
        for (x, top, r, lift) in g["legs"]:
            c.cylinder(x, r, top, 27 - max(0, lift), PANTS, cap_ry=0.6)
    elif layer == "feet":
        for i, (x, top, r, lift) in enumerate(g["legs"]):
            ly = 27 - max(0, lift)
            if d == 2:
                c.box(int(x - 1.5), int(x + 2.5), ly, 1, ly + 2, feet_m)
                c.px(int(x + 3), ly + 2, 2, (0.6, -0.2, 0.8), feet_m)            # toe
            else:
                c.box(int(x - 1.5), int(x + 1.5), ly, 1, ly + 2, feet_m)
        c.occlude(0, 29, 31, 29, 0.7)
    elif layer in ("arms_back", "arms_front"):
        arms = g["arms"]
        pick = ([arms[0]] if layer == "arms_back" else [arms[1]]) if d == 2 else ([] if layer == "arms_back" else arms)
        for (x, y, r, swing) in pick:
            weapon_arm = (x, y) == (arms[1][0], arms[1][1])
            if weapon_arm and g["attack"]:
                hx, hy = g["hand"]
                c.capsule(x, y + 0.5, hx, hy - 1.0, r, m_arm, z=2)
                continue
            bottom = y + (4 if g["run"] else 5) + swing          # на бегу руки согнуты
            c.cylinder(x, r, y, bottom - 1, m_arm, cap_ry=0.9)
            if details and m_arm is TUNIC:
                for xx in range(int(x - r), int(x + r) + 1):
                    c.px(xx, bottom - 1, 9, (0, 0.3, 0.95), TUNIC_DARK)           # sleeve cuff
        if layer == "arms_back" and d == 2:
            c.occlude(0, 0, 31, 31, 0.72)
    elif layer == "torso":
        cx, top, bot, r_sh, r_w = g["torso"]
        _tapered(c, cx, top + 1, bot, r_sh, r_w, m_torso)
        for x in range(int(cx - r_w), int(cx + r_w) + 1):
            c.px(x, bot - 1, 9, (0, 0.2, 0.98), BELT)
        c.px(int(cx), bot - 1, 10, (0, 0, 1), BUCKLE)
        if details and m_torso is TUNIC:
            if d == 0:                                                           # V-neck collar
                for i in range(3):
                    c.px(int(cx) - 1 + 0, top + 1 + i, 9, (0, 0.2, 1), TUNIC_DARK)
                    c.px(int(cx) - i, top + 1 + i // 2, 9, (0, 0.2, 1), TUNIC_DARK)
                    c.px(int(cx) + i, top + 1 + i // 2, 9, (0, 0.2, 1), TUNIC_DARK)
            if d != 1:                                                           # pouch on the hip
                px0 = int(cx - r_w) if d == 0 else int(cx - r_w)
                c.box(px0, px0 + 2, bot - 2, 1, bot + 1, BELT, z=12)
    elif layer == "skirt" and skirt_m:
        cx, top, bot, r_sh, r_w = g["torso"]
        for y in range(21, 28):
            spread = r_w + 0.8 + (y - 21) * 0.5
            c.cylinder(cx, spread, y, y, skirt_m, cap_ry=0.5, z=0)
        c.occlude(0, 21, 31, 21, 0.6)
    return c


def body_part(layer, d, f):
    return _part(layer, d, f).render()


# ---------------- skin parts: head with a face, hands ----------------

def _put(img, x, y, rgb):
    x, y = int(x) + CELL_PAD, int(y) + CELL_PAD
    if 0 <= x < img.width and 0 <= y < img.height and img.getpixel((x, y))[3]:
        img.putpixel((x, y), rgb + (255,))


def head_part(d, f, race, tone):
    """Head with a face. Race: ears (elf, goblin), tusks (orc), eyes (undead, felin, goblin), nose
    (dwarf, goblin). Sex: lashes and fuller lips for women. Normal irises are painted in EYE_KEY and
    recoloured in game to the chosen eye colour."""
    skin = SKIN_TONES[tone]
    m = Mat(skin)
    g = skel(d, f)
    cx, cy = g["head"]
    fem = SEX == "f"
    c = Canvas(32, 32, pad=CELL_PAD)
    wide = {"orc": 0.6, "dwarf": 0.3, "goblin": 0.2}.get(race, 0.0) - (0.2 if fem else 0.0)
    c.sphere(cx - 0.5, cy, (6.4 if d != 2 else 6.0) + wide, 6.0, m, keep=lambda x, y: y <= cy + 5)
    if race == "orc":
        c.sphere(cx - 0.5, cy + 3.2, 5.6 - (0.6 if fem else 0), 2.6, m, z=1)
    ear_lines = []
    if race in ("elf", "goblin"):               # острые уши: лист с широким основанием, под волосами
        length, rise, r0 = (5.4, 4.4, 1.5) if race == "elf" else (6.0, 1.6, 2.0)
        if d == 2:
            ears = [((cx - 1.8, cy + 1.2), (cx - 1.8 - length * 1.05, cy + 1.2 - rise * 1.1), 7)]
        else:
            ears = [((cx - 5.8 - wide, cy + 1.2), (cx - 5.8 - wide - length, cy + 1.2 - rise), -1),
                    ((cx + 4.8 + wide, cy + 1.2), (cx + 4.8 + wide + length, cy + 1.2 - rise), -1)]
        for (bx, by), (tx, ty), z in ears:
            for i in range(10):
                t = i / 9
                rr = r0 * (1 - t) ** 0.8 + 0.35
                c.sphere(bx + (tx - bx) * t, by + (ty - by) * t, rr, rr * 0.9, m, z=z + t)
            ear_lines.append(((bx, by), (tx, ty)))
    elif race != "felin":
        if d == 2:
            c.sphere(cx - 2.0, cy + 0.6, 1.5, 1.9, m, z=7)
        else:
            c.sphere(cx - 6.6 - wide, cy + 0.8, 1.4, 1.9, m, z=-1)
            c.sphere(cx + 5.6 + wide, cy + 0.8, 1.4, 1.9, m, z=-1)
    if race == "goblin":                                                          # крупный нос
        if d == 0:
            c.sphere(cx - 1.0, cy + 2.8, 1.5, 1.3, m, z=9)
        elif d == 2:
            c.sphere(cx + 5.6, cy + 2.6, 1.6, 1.2, m, z=9)
    img = c.render(ambient=0.42)
    dark = (36, 26, 40)
    white = (246, 244, 250)
    iris = EYE_KEY
    blush = tuple(min(255, int(v * k)) for v, k in zip(skin, (1.12, 0.86, 0.86)))
    shade_ = tuple(int(v * 0.78) for v in skin)
    lip = tuple(int(v * k) for v, k in zip(skin, (0.9, 0.66, 0.66) if fem else (0.74, 0.56, 0.56)))
    tusk = (238, 232, 210)
    for (bx, by), (tx, ty) in ear_lines:                                         # ушная раковина
        for t in (0.2, 0.35, 0.5):
            _put(img, bx + (tx - bx) * t, by + (ty - by) * t + 0.5, shade_)

    def eye(ex, ey, lash_side):
        _put(img, ex, ey, iris)
        _put(img, ex + 1, ey, white)
        _put(img, ex, ey + 1, iris)
        _put(img, ex + 1, ey + 1, dark)
        if race in ("undead",):
            _put(img, ex + 1, ey + 1, iris)
        if fem:                                                                 # ресницы
            _put(img, ex + lash_side, ey - 1, dark)

    if d == 0:
        eye(cx - 4, cy + 1, -1)
        eye(cx + 1, cy + 1, 1)
        if race not in ("goblin",):
            _put(img, cx - 1, cy + 3, (226, 140, 150) if race == "felin" else shade_)
        if race == "dwarf":
            _put(img, cx - 2, cy + 3, shade_)
        _put(img, cx - 2, cy + 4, lip)
        _put(img, cx - 1, cy + 4, lip)
        if race == "orc":
            for px, py in ((cx - 3, cy + 4), (cx + 1, cy + 4), (cx - 3, cy + 3), (cx + 1, cy + 3)):
                _put(img, px, py, tusk)
        elif race == "goblin":
            _put(img, cx - 2, cy + 5, tusk)
            _put(img, cx, cy + 5, tusk)
        elif race != "undead":
            _put(img, cx - 5, cy + 3, blush)
            _put(img, cx + 2, cy + 3, blush)
    elif d == 2:
        eye(cx + 2, cy + 1, 1)
        _put(img, cx + 5, cy + 3, shade_)
        if race == "dwarf":
            _put(img, cx + 6, cy + 3, shade_)
        _put(img, cx + 3, cy + 4, lip)
        if race == "orc":
            _put(img, cx + 4, cy + 3, tusk)
            _put(img, cx + 4, cy + 4, tusk)
        elif race == "goblin":
            _put(img, cx + 4, cy + 5, tusk)
        elif race != "undead":
            _put(img, cx + 1, cy + 3, blush)
    return img


def marks_part(d, f, kind):
    """Face markings over the head. Shared: scar, freckles, war paint. Racial: elf leaf tattoo, dwarf soot
    and runes, orc tribal stripes, undead stitches and bare jaw, felin whiskers and stripes, goblin earrings."""
    if d == 1:
        return None
    g = skel(d, f)
    cx, cy = g["head"]
    img = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    front = d == 0
    pts = []                                    # (x, y, цвет)

    def add(col, front_pts, side_pts):
        for (x, y) in (front_pts if front else side_pts):
            pts.append((cx + x, cy + y, col))

    if kind == "scar":
        add((150, 60, 60), [(2, -1), (3, 0), (3, 2), (4, 3)], [(3, -1), (4, 0), (4, 3)])
    elif kind == "freckles":
        add((150, 90, 60), [(-5, 3), (-4, 4), (2, 4), (3, 3)], [(1, 3), (2, 4)])
    elif kind == "warpaint":
        add((190, 40, 50), [(-5 + i, 3) for i in range(3)] + [(1 + i, 3) for i in range(3)], [(1 + i, 3) for i in range(3)])
    elif kind == "leafmark":                    # эльфийские листья: под глазами и точка на лбу
        add((60, 176, 128), [(-4, 3), (-4, 4), (2, 3), (2, 4), (-1, -1)], [(2, 3), (2, 4), (3, -1)])
    elif kind == "soot":                        # копоть кузни
        add((74, 66, 64), [(-6, 2), (-5, 3), (-6, 3), (3, 2), (4, 3), (-1, -1), (0, -1)], [(1, 2), (1, 3), (2, 3), (4, -1)])
    elif kind == "runes":                       # светящиеся руны
        add((96, 176, 255), [(-2, -1), (0, -1), (-1, -2), (-6, 2), (-6, 3), (4, 2), (4, 3)], [(2, -1), (4, -1), (3, -2), (1, 2), (1, 3)])
    elif kind == "tribal":                      # чёрные полосы орка
        add((34, 44, 34), [(-6, 1), (-6, 2), (-5, 3), (4, 1), (4, 2), (3, 3), (-2, 5), (0, 5), (-1, -1)],
            [(1, 1), (1, 2), (2, 3), (4, 5), (3, -1)])
    elif kind == "stitches":                    # шов через лицо
        dark = (58, 36, 52)
        if front:
            add(dark, [(3, y) for y in range(-1, 5)] + [(2, 0), (4, 0), (2, 3), (4, 3)], [])
        else:
            add(dark, [], [(0, y) for y in range(0, 5)] + [(-1, 1), (1, 1), (-1, 3), (1, 3)])
    elif kind == "bones":                       # оголённая челюсть
        bone, gap = (222, 214, 194), (60, 44, 52)
        add(bone, [(1, 3), (2, 3), (3, 3), (1, 4), (3, 4)], [(2, 3), (3, 3), (2, 4)])
        add(gap, [(2, 4)], [(3, 4)])
    elif kind == "whiskers":                    # вибриссы кошколюда торчат за щёки
        col = (206, 200, 192)
        add(col, [(-6, 3), (-7, 2), (-6, 4), (-7, 5), (5, 3), (6, 2), (5, 4), (6, 5)],
            [(5, 3), (6, 2), (5, 4), (6, 5)])
    elif kind == "stripes":                     # полосы на лбу и щеках
        col = (104, 70, 48)
        add(col, [(-6, 1), (-5, 2), (-6, 3), (-5, 4), (4, 1), (3, 2), (4, 3), (3, 4), (-2, -1), (0, -1)],
            [(0, 2), (1, 3), (0, 4), (3, -1), (5, -1)])
    elif kind == "earrings":                    # золотые кольца в длинных ушах
        gold = (236, 190, 70)
        add(gold, [(-9, 2), (-10, 3), (-8, 3), (-9, 4), (8, 2), (7, 3), (9, 3), (8, 4)],
            [(-5, 2), (-6, 3), (-4, 3), (-5, 4)])
    for (x, y, col) in pts:
        _put_any(img, x, y, col)
    return img

def beard_part(d, f, style, color):
    """Facial hair in the hair colour: full beard (dwarves always), moustache or stubble."""
    if d == 1:
        return None
    m = Mat(HAIR_COLORS[color], tex=tex_strands)
    g = skel(d, f)
    cx, cy = g["head"]
    c = Canvas(32, 32, pad=CELL_PAD)
    if style == "stubble":
        img = c.render()
        dark = tuple(int(v * 0.55) for v in HAIR_COLORS[color])
        pts = [(cx - 5 + i, cy + 4 + (i % 2)) for i in range(0, 9, 2)] if d == 0 else [(cx + 1 + i, cy + 4 + (i % 2)) for i in range(0, 5, 2)]
        for (x, y) in pts:
            _put_any(img, x, y, dark)
        return img
    if style == "goatee":                                   # бородка клинышком на подбородке
        if d == 0:
            c.sphere(cx - 0.5, cy + 6.4, 1.6, 2.2, m, keep=lambda x, y: y >= cy + 4.6)
        else:
            c.sphere(cx + 3.5, cy + 6.2, 1.4, 2.0, m, keep=lambda x, y: y >= cy + 4.6)
        return c.render()
    if style in ("full", "braided"):          # растёт от висков по линии челюсти — рот открыт
        if d == 0:
            c.sphere(cx - 0.5, cy + 4.6, 6.0, 4.6, m,
                     keep=lambda x, y: y >= (cy + 1.5 if abs(x + 0.5 - (cx - 0.5)) >= 4.6 else cy + 4.6))
        else:
            c.capsule(cx - 1.0, cy + 1.0, cx + 1.0, cy + 4.0, 1.3, m, z=2)        # бакенбард от уха
            c.sphere(cx + 2.8, cy + 5.0, 3.6, 3.8, m,
                     keep=lambda x, y: y >= (cy + 2.5 if x < cx + 2 else cy + 4.6))
    if style == "braided":                                  # дварфийские косички с золотыми бусинами
        bead = Mat((226, 184, 92), spec=0.9)
        for bx in ((cx - 2.5, cx + 1.5) if d == 0 else (cx + 3.5,)):
            c.capsule(bx, cy + 7.5, bx + (0.0 if d == 0 else 0.5), cy + 12, 1.1, m, z=5)
            c.sphere(bx + (0.0 if d == 0 else 0.3), cy + 10.4, 1.3, 0.8, bead, z=6)
    if d == 0:
        c.capsule(cx - 4, cy + 3.6, cx + 2.5, cy + 3.6, 0.9, m, z=4)
    else:
        c.capsule(cx + 2, cy + 3.6, cx + 5.5, cy + 3.6, 0.8, m, z=4)
    return c.render()

def cat_ears_part(d, f, color):
    """Кошачьи уши растут из причёски: та же фактура прядей, слегка разведены в стороны.
    Низ уха утоплен в волосы и срезан без контура — нет шва «картинка на картинке»."""
    m = Mat(HAIR_COLORS[color], tex=tex_strands)
    inner = Mat((214, 140, 150))
    g = skel(d, f)
    cx, cy = g["head"]
    c = Canvas(32, 32, pad=CELL_PAD)
    spots = [(-4.0, -1), (3.0, 1)] if d != 2 else [(-1.5, -1)]
    for (dx, side) in spots:
        bx, by = cx - 0.5 + dx, cy - 4.0                    # основание — внутри волос
        tx, ty = bx + side * (1.6 if d != 2 else -1.0), cy - 10.5
        for i in range(9):                                   # сужающийся клин от основания к кончику
            t = i / 8
            c.sphere(bx + (tx - bx) * t, by + (ty - by) * t, 2.7 * (1 - t) + 0.45, 1.2, m, z=2 + t)
        if d == 0:
            for i in range(5):
                t = 0.25 + i / 8
                c.sphere(bx + (tx - bx) * t, by + (ty - by) * t + 0.3, 1.3 * (1 - t) + 0.3, 0.9, inner, z=4)
    img = c.render()
    cut = int(cy - 5) + CELL_PAD                             # ниже — волосы: срезаем вместе с контуром
    px = img.load()
    for yy in range(cut + 1, img.height):
        for xx in range(img.width):
            px[xx, yy] = (0, 0, 0, 0)
    return img


def tail_part(d, f, color):
    """Felin tail: sways with the walk; behind the hip from the front, over the back from behind."""
    m = Mat(HAIR_COLORS[color], tex=tex_strands)
    g = skel(d, f)
    sway = [0, 1, 0, -1][(f - 2) % 4] if (g["walk"] or g["run"]) else (1 if f == 1 else 0)
    c = Canvas(32, 32, pad=CELL_PAD)
    if d == 2:
        pts = [(13, 20), (9, 18 + sway), (7, 13 + sway), (8, 10 + sway)]
    elif d == 1:
        pts = [(16, 21), (17 + sway, 24), (20 + sway, 23), (22 + sway, 19)]
    else:
        pts = [(19, 20), (22, 19 + sway), (24, 15 + sway), (23, 12 + sway)]
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        c.capsule(x0, y0, x1, y1, 1.3, m, z=1)
    return c.render()

def hands_part(layer, d, f, tone):
    m = Mat(SKIN_TONES[tone])
    g = skel(d, f)
    c = Canvas(32, 32, pad=CELL_PAD)
    arms = g["arms"]
    if d == 2:
        pick = [arms[0]] if layer == "hands_back" else [arms[1]]
    else:
        pick = [] if layer == "hands_back" else arms
    for a in pick:
        x, y, r, swing = a
        if a is arms[1] and g["attack"]:
            hx, hy = g["hand"]
        else:
            hx, hy = x, y + (4.6 if g["run"] else 5.6) + swing
        c.sphere(hx, hy, 1.7, 1.6, m, z=4)
    img = c.render(ambient=0.4)
    if layer == "hands_back":
        px = img.load()
        for yy in range(img.height):
            for xx in range(img.width):
                p = px[xx, yy]
                if p[3]:
                    px[xx, yy] = (int(p[0] * 0.75), int(p[1] * 0.75), int(p[2] * 0.75), p[3])
    return img


# ---------------- hair ----------------

def hair_back_part(d, f, style, color):
    """Волосы, которые спадают ЗА плечи (вид спереди): рисуются под телом и руками,
    чтобы длинные пряди не закрывали плечи, как шлем."""
    if d != 0 or style not in ("long", "braid"):
        return None
    m = Mat(HAIR_COLORS[color], tex=tex_strands)
    g = skel(d, f)
    cx, cy = g["head"]
    c = Canvas(32, 32, pad=CELL_PAD)
    if style == "braid":                      # коса лежит на спине: спереди видно лишь кончик за плечом
        for i in range(4):
            c.sphere(cx + 4.5 + i * 0.4, cy + 3 + i * 1.8, 1.4 - i * 0.1, 1.1, m, z=-4)
        return c.render()
    for sgn in (-1, 1):
        c.capsule(cx - 0.5 + sgn * 5.9, cy + 1, cx - 0.5 + sgn * 6.6, cy + 10, 1.8, m, z=-4)
    return c.render()


def _bare_hair(c, d, cx, cy, style, m):
    """Лысина, ирокез (орк, гоблин), узел на макушке, клочки (гоблин), редкие пряди (нежить)."""
    hx = cx - 0.5 if d != 2 else cx - 1.0                  # центр черепа
    if style == "mohawk":
        if d == 2:                                          # гребень от лба к затылку
            for a in (65, 90, 115, 140, 165):
                r = math.radians(a)
                c.capsule(hx + 5.0 * math.cos(r), cy - 0.5 - 5.0 * math.sin(r),
                          hx + 9.2 * math.cos(r), cy - 0.5 - 9.2 * math.sin(r), 1.3, m, z=3)
        else:
            for (tx, ty) in ((-1.4, -9.4), (0.0, -10.8), (1.4, -9.4)):       # веер острых прядей
                c.capsule(hx, cy - 5.0, hx + tx, cy + ty, 0.8, m, z=3)
            if d == 1:
                c.capsule(hx, cy - 6, hx, cy + 2.0, 0.9, m, z=3)
    elif style == "topknot":
        kx = hx if d != 2 else hx - 1.5
        c.capsule(kx, cy - 5, kx, cy - 7.5, 1.3, m, z=3)
        c.sphere(kx, cy - 9.0, 2.3, 2.0, m, z=4)
        tie = Mat((160, 40, 50))
        for i in (-1, 0, 1):
            c.px(kx + i, cy - 7, 20, (0, 0, 1), tie)
    elif style == "tufts":
        strands = {0: [(-3, -5, -5.5, -9.5), (-0.5, -6, 0, -10.5), (2, -5, 4.5, -9)],
                   1: [(-3, -5, -5, -9), (-0.5, -6, -1, -10.5), (2, -5, 4, -9.5)],
                   2: [(-1, -5.5, -2.5, -10), (-4, -4, -7.5, -7.5), (1.5, -5.5, 3, -9.5)]}[d]
        for (x0, y0, x1, y1) in strands:
            c.capsule(cx + x0, cy + y0, cx + x1, cy + y1, 0.9, m, z=3)
    elif style == "wisps":
        strands = {0: [(-5.8, -3, -6.8, 6), (4.8, -3, 5.8, 6), (0, -6, 1.5, -8.5)],
                   1: [(-3, -4, -3.5, 7), (-0.5, -5, -0.5, 8), (2, -4, 2.5, 7)],
                   2: [(-3, -4.5, -5, 6), (-5.5, -2, -7, 5), (0, -6, 1, -8.5)]}[d]
        for (x0, y0, x1, y1) in strands:
            c.capsule(cx + x0, cy + y0, cx + x1, cy + y1, 0.8, m, z=3)


def _flat_hair(c, d, cx, cy, style, color):
    """Гладкие причёски по форме головы (голова: центр cx-0.5, радиусы 6.4/6.0 x 6.0):
    короткая стрижка, зализанные назад (блестят), прямые гладкие до плеч."""
    m = Mat(HAIR_COLORS[color], spec=0.7) if style == "slick" else Mat(HAIR_COLORS[color], tex=tex_strands)
    line = cy - (3.2 if style == "slick" else 2.6)          # линия волос надо лбом
    if d == 0:
        c.sphere(cx - 0.5, cy - 0.3, 6.7, 6.0, m,
                 keep=lambda x, y: y <= (cy + 0.5 if (x < cx - 5.6 or x > cx + 4.6) else line))
    elif d == 1:
        c.sphere(cx - 0.5, cy - 0.2, 6.7, 6.1, m, keep=lambda x, y: y <= cy + (4.0 if style == "slick" else 3.0))
    else:
        c.sphere(cx - 0.6, cy - 0.3, 6.3, 6.0, m,
                 keep=lambda x, y: y <= (line if x > cx + 0.5 else cy + 2.5))
    if style == "straight":                                  # прямые пряди, плоские, не шире головы
        if d == 0:
            for sgn in (-1, 1):
                c.capsule(cx - 0.5 + sgn * 5.9, cy - 1, cx - 0.5 + sgn * 6.1, cy + 7, 1.2, m, z=4)
        elif d == 1:
            c.capsule(cx - 0.5, cy, cx - 0.5, cy + 8, 4.6, m, z=-2)
        else:
            c.capsule(cx - 3.8, cy - 1, cx - 4.2, cy + 7.5, 2.0, m, z=-2)


def hair_part(d, f, style, color):
    m = Mat(HAIR_COLORS[color], tex=tex_strands)
    g = skel(d, f)
    cx, cy = g["head"]
    c = Canvas(32, 32, pad=CELL_PAD)

    def fringe_down(x, y):                    # чёлка выше бровей: лоб и глаза открыты
        bang = cy - 2.4 + (1.0 if (x % 3 == 0) else 0.0)
        side = x < cx - 5.5 or x > cx + 4.5
        return y <= (cy + 1.5 if side else bang)

    if style in BARE_STYLES:
        _bare_hair(c, d, cx, cy, style, m)
    elif style in FLAT_STYLES:
        _flat_hair(c, d, cx, cy, style, color)
    elif d == 0:
        c.sphere(cx - 0.5, cy - 1.0, 6.8, 6.0, m, keep=fringe_down)
    elif d == 1:
        c.sphere(cx - 0.5, cy - 0.4, 6.9, 6.3, m, keep=lambda x, y: y <= cy + 4)
    else:
        c.sphere(cx - 1.0, cy - 1.0, 6.5, 5.9, m,
                 keep=lambda x, y: y <= (cy - 2.2 + (1.0 if x % 3 == 0 else 0)) if x > cx + 0.5 else y <= cy + 3.0)
    if style == "long":
        if d == 0:                            # у лица — короткие пряди, остальное за плечами (hair_back_part)
            for sgn in (-1, 1):
                c.capsule(cx - 0.5 + sgn * 5.8, cy - 1, cx - 0.5 + sgn * 6.0, cy + 3, 1.2, m, z=4)
        elif d == 1:
            c.capsule(cx - 0.5, cy, cx - 0.5, cy + 11, 5.2, m, z=-2)
        else:
            c.capsule(cx - 4.0, cy - 1, cx - 4.6, cy + 9, 2.6, m, z=-2)
    elif style == "tail":
        tie = Mat((160, 40, 50))
        if d == 1:
            c.capsule(cx - 0.5, cy - 1, cx - 0.5, cy + 9, 1.9, m, z=6)
            c.px(cx - 1, cy - 1, 20, (0, 0, 1), tie)
            c.px(cx, cy - 1, 20, (0, 0, 1), tie)
        elif d == 2:
            c.capsule(cx - 6.5, cy - 2.5, cx - 9.0, cy + 5, 1.8, m, z=-1)
            c.px(cx - 7, cy - 2, 20, (0, 0, 1), tie)
        else:
            c.capsule(cx + 5.5, cy - 4, cx + 7.5, cy + 3, 1.5, m, z=-3)
    elif style == "braid":                                                  # коса
        if d == 1:
            for i in range(5):
                c.sphere(cx - 0.5, cy + 2 + i * 2.2, 1.9 - i * 0.12, 1.4, m, z=6)
        elif d == 2:                          # спереди коса за спиной — в hair_back_part
            for i in range(5):
                c.sphere(cx - 5.0 - i * 0.3, cy + 1 + i * 2.0, 1.7 - i * 0.1, 1.3, m, z=-1)
    elif style == "bob":                                                    # каре до подбородка
        if d == 0:
            for sgn in (-1, 1):
                c.capsule(cx - 0.5 + sgn * 5.9, cy - 2, cx - 0.5 + sgn * 6.1, cy + 3.5, 1.3, m, z=4)
        elif d == 1:
            c.capsule(cx - 0.5, cy, cx - 0.5, cy + 4.5, 6.2, m, z=-2)
        else:
            c.capsule(cx - 3.5, cy - 1, cx - 3.8, cy + 4.5, 3.0, m, z=-2)
    elif style == "bun":                                                    # пучок
        by = cy - 7.0
        bx = cx - 0.5 if d != 2 else cx - 3.5
        c.sphere(bx, by, 2.8, 2.6, m, z=-1 if d == 0 else 4)
    elif style == "spiky":
        tips = [(-6, -6), (-3, -9), (1, -9.5), (4, -7), (6.5, -3.5)] if d != 2 else [(-5, -7), (-1.5, -9), (2, -8), (-7.5, -3)]
        for (dx, dy) in tips:
            c.capsule(cx - 0.5 + dx * 0.45, cy - 1 + dy * 0.45, cx - 0.5 + dx, cy - 1 + dy, 1.2, m, z=3)
    img = c.render()
    brow = tuple(int(v * 0.6) for v in HAIR_COLORS[color])
    if d == 0:                                                                   # eyebrows follow hair colour
        for bx in (cx - 4, cx + 1):
            _put_any(img, bx, cy - 0, brow)
            _put_any(img, bx + 1, cy - 0, brow)
    elif d == 2:
        _put_any(img, cx + 2, cy, brow)
        _put_any(img, cx + 3, cy, brow)
    return img


def _put_any(img, x, y, rgb):
    x, y = int(x) + CELL_PAD, int(y) + CELL_PAD
    if 0 <= x < img.width and 0 <= y < img.height:
        img.putpixel((x, y), rgb + (255,))


# ---------------- gear ----------------

def _trim(c, pts, trim):
    if trim:
        m = Mat(trim, spec=0.6)
        for (x, y) in pts:
            if 0 <= x < 32 and 0 <= y < 32 and c.mat[y + c.pad, x + c.pad] >= 0:
                c.px(x, y, 50, (0, -0.3, 0.95), m)


def gear_part(base, layer, d, f, trim=None):
    if base in WEAPONS:
        return weapon_part(base, layer, d, f, trim)
    g = skel(d, f)
    cx, cy = g["head"]
    if base == "armor":
        if layer not in ("torso", "arms_front", "arms_back"):
            return None
        c = _part(layer, d, f, m_torso=STEEL, details=False)
        if layer == "torso":
            tcx, top, bot, r_sh, r_w = g["torso"]
            if d != 2:
                for sx in (tcx - r_sh - 0.3, tcx + r_sh + 0.3):
                    c.sphere(sx, top + 1.8, 2.7, 2.1, STEEL, z=8)
                for y in range(top + 3, bot - 1):
                    c.px(int(tcx), y, 9, (0, -0.1, 1), STEEL)
                _trim(c, [(int(tcx - r_sh - 2) + k, top + 3) for k in range(4)] + [(int(tcx + r_sh - 1) + k, top + 3) for k in range(4)], trim)
            else:
                c.sphere(tcx - 0.5, top + 1.8, 2.9, 2.1, STEEL, z=8)
                _trim(c, [(int(tcx - 2) + k, top + 3) for k in range(5)], trim)
            _trim(c, [(int(tcx), bot - 1)], trim or (230, 180, 80))
        return c.render()
    if base == "jerkin":                         # кожаная куртка следопыта и разбойника
        if layer not in ("torso", "arms_front", "arms_back"):
            return None
        c = _part(layer, d, f, m_torso=LEATHER, details=False)
        if layer == "torso":
            tcx, top, bot, r_sh, r_w = g["torso"]
            belt = Mat((70, 46, 30))
            for x in range(int(tcx - r_w - 1), int(tcx + r_w + 2)):
                c.px(x, bot - 3, 9, (0, 0, 1), belt)
            if d == 0:
                for y in range(top + 2, bot - 3, 2):
                    c.px(int(tcx), y, 9, (0, -0.2, 1), belt)       # шнуровка
            _trim(c, [(int(tcx), bot - 3)], trim or (200, 170, 90))
        return c.render()
    if base == "robe":
        if layer in ("torso", "arms_front", "arms_back"):
            c = _part(layer, d, f, m_torso=CLOTH, details=False)
            if layer == "torso":
                tcx, top, bot, r_sh, r_w = g["torso"]
                _trim(c, [(int(tcx), y) for y in range(top + 2, bot)], trim)
            return c.render()
        if layer == "skirt":
            c = _part("skirt", d, f, skirt_m=CLOTH)
            _trim(c, [(x, 27 + (1 if x % 3 == 0 else 0)) for x in range(6, 27)], trim)
            return c.render()
        return None
    if base == "boots":
        if layer != "feet":
            return None
        c = _part("feet", d, f, feet_m=LEATHER)
        for (x, top, r, lift) in g["legs"]:
            ly = 27 - max(0, lift)
            c.cylinder(x, r + 0.4, ly - 3, ly, LEATHER, cap_ry=0.7, z=3)
            _trim(c, [(int(x - 1) + k, ly - 3) for k in range(3)], trim)
        return c.render()
    if base == "dawn_crown":
        if layer != "hat":
            return None
        c = Canvas(32, 32, pad=CELL_PAD)
        for x in range(cx - 5, cx + 5):
            for y in (cy - 5, cy - 4):
                c.px(x, y, 30, (0, -0.4 if y == cy - 5 else 0.2, 0.9), GOLD)
        for sx in (cx - 5, cx - 2, cx + 1, cx + 4):
            c.px(sx, cy - 6, 30, (0, -0.6, 0.8), GOLD)
            c.px(sx, cy - 7, 30, (0, -0.8, 0.6), GOLD)
        if d != 1:
            c.px(cx - 1, cy - 4, 31, (0, 0, 1), GEM)
        return c.render()
    if layer != "headgear" or base not in ("helm", "hood"):
        return None
    c = Canvas(32, 32, pad=CELL_PAD)
    if base == "helm":
        c.sphere(cx - 0.5, cy - 0.4, 7.0, 6.5, STEEL)
        dark = Mat((26, 22, 34), emissive=True)
        if d == 0:
            for x in range(cx - 5, cx + 5):
                c.px(x, cy + 1, 20, (0, 0, 1), dark)
            for y in range(cy - 6, cy + 4):
                c.px(cx - 1, y, 21, (0, -0.1, 1), STEEL)
            _trim(c, [(cx - 1, y) for y in range(cy - 7, cy - 2)], trim)
        elif d == 2:
            for x in range(cx + 1, cx + 6):
                c.px(x, cy + 1, 20, (0, 0, 1), dark)
            _trim(c, [(cx - 2 + k, cy - 6) for k in range(4)], trim)
        else:
            _trim(c, [(cx - 1, y) for y in range(cy - 7, cy + 4)], trim)
    else:   # hood: open in front so the face (head layer) shows through
        if d == 0:
            face = lambda x, y: ((x + 0.5 - (cx - 0.5)) / 4.4) ** 2 + ((y + 0.5 - (cy + 1.8)) / 4.0) ** 2 > 1
        elif d == 2:
            face = lambda x, y: ((x + 0.5 - (cx + 2.5)) / 3.4) ** 2 + ((y + 0.5 - (cy + 1.8)) / 3.8) ** 2 > 1
        else:
            face = None
        c.sphere(cx - 0.5, cy, 7.4, 6.8, HOODC, keep=face)
        c.cylinder(cx - 0.5, 7.2, cy + 4, cy + 6, HOODC, cap_ry=1.0, z=-2)
        _trim(c, [(cx - 6 + k, cy + 6) for k in range(12)], trim)
    return c.render()


RARITY_TRIM = [None, (90, 200, 90), (80, 150, 255), (190, 110, 255), (255, 170, 40), (255, 60, 90)]


def sheet(fn):
    out = Image.new("RGBA", (CELL * len(FRAMES), CELL * len(DIRS)), (0, 0, 0, 0))
    any_px = False
    for d in range(len(DIRS)):
        for f in range(len(FRAMES)):
            cell = fn(d, f)
            if cell is not None:
                out.alpha_composite(cell, (f * CELL, d * CELL))
                any_px = True
    return out if any_px else None


# ---------------- weapons held in the hand ----------------

WEAPONS = {"sword": (11.0, 1.4), "axe": (11.0, 0.0), "dagger": (7.0, 1.1), "abyss_blade": (12.5, 1.9),
           "staff": (14.0, 0.0), "wand": (7.0, 0.0), "bow": (8.0, 0.0), "hammer": (11.0, 0.0)}
TIER_INDEX = {None: 0, (90, 200, 90): 1, (80, 150, 255): 2, (190, 110, 255): 3, (255, 170, 40): 4, (255, 60, 90): 5}


def weapon_part(base, layer, d, f, trim):
    """Weapon modelled from primitives at the skeleton's hand point; the hands layer is drawn over
    the grip so it is really held. Behind the body when facing up."""
    import weapons as W
    want = "weapon_back" if d == 1 else "weapon"
    if layer != want:
        return None
    tier = 5 if base == "abyss_blade" else TIER_INDEX.get(trim, 0)
    T = W.TIERS[tier]
    blade_m = Mat(T["blade"][2], spec=0.85)
    guard_m = Mat(T["guard"][1], spec=0.6)
    grip_m = Mat(T["grip"][1])
    g = skel(d, f)
    hx, hy = g["hand"]
    a = math.radians(g["angle"])
    ux, uy = math.cos(a), math.sin(a)
    px, py = -uy, ux
    length, width = WEAPONS[base]
    c = Canvas(32, 32, pad=CELL_PAD)
    if base in ("staff", "wand"):
        wood = Mat(W.WOOD[1]) if tier < 2 else grip_m
        tail = 5.0 if base == "staff" else 1.5
        c.capsule(hx - ux * tail, hy - uy * tail, hx + ux * length, hy + uy * length, 0.8, wood, z=1)
        orb = Mat(W.ORB[tier][2], emissive=True)
        ex, ey = hx + ux * (length + 1.5), hy + uy * (length + 1.5)
        if base == "staff":
            c.capsule(ex - px * 2.2, ey - py * 2.2, ex + px * 2.2, ey + py * 2.2, 0.6, guard_m, z=2)
            c.sphere(ex + ux * 0.8, ey + uy * 0.8, 2.0, 2.0, orb, z=4)
        else:
            c.sphere(ex, ey, 1.3, 1.6, orb, z=4)
    elif base == "bow":
        limb = Mat(W.WOOD[2]) if tier < 2 else blade_m
        pts = []
        for i in range(9):
            t = -1 + i / 4
            bulge = (1 - t * t) * 2.6
            pts.append((hx + px * t * length + ux * bulge, hy + py * t * length + uy * bulge))
        for a_, b_ in zip(pts, pts[1:]):
            c.capsule(a_[0], a_[1], b_[0], b_[1], 0.7, limb, z=2)
        c.capsule(pts[0][0], pts[0][1], pts[-1][0], pts[-1][1], 0.25, Mat((222, 214, 196)), z=1)
    elif base == "hammer":
        c.capsule(hx - ux * 2, hy - uy * 2, hx + ux * length, hy + uy * length, 0.8, grip_m, z=1)
        hx2, hy2 = hx + ux * (length - 1), hy + uy * (length - 1)
        c.blade(hx2 - px * 3.6, hy2 - py * 3.6, hx2 + px * 3.6, hy2 + py * 3.6, 3.2, blade_m, z=3, taper=0)
    elif base == "axe":
        c.capsule(hx - ux * 2, hy - uy * 2, hx + ux * length, hy + uy * length, 0.8, grip_m, z=1)
        hx2, hy2 = hx + ux * (length - 2.5), hy + uy * (length - 2.5)
        side = 1 if (d != 1) else -1
        c.blade(hx2 + px * 0.5 * side, hy2 + py * 0.5 * side, hx2 + px * 5 * side, hy2 + py * 5 * side, 2.6, blade_m, z=3, taper=0)
        c.blade(hx2 + px * 4 * side, hy2 + py * 4 * side, hx2 + px * 5.2 * side, hy2 + py * 5.2 * side, 3.4, blade_m, z=4, taper=0)
    else:
        c.capsule(hx - ux * 2.5, hy - uy * 2.5, hx + ux * 1.2, hy + uy * 1.2, 0.8, grip_m, z=1)
        c.sphere(hx - ux * 3.2, hy - uy * 3.2, 1.2, 1.2, guard_m, z=2)
        gx, gy = hx + ux * 1.8, hy + uy * 1.8
        gw = 2.4 + tier * 0.25
        c.capsule(gx - px * gw, gy - py * gw, gx + px * gw, gy + py * gw, 0.8, guard_m, z=3)
        c.blade(gx + ux * 0.8, gy + uy * 0.8, hx + ux * length, hy + uy * length, width * 0.75, blade_m, z=4)
        if T.get("gem"):
            c.px(gx, gy, 9, (0, 0, 1), Mat(T["gem"][1], emissive=True))
    img = c.render()
    if T["glow"]:
        W._halo(img, T["glow"], 150 if tier >= 4 else 100, wide=tier >= 4)
    return img
