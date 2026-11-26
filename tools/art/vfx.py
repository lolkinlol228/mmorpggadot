"""Покадровые спрайты эффектов умений -> assets/custom/vfx/<name>.png (кадры в ряд).

Запуск: python tools/art/vfx.py [--preview PATH]
Все эффекты — пиксель-арт с жёсткими краями и ограниченной палитрой, чтобы стоять рядом
с персонажами. Цвет и форма каждого кадра считаются из расстояния, угла и шума.
"""
import math
import sys
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "custom" / "vfx"


def _hash(x, y, s=0):
    h = (x * 374761393 + y * 668265263 + s * 1274126177) & 0xFFFFFFFF
    h = (h ^ (h >> 13)) * 1274126177 & 0xFFFFFFFF
    return (h ^ (h >> 16)) / 0xFFFFFFFF


def _ramp(pal, v):
    """v 0..1 -> цвет из палитры (последний — самый яркий)."""
    i = max(0, min(len(pal) - 1, int(v * len(pal))))
    return pal[i]


def strip(frames):
    w, h = frames[0].size
    out = Image.new("RGBA", (w * len(frames), h), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        out.alpha_composite(f, (i * w, 0))
    return out


# ---------------- огонь: взрыв огненного шара / удар метеора ----------------
FIRE = [(70, 16, 12), (150, 34, 18), (220, 84, 24), (250, 150, 40), (255, 214, 96), (255, 250, 214)]
SMOKE = [(40, 34, 38), (64, 56, 60), (92, 84, 86)]


def fire_burst(f, n=8, size=48):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    c = size / 2
    grow = min(1.0, (f + 1) / 4.0)
    r = 5 + 15 * grow
    heat = max(0.0, 1.0 - f / (n - 2))           # к концу огонь гаснет и становится дымом
    for y in range(size):
        for x in range(size):
            dx, dy = x + 0.5 - c, y + 0.5 - c
            d = math.hypot(dx, dy)
            a = math.atan2(dy, dx)
            edge = r + math.sin(a * 5 + f * 1.7) * 2.2 + (_hash(x, y, f) - 0.5) * 3.0
            if d > edge:
                continue
            v = 1.0 - d / edge
            if heat > 0.15 and v * heat + 0.15 > 0.25:
                img.putpixel((x, y), _ramp(FIRE, v * heat * 1.25 + 0.05) + (255,))
            elif _hash(x, y, f + 7) < 0.55 + 0.35 * (1 - f / n):
                img.putpixel((x, y), _ramp(SMOKE, v + 0.2) + (int(220 * (1 - f / n)) + 30,))
    return img


# ---------------- лёд: ледяная волна (кольцо по земле с осколками) ----------------
ICE = [(40, 90, 150), (80, 150, 210), (150, 210, 245), (230, 250, 255)]


def frost_nova(f, n=8, w=112, h=56):
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    cx, cy = w / 2, h / 2
    rr = 10 + f * 6.2
    fade = 1.0 - max(0, f - 4) / 4.0
    for y in range(h):
        for x in range(w):
            dx, dy = (x + 0.5 - cx), (y + 0.5 - cy) * 2.0
            d = math.hypot(dx, dy)
            band = abs(d - rr)
            if band < 3.2:
                v = 1.0 - band / 3.2
                img.putpixel((x, y), _ramp(ICE, v * 0.9 + 0.1) + (int(255 * fade),))
            elif d < rr and _hash(x, y, f) < 0.07 * fade:          # иней внутри кольца
                img.putpixel((x, y), ICE[2] + (int(170 * fade),))
    for k in range(12):                                          # ледяные шипы на кольце
        a = k * math.tau / 12 + 0.3
        length = (2 + min(f, 4) * 2.2) * fade
        bx, by = cx + math.cos(a) * rr, cy + math.sin(a) * rr * 0.5
        for i in range(int(length) + 1):
            px, py = int(bx), int(by - i)
            if 0 <= px < w and 0 <= py < h:
                img.putpixel((px, py), (ICE[3] if i > length - 2 else ICE[2]) + (int(255 * fade),))
                if i < length - 2 and 0 <= px + 1 < w:
                    img.putpixel((px + 1, py), ICE[1] + (int(255 * fade),))
    return img


# ---------------- свет: столп для «Кары», «Удара света», щитов ----------------
HOLY = [(170, 120, 40), (230, 180, 70), (255, 226, 130), (255, 248, 214), (255, 255, 255)]


def holy_pillar(f, n=8, w=32, h=80):
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    widths = [2, 6, 10, 12, 11, 8, 5, 2]
    half = widths[f] / 2
    cx = w / 2
    for y in range(h):
        wob = math.sin(y * 0.4 + f) * 0.6
        for x in range(w):
            d = abs(x + 0.5 - cx - wob)
            if d <= half:
                v = 1.0 - d / max(half, 0.5)
                a = 255 if y > 6 else int(255 * y / 6)
                img.putpixel((x, y), _ramp(HOLY, v * 0.95 + 0.05) + (a,))
    for i in range(6):                                           # искры вокруг
        sx = int(cx + (_hash(i, f, 3) - 0.5) * (half * 2 + 10))
        sy = int(h - 8 - _hash(i, f, 9) * (h - 16))
        if 0 <= sx < w and 0 <= sy < h:
            img.putpixel((sx, sy), HOLY[4] + (255,))
    for x in range(w):                                           # свечение у земли
        for y in range(h - 6, h):
            dx, dy = (x + 0.5 - cx) / (half + 6), (y + 0.5 - (h - 3)) / 3
            if dx * dx + dy * dy <= 1 and img.getpixel((x, y))[3] == 0:
                img.putpixel((x, y), HOLY[2] + (150,))
    return img


# ---------------- метеор (камень с огненным хвостом, летит вправо-вниз) ----------------
ROCK = [(40, 28, 24), (74, 50, 38), (110, 76, 52), (150, 104, 64)]


def meteor(f, n=4, size=40):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    hx, hy = 28, 28                                               # голова камня
    for i in range(22):                                           # хвост вверх-влево
        t = i / 22
        x, y = hx - i * 0.9, hy - i * 0.9
        rad = 5.5 * (1 - t) + 0.5
        for yy in range(int(y - rad), int(y + rad) + 1):
            for xx in range(int(x - rad), int(x + rad) + 1):
                if 0 <= xx < size and 0 <= yy < size and math.hypot(xx - x, yy - y) <= rad and _hash(xx, yy, f + i) < 0.85 - t * 0.5:
                    img.putpixel((xx, yy), _ramp(FIRE, (1 - t) * 0.9 + 0.1) + (255,))
    for y in range(size):
        for x in range(size):
            d = math.hypot(x + 0.5 - hx, y + 0.5 - hy)
            if d <= 5.5:
                lit = (hx - x) + (hy - y)
                img.putpixel((x, y), _ramp(ROCK, 0.5 + lit / 14) + (255,))
                if d > 4.4:
                    img.putpixel((x, y), FIRE[3] + (255,))
    return img


# ---------------- удар оружием: полумесяц, повёрнут в коде ----------------
SLASH = [(120, 140, 190), (190, 210, 240), (245, 250, 255)]


def slash(f, n=5, size=48):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    c = size / 2
    sweep = [0.35, 0.75, 1.0, 1.0, 1.0][f]
    fade = [1.0, 1.0, 0.9, 0.55, 0.25][f]
    a0, a1 = -1.25, -1.25 + 2.5 * sweep
    for y in range(size):
        for x in range(size):
            dx, dy = x + 0.5 - c, y + 0.5 - c
            d = math.hypot(dx, dy)
            a = math.atan2(dy, dx)
            if not (a0 <= a <= a1):
                continue
            k = (a - a0) / max(0.01, a1 - a0)                    # 0 — хвост, 1 — передний край
            thick = 1.0 + 4.0 * math.sin(k * math.pi) * (0.4 + 0.6 * k)
            if abs(d - 17) <= thick:
                v = 1.0 - abs(d - 17) / (thick + 0.01)
                img.putpixel((x, y), _ramp(SLASH, v * k + 0.15) + (int(255 * fade * (0.5 + 0.5 * k)),))
    return img


# ---------------- искры попадания ----------------
SPARK = [(255, 180, 60), (255, 230, 140), (255, 255, 240)]


def hit_spark(f, n=5, size=24):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    c = size / 2
    length = [4, 9, 10, 8, 5][f]
    inner = [0, 1, 3, 5, 6][f]
    for k in range(8):
        a = k * math.tau / 8 + (0.39 if k % 2 else 0)
        ln = length if k % 2 == 0 else length * 0.6
        for i in range(inner, int(ln) + 1):
            x, y = int(c + math.cos(a) * i), int(c + math.sin(a) * i)
            if 0 <= x < size and 0 <= y < size:
                img.putpixel((x, y), _ramp(SPARK, 1 - i / (ln + 1) + 0.2) + (255,))
    if f < 2:
        for y in range(int(c) - 2, int(c) + 2):
            for x in range(int(c) - 2, int(c) + 2):
                img.putpixel((x, y), SPARK[2] + (255,))
    return img


# ---------------- лечение: зелёный столб и кресты ----------------
HEAL = [(40, 120, 60), (80, 190, 90), (150, 240, 150), (230, 255, 230)]


def heal(f, n=8, w=32, h=56):
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    cx = w / 2
    glow = math.sin((f + 1) / n * math.pi)
    for y in range(h):
        for x in range(w):
            d = abs(x + 0.5 - cx) / 9
            v = (1 - d) * glow * (y / h)
            if v > 0.25 and _hash(x, y, f) < v:
                img.putpixel((x, y), _ramp(HEAL, v) + (int(200 * v),))
    for i in range(5):                                           # кресты поднимаются
        sx = int(cx + (_hash(i, 1, 5) - 0.5) * 20)
        sy = int(h - 6 - ((f * 5 + i * 9) % (h - 8)))
        col = HEAL[3] + (255,)
        for dx, dy in ((0, 0), (-1, 0), (1, 0), (0, -1), (0, 1)):
            if 0 <= sx + dx < w and 0 <= sy + dy < h:
                img.putpixel((sx + dx, sy + dy), col if (dx, dy) == (0, 0) else HEAL[2] + (255,))
    return img


# ---------------- ударная волна по земле (пыль и обломки) ----------------
DUST = [(90, 76, 60), (140, 120, 94), (196, 176, 140), (240, 228, 200)]


def shockwave(f, n=6, w=112, h=56):
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    cx, cy = w / 2, h / 2
    rr = 8 + f * 8.5
    th = 4.5 - f * 0.6
    fade = 1.0 - f / n
    for y in range(h):
        for x in range(w):
            d = math.hypot(x + 0.5 - cx, (y + 0.5 - cy) * 2.0)
            band = abs(d - rr)
            if band < th and _hash(x, y, f) < 0.9:
                v = 1.0 - band / th
                img.putpixel((x, y), _ramp(DUST, v) + (int(235 * fade),))
    for i in range(14):                                          # летящие камешки
        a = _hash(i, 0, 11) * math.tau
        dd = rr + 3 + _hash(i, 1, 11) * 6
        px, py = int(cx + math.cos(a) * dd), int(cy + math.sin(a) * dd * 0.5 - f * 1.5 * _hash(i, 2, 11))
        if 0 <= px < w and 0 <= py < h:
            img.putpixel((px, py), DUST[0] + (int(255 * fade),))
    return img


# ---------------- кольцо силы: клич, аура, щит (белое, красится в коде) ----------------
def ring(f, n=6, w=96, h=48):
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    cx, cy = w / 2, h / 2
    rr = 6 + f * 7.5
    fade = 1.0 - f / n
    for y in range(h):
        for x in range(w):
            d = math.hypot(x + 0.5 - cx, (y + 0.5 - cy) * 2.0)
            band = abs(d - rr)
            if band < 2.2:
                v = 1.0 - band / 2.2
                img.putpixel((x, y), (255, 255, 255, int(255 * fade * (0.4 + 0.6 * v))))
    return img


EFFECTS = {
    "fire_burst": (fire_burst, 8), "frost_nova": (frost_nova, 8), "holy_pillar": (holy_pillar, 8),
    "meteor": (meteor, 4), "slash": (slash, 5), "hit_spark": (hit_spark, 5), "heal": (heal, 8),
    "shockwave": (shockwave, 6), "ring": (ring, 6),
}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    strips = {}
    for name, (fn, n) in EFFECTS.items():
        strips[name] = strip([fn(f, n) for f in range(n)])
        strips[name].save(OUT / f"{name}.png")
    if "--preview" in sys.argv:
        path = sys.argv[sys.argv.index("--preview") + 1]
        width = max(s.width for s in strips.values())
        height = sum(s.height + 4 for s in strips.values())
        prev = Image.new("RGBA", (width, height), (34, 32, 44, 255))
        y = 0
        for s in strips.values():
            prev.alpha_composite(s, (0, y))
            y += s.height + 4
        prev.resize((prev.width * 3, prev.height * 3), Image.NEAREST).save(path)
    print("vfx", {k: v.size for k, v in strips.items()})


if __name__ == "__main__":
    main()
