"""Enemy sprites rendered with lighting (shade.py): slime = glossy sphere, wolf = ellipsoid body,
sphere head, cylinder legs, golem = lit stone blocks with glowing runes."""
import math
from shade import Canvas, Mat, tex_noise, tex_bricks

SLIME = Mat((80, 168, 150), spec=0.9)
SLIME_CORE = Mat((60, 130, 116))
EYE = Mat((235, 70, 90), emissive=True)
EYE_HI = Mat((255, 210, 210), emissive=True)
MOUTH = Mat((30, 24, 36), emissive=True)
FUR = Mat((112, 116, 136), tex=tex_noise(0.5, 3))
FUR_DARK = Mat((78, 80, 98), tex=tex_noise(0.4, 4))
FUR_LIGHT = Mat((168, 170, 184))
TEETH = Mat((232, 230, 214), emissive=True)
STONE = Mat((132, 116, 106), tex=tex_bricks(6, 5, 0.5))
MOSS = Mat((70, 118, 84), tex=tex_noise(0.5, 6))
GLOW = Mat((255, 170, 70), emissive=True)
GLOW_HI = Mat((255, 226, 140), emissive=True)


def slime(frame: int):
    c = Canvas(24, 20)
    sq = 1.0 if frame == 0 else 1.15
    rx, ry = 9.0 * sq, 9.0 / sq
    cy = 17 - ry
    c.sphere(12, cy + 1, rx, ry, SLIME, keep=lambda x, y: y <= 17)
    c.sphere(12, cy + 3, rx * 0.5, ry * 0.45, SLIME_CORE, z=-3)
    ey = int(cy) - 1
    for ex in (8, 14):
        c.px(ex, ey, 20, (0, 0, 1), EYE)
        c.px(ex + 1, ey, 20, (0, 0, 1), EYE)
        c.px(ex, ey + 1, 20, (0, 0, 1), EYE)
        c.px(ex + 1, ey + 1, 20, (0, 0, 1), EYE)
        c.px(ex, ey, 21, (0, 0, 1), EYE_HI)
    c.px(11, ey + 3, 20, (0, 0, 1), MOUTH)
    c.px(12, ey + 3, 20, (0, 0, 1), MOUTH)
    c.occlude(0, 16, 23, 17, 0.6)
    return c.render()


def wolf(frame: int):
    c = Canvas(34, 20)
    bob = 1 if frame % 2 else 0
    phase = [(0, 1), (1, 0), (0, -1), (-1, 0)][frame]
    for i, lx in enumerate([9, 13, 22, 26]):                 # legs: front pair, back pair
        dx = phase[0] if i in (0, 3) else -phase[0]
        lift = phase[1] if i in (0, 3) else -phase[1]
        far = i in (1, 2)
        c.cylinder(lx + dx, 1.3, 11 + bob, 17 - max(0, lift), FUR_DARK if far else FUR, cap_ry=0.5, z=-4 if far else 2)
    c.sphere(19, 10 + bob, 10, 4.8, FUR)                     # body
    c.sphere(19, 12.5 + bob, 7, 2.2, FUR_DARK, z=1)          # belly shade
    c.sphere(29.5, 8 + bob, 3.2, 2.4, FUR, z=-1)             # tail base
    c.sphere(32, 6 + bob, 2.0, 1.8, FUR_LIGHT, z=-1)
    c.sphere(7, 7 + bob, 4.6, 4.2, FUR, z=3)                 # head
    c.sphere(3, 9 + bob, 3.0, 2.0, FUR_LIGHT, z=4)           # snout
    for ex, tip in ((6, 0), (9, 1)):                          # ears
        c.cone(ex, 1 + bob + tip, 5 + bob, 1.8, FUR_DARK if tip else FUR, z=2)
    c.px(5, 6 + bob, 30, (0, 0, 1), EYE)
    c.px(1, 9 + bob, 30, (0, 0, 1), MOUTH)
    c.px(2, 11 + bob, 30, (0, 0, 1), TEETH)
    c.px(4, 11 + bob, 30, (0, 0, 1), TEETH)
    return c.render()


def golem(frame: int):
    """Boulder golem: big lit stones (spheres), moss, cracks, glowing eyes and chest rune."""
    c = Canvas(52, 52)
    b = frame
    rock = Mat((134, 120, 110), tex=tex_noise(0.5, 12))
    rock_dark = Mat((104, 92, 86), tex=tex_noise(0.5, 13))
    c.sphere(18, 45, 6, 5, rock_dark, z=-2)                  # legs
    c.sphere(34, 45, 6, 5, rock_dark, z=-2)
    c.sphere(26, 28 + b, 15, 13, rock, z=0)                  # torso boulder
    c.sphere(7, 26 + b, 6, 8, rock, z=2)                     # arms
    c.sphere(45, 26 + b, 6, 8, rock_dark, z=2)
    c.sphere(6, 37 + b, 6.5, 5.5, rock, z=4)                 # fists
    c.sphere(46, 37 + b, 6.5, 5.5, rock_dark, z=4)
    c.sphere(26, 10 + b, 9, 7.5, rock, z=6)                  # head
    for (x, y, rx, ry) in ((17, 22, 4, 3), (33, 33, 4, 2.5), (5, 21, 3, 2)):
        c.sphere(x, y + b, rx, ry, MOSS, z=8)
    for (x0, y0, x1, y1) in ((24, 18, 27, 25), (27, 25, 25, 30)):
        n = 8
        for i in range(n + 1):
            c.px(round(x0 + (x1 - x0) * i / n), round(y0 + (y1 - y0) * i / n) + b, 9, (0, 0, 1), Mat((40, 32, 36), emissive=True))
    glow = GLOW_HI if frame else GLOW
    for ex in (22, 29):
        for dx in (0, 1):
            c.px(ex + dx, 10 + b, 12, (0, 0, 1), glow)
            c.px(ex + dx, 11 + b, 12, (0, 0, 1), GLOW)
    for (x, y) in [(25, 28), (26, 29), (27, 28), (26, 30), (26, 31), (25, 32), (27, 32)]:
        c.px(x, y + b, 12, (0, 0, 1), glow)
    return c.render()




# ---- Затопленная шахта: панцирник, звонарь, Колокольный Страж (смотрят влево) ----
IRON = Mat((112, 124, 134), spec=0.6, tex=tex_noise(0.35, 21))
IRON_DARK = Mat((74, 84, 94), spec=0.4, tex=tex_noise(0.35, 22))
RIVET = Mat((186, 194, 200), spec=0.9)
RUST = Mat((150, 92, 58), tex=tex_noise(0.6, 23))
WET_SKIN = Mat((92, 118, 112), tex=tex_noise(0.4, 24))
CLOTH = Mat((58, 66, 82), tex=tex_noise(0.5, 25))
BRONZE = Mat((196, 148, 64), spec=0.8, tex=tex_noise(0.25, 26))
BRONZE_DARK = Mat((138, 98, 44), spec=0.5, tex=tex_noise(0.3, 27))
PATINA = Mat((70, 140, 120))
WOOD = Mat((112, 80, 52), tex=tex_noise(0.5, 28))
DRIP = Mat((140, 214, 226), emissive=True)
EYE_SEA = Mat((120, 240, 220), emissive=True)
EYE_SEA_HI = Mat((220, 255, 250), emissive=True)


def _line(c, x0, y0, x1, y1, z, m, n=8):
    for i in range(n + 1):
        c.px(round(x0 + (x1 - x0) * i / n), round(y0 + (y1 - y0) * i / n), z, (0, 0, 1), m)


def shell(frame: int):
    """Панцирник: шахтёрская тварь под клёпаным железным панцирем, лобовой щит смотрит влево."""
    c = Canvas(36, 26)
    b = frame
    for i, lx in enumerate([9, 15, 22, 28]):                 # ноги
        lift = 1 if (i + frame) % 2 else 0
        c.capsule(lx, 17, lx + (-2 if i < 2 else 2), 24 - lift, 1.4, IRON_DARK, z=-3)
    c.sphere(20, 14 + b, 14, 9.5, IRON, z=0)                 # спинной панцирь
    c.sphere(20, 17 + b, 13, 5, IRON_DARK, z=-1, keep=lambda x, y: y >= 17 + b)
    for k in range(3):                                       # стыки пластин
        x = 13 + k * 7
        _line(c, x, 6 + b + abs(k - 1), x + 1, 20 + b, 12, IRON_DARK, n=10)
    for (x, y) in [(10, 13), (16, 8), (23, 8), (29, 12), (19, 19), (27, 18)]:
        c.px(x, y + b, 13, (0, -0.3, 1), RIVET)
    c.sphere(25, 9 + b, 3, 2, RUST, z=9)
    c.sphere(15, 18 + b, 2.5, 1.5, RUST, z=9)
    c.sphere(6, 15 + b, 7, 7.5, IRON, z=4)                   # лобовой щит
    c.sphere(5.5, 15 + b, 5, 5.5, IRON_DARK, z=6)
    for (x, y) in [(3, 11), (8, 11), (3, 19), (8, 19)]:
        c.px(x, y + b, 14, (0, 0, 1), RIVET)
    for dx in (0, 1):                                        # глаза в смотровой щели
        c.px(3 + dx, 14 + b, 15, (0, 0, 1), EYE_SEA_HI if frame else EYE_SEA)
        c.px(7 + dx, 14 + b, 15, (0, 0, 1), EYE_SEA)
    c.px(30, 22 + b, 14, (0, 0, 1), DRIP)
    c.occlude(0, 23, 35, 25, 0.5)
    return c.render()


def ringer(frame: int):
    """Звонарь: сгорбленный утопленник в капюшоне с медным колоколом на шесте."""
    c = Canvas(28, 32)
    sw = -2 if frame else 2                                  # качание колокола
    c.capsule(12, 22, 11, 30, 1.6, CLOTH, z=-2)              # ноги
    c.capsule(16, 22, 17, 30, 1.6, CLOTH, z=-3)
    c.sphere(14, 19, 7, 8, CLOTH, z=0)                       # балахон
    c.sphere(14, 25, 7.5, 3.5, CLOTH, z=1, keep=lambda x, y: y >= 24)
    c.sphere(11, 10, 5, 5, CLOTH, z=2)                       # капюшон
    c.sphere(9.5, 11, 3, 3, WET_SKIN, z=4)                   # лицо
    c.px(8, 10, 9, (0, 0, 1), EYE_SEA)
    c.px(10, 10, 9, (0, 0, 1), EYE_SEA_HI if frame else EYE_SEA)
    c.capsule(4, 3, 7, 28, 0.9, WOOD, z=5)                   # шест
    c.capsule(11, 17, 6, 18, 1.4, WET_SKIN, z=6)             # рука на шесте
    bx = 3 + sw
    c.sphere(bx, 7, 3.4, 3.6, BRONZE, z=7, keep=lambda x, y: y <= 9)   # колокол
    c.sphere(bx, 9.5, 4.2, 1.2, BRONZE_DARK, z=7.5)
    c.px(bx, 11, 10, (0, 0, 1), BRONZE_DARK)
    c.px(14, 30, 6, (0, 0, 1), DRIP)
    return c.render()


def warden(frame: int):
    """Колокольный Страж: бронзовый колокол-тело на каменных ногах, руки-цепи с молотами, глаза в прорези."""
    c = Canvas(56, 58)
    b = frame
    rock = Mat((96, 104, 108), tex=tex_noise(0.5, 31))
    c.sphere(19, 52, 6.5, 5, rock, z=-2)                     # ноги
    c.sphere(37, 52, 6.5, 5, rock, z=-2)
    c.capsule(15, 19 + b, 6, 36 + b, 3.6, IRON_DARK, z=-1)   # руки от плеч колокола
    c.capsule(41, 19 + b, 50, 36 + b, 3.6, IRON_DARK, z=-1)
    c.sphere(5, 40 + b, 6, 5.5, IRON, z=3)                   # кулаки-молоты
    c.sphere(51, 40 + b, 6, 5.5, IRON_DARK, z=3)
    bell = Mat((148, 98, 40), spec=0.9, tex=tex_noise(0.25, 26))

    def radius(y):                                           # профиль колокола: купол, талия, раструб
        t = (y - 6) / 40
        return 6 + 7 * math.sqrt(max(0.0, t)) + 8 * t ** 3

    for y in range(6, 47):
        r = radius(y)
        slope = radius(y + 1) - r
        for x in range(int(28 - r) - 1, int(28 + r) + 2):
            nx = (x + 0.5 - 28) / r
            if abs(nx) <= 1:
                nz = math.sqrt(1 - nx * nx)
                c.px(x, y + b, 4 + nz * r * 0.5, (nx, -0.35 - slope * 0.6, nz), bell)
    c.sphere(28, 46 + b, 21.5, 3.4, BRONZE_DARK, z=14)       # губа колокола
    c.sphere(28, 47 + b, 17, 2, MOUTH, z=15, keep=lambda x, y: y >= 47 + b)
    c.sphere(28, 5 + b, 3.6, 2.6, IRON_DARK, z=8)            # ушко
    for y in (14, 32):                                       # пояса
        rr = radius(y)
        _line(c, 28 - rr + 1, y + b, 28 + rr - 1, y + b, 16, BRONZE_DARK, n=36)
    for (x, y) in [(19, 27), (23, 30), (33, 25), (36, 29), (27, 38), (30, 40)]:
        c.px(x, y + b, 17, (0, 0, 1), PATINA)
    for x in range(20, 37):                                  # смотровая прорезь
        c.px(x, 21 + b, 17, (0, 0, 1), MOUTH)
        c.px(x, 22 + b, 17, (0, 0, 1), MOUTH)
    glow = EYE_SEA_HI if frame else EYE_SEA
    for ex in (23, 31):
        for dx in (0, 1, 2):
            c.px(ex + dx, 21 + b, 18, (0, 0, 1), glow)
            c.px(ex + dx, 22 + b, 18, (0, 0, 1), EYE_SEA)
    c.capsule(28, 46 + b, 28 + (2 if frame else -2), 51 + b, 2.2, IRON_DARK, z=16)   # язык колокола
    c.px(15, 49 + b, 14, (0, 0, 1), DRIP)
    c.px(42, 48 + b, 14, (0, 0, 1), DRIP)
    return c.render()
