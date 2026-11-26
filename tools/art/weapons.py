"""Weapon icons 32x32: every weapon type in 6 rarity tiers that read differently at a glance.

Tier 0 rusty iron, 1 clean steel + green wrap, 2 blue steel + sapphire, 3 violet enchanted
with runes and halo, 4 gold with ruby, wings and flames, 5 abyss black-red with veins and drips.
Shapes are built in a rotated (u, v) space along the 45° diagonal, then outlined.
"""
import math
from pixel import blank, put, outline, OUTLINE

TIERS = [
    {   # 0 common: rusty iron
        "blade": [(52, 46, 46), (92, 82, 78), (130, 118, 108), (160, 150, 138)],
        "guard": [(54, 50, 50), (88, 82, 80), (120, 112, 106)],
        "grip": [(60, 40, 30), (92, 64, 44)], "gem": None, "glow": None, "rust": True,
    },
    {   # 1 uncommon: clean steel, green wrap
        "blade": [(62, 72, 86), (112, 126, 142), (172, 186, 198), (228, 234, 240)],
        "guard": [(70, 78, 90), (120, 130, 144), (176, 186, 198)],
        "grip": [(40, 92, 52), (70, 140, 80)], "gem": None, "glow": None,
    },
    {   # 2 rare: blue steel, sapphire
        "blade": [(36, 56, 104), (64, 104, 166), (114, 166, 224), (204, 232, 255)],
        "guard": [(120, 128, 140), (178, 186, 198), (232, 236, 242)],
        "grip": [(36, 52, 104), (60, 86, 150)], "gem": [(40, 90, 200), (130, 190, 255)], "glow": None,
    },
    {   # 3 epic: violet enchanted, runes
        "blade": [(48, 26, 80), (96, 56, 146), (156, 106, 218), (226, 194, 255)],
        "guard": [(110, 80, 30), (168, 128, 52), (222, 186, 96)],
        "grip": [(56, 28, 72), (94, 50, 116)], "gem": [(120, 40, 170), (220, 140, 255)],
        "glow": (190, 110, 255), "runes": (240, 200, 255),
    },
    {   # 4 legendary: radiant gold, ruby, wings, flames
        "blade": [(150, 92, 26), (214, 150, 46), (250, 206, 96), (255, 246, 206)],
        "guard": [(140, 84, 20), (214, 160, 50), (255, 222, 120)],
        "grip": [(110, 30, 24), (170, 52, 40)], "gem": [(180, 20, 40), (255, 110, 120)],
        "glow": (255, 160, 40), "flames": True, "wings": True,
    },
    {   # 5 mythic: abyss
        "blade": [(22, 10, 18), (60, 14, 30), (140, 24, 52), (255, 84, 110)],
        "guard": [(54, 44, 66), (96, 82, 112), (150, 134, 168)],
        "grip": [(20, 14, 22), (46, 30, 44)], "gem": [(200, 10, 40), (255, 140, 150)],
        "glow": (255, 40, 80), "veins": (255, 70, 100), "drips": True, "wings": True,
    },
]

SQ2 = math.sqrt(2)


def _uv(x, y, ox, oy):
    dx, dy = x + 0.5 - ox, y + 0.5 - oy
    return (dx - dy) / SQ2, (dx + dy) / SQ2   # u along blade (towards top-right), v across


def _ramp(r, k):
    c = r[max(0, min(len(r) - 1, k))]
    return c + (255,)


def _halo(img, color, strength=150, wide=False):
    """Soft rarity glow outside the outline (1px, or 2px for legendary+)."""
    src = img.copy()
    steps = ((1, strength), (2, strength // 3)) if wide else ((1, strength),)
    for rad, a in steps:
        for y in range(img.height):
            for x in range(img.width):
                if src.getpixel((x, y))[3]:
                    continue
                near = False
                for dy in range(-rad, rad + 1):
                    for dx in range(-rad, rad + 1):
                        if abs(dx) + abs(dy) != rad:
                            continue
                        xx, yy = x + dx, y + dy
                        if 0 <= xx < img.width and 0 <= yy < img.height and src.getpixel((xx, yy))[3] > 200:
                            near = True
                if near and img.getpixel((x, y))[3] == 0:
                    img.putpixel((x, y), color + (a,))
        src = img.copy()


def _gem(img, x, y, gem, big=False):
    put(img, x, y, gem[0] + (255,))
    put(img, x + 1, y, gem[0] + (255,))
    put(img, x, y + 1, gem[0] + (255,))
    put(img, x + 1, y + 1, gem[0] + (255,))
    put(img, x, y, gem[1] + (255,))
    if big:
        for dx, dy in ((-1, 0), (2, 0), (0, -1), (1, -1), (0, 2), (1, 2), (-1, 1), (2, 1)):
            put(img, x + dx, y + dy, gem[0] + (255,))


def sword(tier: int, length_bonus=0, size=32):
    T = TIERS[tier]
    img = blank(size, size)
    ox, oy = 6.0, 26.0                      # hilt end (bottom-left)
    grip_end = 4.5
    guard_u = 5.5
    tip = min(24.5, 23.0 + tier * 0.3) + length_bonus
    half_w = 1.25 + (0.3 if tier >= 3 else 0.0) + (0.3 if tier >= 5 else 0.0)
    guard_w = 3.8 + tier * 0.4
    for y in range(size):
        for x in range(size):
            u, v = _uv(x, y, ox, oy)
            av = abs(v)
            if guard_u + 1.0 <= u <= tip:
                taper = min(1.0, (tip - u) / 4.0)
                w = half_w * (0.35 + 0.65 * taper)
                if av <= w:
                    k = 2 if v < -0.3 else (1 if v > 0.4 else 3)   # edge light / back dark / fuller
                    if av < 0.45 and tier >= 1:
                        k = 2 if tier < 3 else 1                     # fuller groove
                    if T.get("rust") and (x * 7 + y * 3) % 5 == 0:
                        k = 0
                    img.putpixel((x, y), _ramp(T["blade"], k))
            elif guard_u - 0.4 <= u <= guard_u + 1.0 and av <= guard_w:
                k = 2 if v < 0 else 1
                if av > guard_w - 1.0:
                    k = 0 if tier < 3 else 2
                img.putpixel((x, y), _ramp(T["guard"], k))
            elif 0.0 <= u < guard_u - 0.4 and av <= 0.95:
                k = 1 if (int(u * 1.6) % 2 == 0) else 0
                img.putpixel((x, y), _ramp(T["grip"], k))
            elif -1.8 <= u < 0.0 and av <= 1.4:
                img.putpixel((x, y), _ramp(T["guard"], 1 if v < 0 else 0))
    if T.get("wings"):
        # flared guard tips
        for s in (-1, 1):
            gx = ox + (guard_u * 1 + s * (guard_w + 1.2)) / SQ2
            gy = oy + (-guard_u + s * (guard_w + 1.2)) / SQ2
            put(img, round(gx), round(gy), T["guard"][2] + (255,))
            put(img, round(gx) - (1 if s > 0 else 0), round(gy) + (1 if s < 0 else 0), T["guard"][1] + (255,))
    outline(img)
    # ornaments after outline so they sit on top
    if T["gem"]:
        gx = round(ox + guard_u / SQ2 + 0.4)
        gy = round(oy - guard_u / SQ2 - 0.6)
        _gem(img, gx - 1, gy - 1, T["gem"], big=tier >= 4)
        put(img, round(ox - 1.2), round(oy), T["gem"][1] + (255,))   # pommel stone
    if T.get("runes"):
        for i in range(4):
            u = guard_u + 3.5 + i * 4.0
            put(img, round(ox + u / SQ2), round(oy - u / SQ2), T["runes"] + (255,))
    if T.get("veins"):
        for i in range(6):
            u = guard_u + 2.5 + i * 3.1
            v = 0.7 if i % 2 else -0.7
            put(img, round(ox + (u + v) / SQ2), round(oy + (-u + v) / SQ2), T["veins"] + (255,))
    if T["glow"]:
        _halo(img, T["glow"], 170 if tier >= 4 else 110, wide=tier >= 4)
    if T.get("flames"):
        tx, ty = round(ox + tip / SQ2), round(oy - tip / SQ2)   # flames hug the blade tip
        for (dx, dy) in ((0, 1), (2, 3), (-3, 0), (3, -1), (-5, 3)):
            put(img, tx + dx, ty + dy, (255, 200, 80, 255))
            put(img, tx + dx, ty + dy - 1, (255, 120, 30, 200))
    if T.get("drips"):
        for (x, y, n) in ((14, 19, 3), (19, 14, 2), (11, 22, 2)):
            for k in range(n):
                put(img, x, y + 2 + k, (200, 20, 50, 255 - k * 60))
    return img


def dagger(tier: int):
    img = sword(tier, length_bonus=-9)
    return img


def axe(tier: int, size=32):
    T = TIERS[tier]
    img = blank(size, size)
    ox, oy = 5.0, 27.0
    top = 23.0
    for y in range(size):
        for x in range(size):
            u, v = _uv(x, y, ox, oy)
            av = abs(v)
            if -1.0 <= u <= top and av <= 0.95:                     # haft
                k = 1 if v < 0 else 0
                ramp = T["grip"] if tier in (1, 2, 3, 4) else [(70, 48, 32), (112, 80, 52)]
                img.putpixel((x, y), _ramp(ramp, k))
            # fan-shaped head on the +v side near the top, widening towards the edge
            hu, hv = u - (top - 4.0), v
            reach = 6.5 + tier * 0.35
            if 0.6 <= hv <= reach:
                half = 1.6 + hv * 0.62
                edge = reach - abs(hu) * 0.18
                if abs(hu) <= half and hv <= edge:
                    k = 3 if hv > edge - 1.3 else (2 if hu < 0 else 1)
                    if T.get("rust") and (x * 5 + y * 7) % 4 == 0:
                        k = 0
                    img.putpixel((x, y), _ramp(T["blade"], k))
            if tier >= 3 and -4.0 <= hv <= -0.6 and abs(hu) <= 1.2 + (hv + 4.0) * 0.25:   # back spike
                img.putpixel((x, y), _ramp(T["blade"], 1))
    outline(img)
    if T["gem"]:
        hu0, hv0 = top - 4.0, 3.0
        cx = round(ox + (hu0 + hv0) / SQ2)
        cy = round(oy + (-hu0 + hv0) / SQ2)
        _gem(img, cx - 1, cy - 1, T["gem"], big=tier >= 4)
    if T.get("runes"):
        for i in range(3):
            u = 6.0 + i * 4.5
            put(img, round(ox + u / SQ2), round(oy - u / SQ2), T["runes"] + (255,))
    if T["glow"]:
        _halo(img, T["glow"], 170 if tier >= 4 else 110, wide=tier >= 4)
    if T.get("flames"):
        for (x, y) in ((25, 9), (23, 5), (26, 12)):
            put(img, x, y, (255, 200, 80, 255))
            put(img, x, y - 1, (255, 120, 30, 200))
    if T.get("drips"):
        for (x, y, n) in ((24, 18, 3), (21, 17, 2)):
            for k in range(n):
                put(img, x, y + k, (200, 20, 50, 255 - k * 60))
    return img


def abyss_blade():
    """Unique mythic: longer, wider, with an eye in the guard."""
    img = sword(5, length_bonus=2)
    put(img, 9, 21, (255, 230, 120, 255))
    return img


# ---------------- оружие классов: посох, жезл, лук, молот ----------------

WOOD = [(58, 38, 26), (92, 62, 40), (128, 92, 60), (160, 122, 84)]
ORB = [   # навершие посоха / кристалл жезла по редкости: тёмный, средний, светлый, блик
    [(70, 70, 84), (110, 112, 128), (150, 152, 168), (200, 204, 216)],
    [(30, 90, 50), (60, 150, 80), (120, 210, 130), (210, 255, 210)],
    [(30, 60, 150), (60, 110, 220), (120, 170, 255), (220, 240, 255)],
    [(70, 30, 120), (130, 70, 200), (190, 130, 255), (240, 220, 255)],
    [(160, 80, 10), (230, 150, 40), (255, 210, 100), (255, 250, 220)],
    [(90, 0, 20), (180, 20, 50), (255, 80, 110), (255, 210, 220)],
]


def _shaft(img, T, tier, ox, oy, u0, u1, half=0.95):
    ramp = WOOD if tier in (0, 1) else [T["grip"][0], T["grip"][1], WOOD[2], WOOD[3]]
    for y in range(img.height):
        for x in range(img.width):
            u, v = _uv(x, y, ox, oy)
            if u0 <= u <= u1 and abs(v) <= half:
                img.putpixel((x, y), _ramp(ramp, 1 if v < 0 else 0))


def _orb(img, cx, cy, r, ramp):
    for y in range(img.height):
        for x in range(img.width):
            dx, dy = x + 0.5 - cx, y + 0.5 - cy
            d = (dx * dx + dy * dy) ** 0.5
            if d <= r:
                k = 3 if (dx < -r * 0.2 and dy < -r * 0.2 and d < r * 0.55) else (2 if dx + dy < 0 else (1 if d < r * 0.8 else 0))
                img.putpixel((x, y), _ramp(ramp, k))


def _finish(img, T, tier):
    if T["glow"]:
        _halo(img, T["glow"], 170 if tier >= 4 else 110, wide=tier >= 4)
    return img


def staff(tier: int, size=32):
    """Длинный посох, на конце — светящаяся сфера в оправе."""
    T = TIERS[tier]
    img = blank(size, size)
    ox, oy = 4.0, 28.0
    _shaft(img, T, tier, ox, oy, -1.0, 24.0)
    for k in (8.0, 16.0):                       # обмотки
        for y in range(size):
            for x in range(size):
                u, v = _uv(x, y, ox, oy)
                if abs(u - k) <= 0.7 and abs(v) <= 1.2:
                    img.putpixel((x, y), _ramp(T["guard"], 1))
    cu = 26.0
    cx, cy = ox + cu / SQ2, oy - cu / SQ2
    for s in (-1, 1):                           # рожки оправы
        put(img, round(cx + s * 3), round(cy + 1), T["guard"][1] + (255,))
        put(img, round(cx + s * 3), round(cy), T["guard"][2] + (255,))
    outline(img)
    _orb(img, cx, cy, 3.0 + (0.5 if tier >= 3 else 0.0), ORB[tier])
    return _finish(img, T, tier)


def wand(tier: int, size=32):
    """Короткий жезл с кристаллом."""
    T = TIERS[tier]
    img = blank(size, size)
    ox, oy = 8.0, 24.0
    _shaft(img, T, tier, ox, oy, -1.0, 13.0, half=0.8)
    for y in range(size):
        for x in range(size):
            u, v = _uv(x, y, ox, oy)
            if 13.0 <= u <= 19.5 and abs(v) <= max(0.0, 2.2 - abs(u - 15.5) * 0.6):   # ромб кристалла
                img.putpixel((x, y), _ramp(ORB[tier], 3 if v < -0.6 else (2 if u < 15.5 else 1)))
            elif 11.5 <= u < 13.0 and abs(v) <= 2.0:
                img.putpixel((x, y), _ramp(T["guard"], 2 if v < 0 else 1))
    outline(img)
    return _finish(img, T, tier)


def bow(tier: int, size=32):
    """Лук по диагонали: изогнутые плечи и тетива."""
    T = TIERS[tier]
    img = blank(size, size)
    ox, oy = 4.0, 28.0
    L = 31.0
    ramp = WOOD if tier in (0, 1) else T["blade"]
    for y in range(size):
        for x in range(size):
            u, v = _uv(x, y, ox, oy)
            if 0.0 <= u <= L:
                t = (u - L / 2) / (L / 2)
                arc = 5.2 * (1 - t * t)               # плечи выгибаются в сторону −v
                if abs(-v - arc) <= 0.95 - abs(t) * 0.25:
                    img.putpixel((x, y), _ramp(ramp, 2 if v > -arc else 1))
                if abs(t) < 0.12 and abs(-v - arc) <= 1.5:
                    img.putpixel((x, y), _ramp(T["grip"], 1))     # рукоять
    outline(img)
    for i in range(1, 30):                         # тетива поверх обводки
        u = 0.6 + i * (L - 1.2) / 30
        put(img, round(ox + u / SQ2), round(oy - u / SQ2), (220, 214, 196, 255))
    if T["gem"]:
        cu, cv = L / 2, -6.0
        _gem(img, round(ox + (cu + cv) / SQ2) - 1, round(oy + (-cu + cv) / SQ2) - 1, T["gem"], big=tier >= 4)
    return _finish(img, T, tier)


def hammer(tier: int, size=32):
    """Боевой молот паладина: рукоять и тяжёлое оголовье."""
    T = TIERS[tier]
    img = blank(size, size)
    ox, oy = 6.0, 26.0
    _shaft(img, T, tier, ox, oy, -1.0, 19.0)
    hu = 19.5
    for y in range(size):
        for x in range(size):
            u, v = _uv(x, y, ox, oy)
            if abs(u - hu) <= 3.2 and abs(v) <= 5.5 + tier * 0.2:
                k = 3 if (abs(v) > 4.6 and u < hu) else (2 if u < hu else 1)
                if T.get("rust") and (x * 5 + y * 3) % 5 == 0:
                    k = 0
                img.putpixel((x, y), _ramp(T["blade"], k))
            elif -2.2 <= u < -0.6 and abs(v) <= 1.5:
                img.putpixel((x, y), _ramp(T["guard"], 1))
    outline(img)
    if T["gem"]:
        _gem(img, round(ox + hu / SQ2) - 1, round(oy - hu / SQ2) - 1, T["gem"], big=tier >= 4)
    return _finish(img, T, tier)
