"""Затопленная шахта: пол, скальные стены с крепью, рельсы, арена Стража, вход у Пристани.

Запуск:  python tools/art/mine.py [--preview PATH]
Геометрия берётся из scripts/adventure_sites.gd (MINE, MINE_WALLS, MINE_EXIT) — меняя её там, перегенерируй.
Пишет: assets/custom/world/mine_floor.png, mine_gate.png и mine.json (фонари и предметы с коллизией).
"""
import json
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "custom" / "world"
SRC = (ROOT / "scripts" / "adventure_sites.gd").read_text(encoding="utf-8")


def _nums(text):
    return [float(v) for v in re.findall(r"[-\d.]+", text)]


MINE = _nums(re.search(r"MINE := Rect2\(([^)]*)\)", SRC).group(1))
WALLS = [_nums(m) for m in re.findall(r"Rect2\(([^)]*)\)", re.search(r"MINE_WALLS := \[(.*?)\]", SRC, re.S).group(1))]
EXIT = _nums(re.search(r"MINE_EXIT := Vector2\(([^)]*)\)", SRC).group(1))
X0, Y0, W, H = [int(v) for v in MINE]
TOP_FACE = 34                     # северная стена: верх скалы + освещённый откос (непроходимо, см. world_data.gd)
ARENA = (3400, 300, 84)           # круг Колокольного Стража

# Рельсы идут через проёмы перемычек: только прямые отрезки (в пикселях рельсы по диагонали выглядят плохо).
RAIL = [(2612, 842), (2800, 842), (2800, 720), (2990, 720), (2990, 576), (3232, 576), (3232, 410), (3330, 410)]

# Фонари: на северном откосе и над проёмами (мировые координаты; радиус свечения).
LIGHTS = [(2700, 222, 70), (2944, 222, 60), (3150, 222, 66), (3330, 222, 60), (3470, 222, 60),
          (2859, 676, 58), (3029, 532, 58), (3279, 366, 58), (2650, 800, 64)]

# Предметы сцены (props): у стен и в углах, не на рельсах и не на постах врагов. r — радиус коллизии.
PROPS = [
    ("crate", 2628, 262, 10), ("barrel", 2652, 258, 9), ("cart", 2770, 300, 15), ("sacks", 2822, 268, 10),
    ("log", 2690, 480, 11), ("rock", 2628, 620, 10), ("crate", 2830, 880, 10),
    ("barrel", 2888, 262, 9), ("crate", 2996, 266, 10), ("sacks", 2890, 520, 10), ("rock", 2900, 872, 10),
    ("crate", 3060, 262, 10), ("crate", 3083, 270, 10), ("barrel", 3246, 262, 9), ("log", 3205, 820, 11),
    ("rock", 3060, 872, 10), ("pillar_broken", 3140, 720, 11),
    ("pillar_broken", 3318, 560, 11), ("pillar_broken", 3478, 560, 11), ("barrel", 3312, 876, 9),
    ("rock", 3474, 870, 10), ("sacks", 3480, 690, 10),
]


def noise(w, h, scale, seed):
    """Сглаженный шум 0..1: случайная сетка, растянутая билинейно."""
    rng = np.random.default_rng(seed)
    gw, gh = int(w / scale) + 2, int(h / scale) + 2
    g = Image.fromarray((rng.random((gh, gw)) * 255).astype(np.uint8))
    return np.asarray(g.resize((int(gw * scale), int(gh * scale)), Image.BILINEAR), dtype=float)[:h, :w] / 255


YY, XX = np.mgrid[0:H, 0:W]
N1, N2, N3 = noise(W, H, 30, 1), noise(W, H, 8, 2), noise(W, H, 2.5, 3)


def paint(img, mask, col, k=1.0):
    img[mask] = img[mask] * (1 - k) + np.array(col, float) * k


def ground():
    """Утоптанная порода: тёплый серо-бурый тон, крупные пятна, мелкая крошка, трещины."""
    n = N1 * 0.55 + N2 * 0.3 + N3 * 0.15
    pal = [np.array(c, float) for c in [(56, 50, 48), (66, 60, 56), (76, 70, 64), (86, 80, 72)]]
    band = np.clip((n * 4.4 - 0.9).astype(int), 0, 3)
    img = np.zeros((H, W, 3))
    for i, c in enumerate(pal):
        img[band == i] = c
    rng = np.random.default_rng(6)
    for _ in range(140):                                     # трещины — короткие ломаные
        x, y = rng.integers(20, W - 20), rng.integers(40, H - 20)
        for _ in range(rng.integers(6, 16)):
            x = int(np.clip(x + rng.integers(-1, 2), 0, W - 1))
            y = int(np.clip(y + rng.integers(0, 2), 0, H - 1))
            img[y, x] = (40, 36, 36)
    for _ in range(2200):                                    # крошка с бликом
        x, y = rng.integers(0, W - 2), rng.integers(0, H - 2)
        c = rng.integers(88, 118)
        img[y, x] = (c, c - 6, c - 12)
        img[y + 1, x] = (46, 42, 40)
    return img


def puddles(img):
    wet = noise(W, H, 46, 4)
    pool = (wet > 0.8) & (YY > TOP_FACE + 10)
    damp = (wet > 0.74) & ~pool
    paint(img, damp, (52, 54, 56), 0.5)
    paint(img, pool, (34, 62, 74), 0.85)
    rim = pool & ~np.roll(pool, 1, 0)                        # светлая кромка сверху лужи
    paint(img, rim, (110, 150, 160), 0.7)
    paint(img, pool & (N3 > 0.86), (90, 140, 156), 0.8)
    # сток вдоль южной стены — вода, из-за которой шахту и затопило
    ch = (YY > H - 40) & (YY < H - 26 + (N2 * 6).astype(int))
    paint(img, ch, (30, 58, 72), 0.9)
    paint(img, ch & ~np.roll(ch, 1, 0), (120, 166, 176), 0.8)
    paint(img, ch & (np.sin(XX / 7.0 + YY) > 0.92), (70, 116, 134), 0.8)


def rails(img):
    for (ax, ay), (bx, by) in zip(RAIL, RAIL[1:]):
        ax, ay, bx, by = ax - X0, ay - Y0, bx - X0, by - Y0
        if ay == by:                                         # горизонтальный путь: шпалы поперёк
            xa, xb = sorted((ax, bx))
            for sx in range(xa - 6, xb + 6, 10):
                img[ay - 7:ay + 8, sx:sx + 4] = (70, 52, 38)
                img[ay - 7, sx:sx + 4] = (96, 72, 50)
            for ry in (ay - 5, ay + 4):
                img[ry, xa - 6:xb + 6] = (150, 140, 132)
                img[ry + 1, xa - 6:xb + 6] = (60, 54, 52)
        else:                                                # вертикальный путь
            ya, yb = sorted((ay, by))
            for sy in range(ya - 6, yb + 6, 10):
                img[sy:sy + 4, ax - 7:ax + 8] = (70, 52, 38)
                img[sy, ax - 7:ax + 8] = (96, 72, 50)
            for rx in (ax - 5, ax + 4):
                img[ya - 6:yb + 6, rx] = (150, 140, 132)
                img[ya - 6:yb + 6, rx + 1] = (60, 54, 52)


def arena(img):
    cx, cy, r = ARENA[0] - X0, ARENA[1] - Y0, ARENA[2]
    d = np.hypot(XX - cx, YY - cy)
    ang = np.arctan2(YY - cy, XX - cx)
    ring = (d < r) & (YY > TOP_FACE + 2)
    tiles = (((d // 14).astype(int) + ((ang * 24 / np.pi) // 1).astype(int)) % 2) == 0
    paint(img, ring, (92, 88, 86), 0.9)
    paint(img, ring & tiles, (102, 98, 94), 0.9)
    seams = ring & ((np.abs((d % 14) - 0) < 1) | (np.abs(((ang * 24 / np.pi) % 1)) < 0.06))
    paint(img, seams, (52, 48, 48), 0.9)
    paint(img, (np.abs(d - r) < 2.5) & (YY > TOP_FACE), (130, 104, 62), 0.9)   # бронзовый обод
    paint(img, ring & (N2 > 0.78), (66, 92, 80), 0.6)        # патина и мох
    rng = np.random.default_rng(12)
    for _ in range(26):                                      # осколки колокола
        a, rr = rng.random() * np.pi * 2, r * (0.3 + rng.random() * 0.8)
        x, y = int(cx + np.cos(a) * rr), int(cy + np.sin(a) * rr)
        if y > TOP_FACE + 4:
            img[y:y + 2, x:x + 3] = (176, 130, 60)
            img[y + 2, x:x + 3] = (90, 62, 32)


def rock_mask(x0, y0, x1, y1, seed, grow=5):
    """Неровная скальная масса вокруг прямоугольника."""
    jag = (noise(W, H, 5, seed) * grow * 1.6).astype(int)
    dx = np.maximum(np.maximum(x0 - XX, XX - x1), 0)
    dy = np.maximum(np.maximum(y0 - YY, YY - y1), 0)
    return np.hypot(dx, dy) <= grow - 2 + jag * 0.6


def rock(img, mask, seed):
    """Скала сверху: тёмная, с бликом по северной кромке и тенью по южной."""
    n = noise(W, H, 5, seed) * 0.55 + noise(W, H, 1.6, seed + 1) * 0.45
    pal = [(30, 30, 36), (42, 41, 48), (55, 53, 60), (70, 67, 74)]
    band = np.clip(((n - 0.25) * 6).astype(int), 0, 3)
    for i, c in enumerate(pal):
        img[mask & (band == i)] = c
    hi = mask & (noise(W, H, 1.2, seed + 2) > 0.86)          # светлые грани камней
    img[hi] = (88, 85, 92)
    img[np.roll(hi, 1, 0) & mask & ~hi] = (26, 25, 30)
    paint(img, mask & ~np.roll(mask, 2, 0), (104, 100, 108), 0.8)   # кромка, на которую падает свет
    # южный откос: скала видна сбоку, полосы пород, внизу тень на пол
    face = np.zeros_like(mask)
    for k in range(1, 7):
        face |= np.roll(mask, k, 0)
    face &= ~mask
    fn = noise(W, H, 3, seed + 4)
    img[face] = np.array([58, 54, 58], float) + fn[face][:, None] * 26
    paint(img, face & ((YY + (fn * 4).astype(int)) % 3 == 0), (40, 37, 42), 0.8)
    paint(img, face & ~np.roll(face | mask, 1, 0), (92, 88, 94), 0.7)
    for k in range(1, 5):                                    # тень на пол под откосом
        sh = ~(mask | face) & np.roll(face, k, 0)
        img[sh] *= 0.7 + k * 0.06


def timber(img, x, y_top, y_bot):
    img[y_top:y_bot, x:x + 5] = (104, 74, 48)
    img[y_top:y_bot, x + 4] = (64, 44, 30)
    img[y_top:y_bot, x] = (134, 98, 64)


def lantern(img, x, y):
    img[y - 2:y, x:x + 1] = (40, 36, 36)
    img[y:y + 5, x - 2:x + 3] = (60, 46, 34)
    img[y + 1:y + 4, x - 1:x + 2] = (255, 214, 120)
    img[y + 2, x] = (255, 246, 200)


def walls(img):
    # внешняя скала: по краям, неровно
    edge = np.minimum.reduce([XX, W - 1 - XX, H - 1 - YY]) < 10 + (noise(W, H, 7, 20) * 9).astype(int)
    rock(img, edge, 21)
    # северная стена: верх скалы и освещённый откос с пластами породы
    top = YY < 14 + (noise(W, H, 9, 22)[0] * 6).astype(int)[None, :].repeat(H, 0)
    face = (YY < TOP_FACE) & ~top
    rock(img, top, 23)
    fn = noise(W, H, 4, 24)
    strata = ((YY + (N1 * 10).astype(int)) % 7 == 0)
    fc = np.array([70, 66, 70], float) + fn[..., None] * 34
    fc = fc * (1.0 - (YY / TOP_FACE)[..., None] * 0.35)      # откос темнеет книзу
    img[face] = fc[face]
    paint(img, face & strata, (52, 48, 54), 0.8)
    paint(img, (YY >= TOP_FACE) & (YY < TOP_FACE + 6), (30, 28, 30), 0.45)   # тень у подножия
    for x in range(40, W - 30, 110):                          # крепь: стойки и верхняки
        timber(img, x, 8, TOP_FACE + 2)
        timber(img, x + 46, 8, TOP_FACE + 2)
        img[6:10, x - 2:x + 53] = (118, 86, 56)
        img[9, x - 2:x + 53] = (66, 46, 32)
    for wx, wy, ww, wh in WALLS:                              # перемычки между выработками
        ax, ay = int(wx - X0), int(wy - Y0)
        bx, by = ax + int(ww), ay + int(wh)
        m = rock_mask(ax, ay, bx, by, int(wx + wy), grow=6)
        rock(img, m, int(wx) + 3)
        if by < H - 12:                                       # торец над проёмом: откос с крепью и фонарём
            fy = by - 12
            fm = m & (YY >= fy) & (YY <= by + 4)
            img[fm] = np.array([72, 68, 72]) + noise(W, H, 3, ay)[fm][:, None] * 30
            timber(img, ax - 6, fy - 4, by + 8)
            timber(img, bx + 1, fy - 4, by + 8)
        if ay > Y0 - Y0 + 12:                                 # нижний сегмент: верхний торец светлее
            paint(img, m & (YY < ay + 3) & (YY > ay - 6), (98, 94, 100), 0.6)


def light(img):
    """Запечённый свет фонарей: пол у фонарей теплее и светлее, между ними — темнее."""
    acc = np.zeros((H, W))
    for x, y, r in LIGHTS:
        acc += np.exp(-((XX - (x - X0)) ** 2 + (YY - (y - Y0)) ** 2) / (2 * (r * 1.2) ** 2))
    acc = np.clip(acc, 0, 1)
    k = 0.74 + 0.4 * acc
    img *= k[..., None]
    img += (acc[..., None] * np.array([22, 12, 0]))           # тёплый оттенок
    for x, y, _ in LIGHTS:
        lantern(img, x - X0, y - Y0)


def floor():
    img = ground()
    puddles(img)
    arena(img)
    rails(img)
    walls(img)
    light(img)
    a = np.full((H, W, 1), 255.0)
    return Image.fromarray(np.concatenate([np.clip(img, 0, 255), a], 2).astype(np.uint8), "RGBA")


def gate(open_: bool):
    """Штольня в склоне с деревянной крепью; закрытая — по верхняк в воде."""
    w, h = 44, 34
    im = np.zeros((h, w, 4), float)
    yy, xx = np.mgrid[0:h, 0:w]
    hill = ((xx - 22) / 22) ** 2 + ((yy - 26) / 22) ** 2 <= 1
    n = noise(w, h, 4, 11)
    im[hill] = np.concatenate([np.array([70, 74, 66]) + 40 * n[hill][:, None], np.full((hill.sum(), 1), 255)], 1)
    hole = (np.abs(xx - 22) <= 8) & (yy >= 12) & (yy <= 31)
    im[hole] = (12, 14, 18, 255)
    if not open_:
        water = hole & (yy >= 17)
        im[water] = (40, 96, 120, 255)
        im[water & (yy == 17)] = (130, 190, 205, 255)
        im[water & (n > 0.75)] = (80, 140, 160, 255)
    for x0 in (12, 31):                                       # стойки и верхняк
        im[11:32, x0:x0 + 2] = (110, 78, 48, 255)
        im[11:32, x0 + 1] = (74, 52, 32, 255)
    im[9:12, 11:34] = (124, 90, 56, 255)
    im[11, 11:34] = (74, 52, 32, 255)
    if open_:
        im[24:26, 16:29] = (96, 84, 76, 255)                  # рельсы уходят внутрь
        im[29:31, 15:30] = (96, 84, 76, 255)
    return Image.fromarray(im.clip(0, 255).astype(np.uint8), "RGBA")


def main():
    f = floor()
    f.save(OUT / "mine_floor.png")
    g = Image.new("RGBA", (88, 34))
    g.alpha_composite(gate(False), (0, 0))
    g.alpha_composite(gate(True), (44, 0))
    g.save(OUT / "mine_gate.png")
    meta = {"top_face": TOP_FACE, "lights": [[x, y, r] for x, y, r in LIGHTS],
            "props": [{"k": k, "x": x, "y": y, "r": r} for k, x, y, r in PROPS]}
    (OUT / "mine.json").write_text(json.dumps(meta), encoding="utf-8")
    if "--preview" in sys.argv:
        path = sys.argv[sys.argv.index("--preview") + 1]
        f.save(path)
        g.resize((88 * 6, 34 * 6), Image.NEAREST).save(path.replace(".png", "_gate.png"))
    print("mine", f.size, g.size, len(PROPS), "props")


if __name__ == "__main__":
    main()
