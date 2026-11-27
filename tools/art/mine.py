"""Затопленная шахта: пол с лужами и рельсами, скальные перемычки с крепью, вход у Пристани (затоплен / открыт).

Запуск:  python tools/art/mine.py [--preview PATH]
Геометрия берётся из scripts/adventure_sites.gd (MINE, MINE_WALLS, MINE_EXIT) — меняя её там, перегенерируй.
"""
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "custom" / "world"
SRC = (ROOT / "scripts" / "adventure_sites.gd").read_text(encoding="utf-8")


def _rect(text):
    return [float(v) for v in re.findall(r"[-\d.]+", text)]


MINE = _rect(re.search(r"MINE := Rect2\(([^)]*)\)", SRC).group(1))
WALLS = [_rect(m) for m in re.findall(r"Rect2\(([^)]*)\)", re.search(r"MINE_WALLS := \[(.*?)\]", SRC, re.S).group(1))]
EXIT = _rect(re.search(r"MINE_EXIT := Vector2\(([^)]*)\)", SRC).group(1))


def noise(w, h, scale, seed):
    """Сглаженный шум: случайная сетка, растянутая билинейно."""
    rng = np.random.default_rng(seed)
    gw, gh = int(w / scale) + 2, int(h / scale) + 2
    g = Image.fromarray((rng.random((gh, gw)) * 255).astype(np.uint8))
    return np.asarray(g.resize((int(gw * scale), int(gh * scale)), Image.BILINEAR), dtype=float)[:h, :w] / 255


def floor():
    x0, y0, w, h = [int(v) for v in MINE]
    n = noise(w, h, 24, 1) * 0.6 + noise(w, h, 7, 2) * 0.3 + noise(w, h, 2, 3) * 0.1
    base = np.array([44, 54, 58], float)
    img = base[None, None, :] * (0.72 + 0.5 * n[..., None])
    wet = noise(w, h, 40, 4)                                  # лужи: тёмная вода с бликом
    pool = wet > 0.76
    img[pool] = img[pool] * 0.45 + np.array([30, 70, 84]) * 0.55
    edge = (wet > 0.72) & ~pool
    img[edge] = img[edge] * 0.8 + np.array([60, 96, 104]) * 0.2
    shine = pool & (noise(w, h, 6, 5) > 0.9)
    img[shine] = img[shine] * 0.5 + np.array([110, 160, 172]) * 0.5
    rng = np.random.default_rng(6)                            # щебень
    for _ in range(900):
        x, y = rng.integers(0, w - 3), rng.integers(0, h - 3)
        c = rng.integers(70, 110)
        img[y:y + 2, x:x + 2] = (c, c + 8, c + 10)
        img[y + 2, x:x + 2] *= 0.6
    rail_y = int(EXIT[1] - y0) + 18                           # рельсы от входа вглубь первой выработки
    for ry in (rail_y, rail_y + 9):
        img[ry:ry + 2, 20:int(WALLS[0][0] - x0) - 6] = (112, 96, 84)
        img[ry + 2, 20:int(WALLS[0][0] - x0) - 6] = (50, 44, 40)
    for sx in range(24, int(WALLS[0][0] - x0) - 10, 12):     # шпалы
        img[rail_y - 2:rail_y + 13, sx:sx + 4] = (74, 56, 40)
        img[rail_y:rail_y + 2, sx:sx + 4] = (112, 96, 84)
        img[rail_y + 9:rail_y + 11, sx:sx + 4] = (112, 96, 84)
    border = 10                                               # скальный край выработки
    yy, xx = np.mgrid[0:h, 0:w]
    dist = np.minimum.reduce([xx, yy, w - 1 - xx, h - 1 - yy]).astype(float)
    rock = dist < border + noise(w, h, 9, 7) * 8
    img[rock] = np.array([22, 28, 32]) + 30 * noise(w, h, 4, 8)[rock][:, None]
    for wx, wy, ww, wh in WALLS:                              # перемычки: скала, по краям крепь
        ax, ay = int(wx - x0), int(wy - y0)
        bx, by = ax + int(ww), ay + int(wh)
        sl = (slice(max(0, ay - 3), min(h, by + 3)), slice(max(0, ax - 3), min(w, bx + 3)))
        img[sl] = img[sl] * 0.55                              # тень от стены
        r = noise(int(ww), int(wh), 4, int(wx))
        img[ay:by, ax:bx] = np.array([30, 36, 40]) + 46 * r[..., None]
        img[ay:by, ax:ax + 2] = (64, 76, 80)                  # грань, на которую падает свет
        for py in range(ay + 14, by - 6, 64):                 # стойки крепи
            img[py:py + 6, ax - 4:bx + 4] = (92, 66, 42)
            img[py + 5, ax - 4:bx + 4] = (52, 36, 24)
    a = np.full((h, w, 1), 255.0)
    return Image.fromarray(np.concatenate([np.clip(img, 0, 255), a], 2).astype(np.uint8), "RGBA")


def gate(open_: bool):
    """Штольня в склоне с деревянной крепью; закрытая — по балку в воде."""
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
        rip = water & (n > 0.75)
        im[rip] = (80, 140, 160, 255)
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
    if "--preview" in sys.argv:
        path = sys.argv[sys.argv.index("--preview") + 1]
        f.save(path)
        g.resize((88 * 6, 34 * 6), Image.NEAREST).save(path.replace(".png", "_gate.png"))
    print("mine", f.size, g.size)


if __name__ == "__main__":
    main()
