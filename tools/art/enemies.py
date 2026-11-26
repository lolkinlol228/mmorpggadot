"""Enemy sprites rendered with lighting (shade.py): slime = glossy sphere, wolf = ellipsoid body,
sphere head, cylinder legs, golem = lit stone blocks with glowing runes."""
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