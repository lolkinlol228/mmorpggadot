"""Clean ground renderer: smooth tonal zones + ordered dithering on zone edges, hand-placed decals
(tufts, flowers, pebbles, reeds), lit cobbles and flagstones, banded water with a foam line.
No per-pixel random speckle - that was what made the map look ragged."""
import random
import numpy as np
from PIL import Image
import world as W_

H, W = W_.H, W_.W
XX, YY = W_.XX, W_.YY
BAYER = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]], dtype=np.float32) / 16.0
DITH = np.tile(BAYER, (H // 4 + 1, W // 4 + 1))[:H, :W]


def tone(field, levels):
    """Quantise a smooth 0..1 field into `levels` bands with ordered dithering on the band edges."""
    v = np.clip(field, 0, 0.999) * levels + (DITH - 0.5) * 0.45
    return np.clip(v.astype(int), 0, levels - 1)


def put_decal(img, x, y, pattern, colors):
    for dy, row in enumerate(pattern):
        for dx, ch in enumerate(row):
            if ch != "." and 0 <= x + dx < W and 0 <= y + dy < H:
                img[y + dy, x + dx] = colors[ch]


TUFT = ["a.a.a", ".bab.", "..b.."]
TUFT2 = ["a...a", ".a.a.", ".bab."]
FLOWER = [".c.", "cdc", ".c."]
PEBBLE = [".ab", "abb", "bbc"]
REED = ["a.a", "a.a", "aba", ".b."]


def stones(img, mask, sw, sh, base, mortar, seed):
    """Lit stones: each stone gets a light top-left rim and a dark bottom-right rim."""
    rnd = np.random.default_rng(seed)
    xi, yi = XX.astype(int), YY.astype(int)
    row = yi // sh
    sx = (xi + (row % 2) * (sw // 2)) // sw
    lx = (xi + (row % 2) * (sw // 2)) % sw
    ly = yi % sh
    var = (sx * 7 + row * 13) % 4
    shades = [tuple(int(c * f) for c in base) for f in (0.86, 0.94, 1.0, 1.06)]
    light = tuple(min(255, int(c * 1.25)) for c in base)
    dark = tuple(int(c * 0.66) for c in base)
    for i, c in enumerate(shades):
        img[mask & (var == i)] = c
    img[mask & ((lx == 1) | (ly == 1))] = light
    img[mask & ((lx == sw - 1) | (ly == sh - 1))] = dark
    img[mask & ((lx == 0) | (ly == 0))] = mortar


def whole_stones(core, sw, sh):
    """Mask of stones whose CENTRE is inside `core`: edges follow stone outlines, never cut a stone."""
    xi, yi = XX.astype(int), YY.astype(int)
    row = yi // sh
    off = (row % 2) * (sw // 2)
    sx = (xi + off) // sw
    cx = np.clip(sx * sw - off + sw // 2, 0, W - 1)
    cy = np.clip(row * sh + sh // 2, 0, H - 1)
    return core[cy, cx]


def dilate(mask, steps):
    out = mask.copy()
    for _ in range(steps):
        out = out | np.roll(out, 1, 0) | np.roll(out, -1, 0) | np.roll(out, 1, 1) | np.roll(out, -1, 1)
    return out


def soft_band(dist, inner, width):
    """Dithered falloff: True with decreasing density from `inner` to `inner + width`."""
    t = (dist - inner) / width
    return t < (1.0 - DITH) * 1.0


def render():
    img = np.zeros((H, W, 3), dtype=np.uint8)
    nb = W_.value_noise(140, 21)
    nm = W_.value_noise(48, 22)
    # --- grass: three calm tones in big soft zones
    grass = [(44, 64, 46), (50, 72, 50), (57, 81, 55)]
    g = tone(nb * 0.75 + nm * 0.25, 3)
    for i, c in enumerate(grass):
        img[g == i] = c
    # --- forest floor (wolves) - darker zone with a dithered edge
    fx0, fy0, fx1, fy1 = W_.FOREST
    fd = np.minimum.reduce([XX - fx0, fx1 - XX, YY - fy0, fy1 - YY]) + (nm - 0.5) * 50
    forest = fd > 0
    ff = [(34, 46, 38), (39, 52, 42)]
    fz = tone(nb, 2)
    for i, c in enumerate(ff):
        img[forest & (fz == i)] = c
    edge = (fd > -6) & (fd <= 0) & (DITH > 0.5)
    img[edge] = ff[1]
    # --- marsh: moss + clean ponds with a rim and a highlight
    cx, cy, rx, ry = W_.MARSH
    md = ((XX - cx) / rx) ** 2 + ((YY - cy) / ry) ** 2 + (nm - 0.5) * 0.35
    marsh = md < 1.0
    img[marsh] = (46, 66, 58)
    img[marsh & (md < 0.75) & (DITH > 0.4)] = (42, 61, 54)
    pn = W_.value_noise(56, 23)
    pond = marsh & (pn > 0.66) & (md < 0.8)
    rim = marsh & ~pond & (pn > 0.63) & (md < 0.83)
    img[rim] = (34, 46, 40)
    img[pond] = (38, 62, 84)
    img[pond & (W_.value_noise(10, 24) > 0.72)] = (54, 86, 110)
    # --- fields: tidy furrows
    x0, y0, x1, y1 = W_.FIELDS
    field = (XX > x0) & (XX < x1) & (YY > y0) & (YY < y1)
    furrow = (YY.astype(int) % 6)
    img[field] = (86, 66, 46)
    img[field & (furrow < 2)] = (68, 52, 38)
    img[field & (furrow == 3)] = (104, 122, 62)
    img[field & (furrow == 4)] = (124, 142, 72)
    # --- ruins: flagstones in a circle
    rxx, ryy, rr = W_.RUINS
    dr = np.hypot(XX - rxx, YY - ryy)
    ruin = dr < rr
    img[ruin] = (66, 64, 70)
    stones(img, ruin & (dr < rr - 6), 14, 10, (96, 94, 104), (52, 50, 58), 3)
    img[ruin & (np.abs(dr - rr + 3) < 1.5)] = (58, 56, 62)
    # --- dirt roads with a clean dark edge + light grass lip
    dp = np.full((H, W), 1e9, dtype=np.float32)
    for p in W_.PATHS:
        dp = np.minimum(dp, W_.dist_polyline(p))
    wob = (nm - 0.5) * 3
    half = W_.PATH_W / 2 + wob
    road = dp < half - 2
    dirt = [(82, 66, 50), (92, 74, 56), (100, 82, 62)]
    dz = tone(W_.value_noise(20, 25) * 0.7 + nb * 0.3, 3)
    for i, c in enumerate(dirt):
        img[road & (dz == i)] = c
    worn = (dp >= half - 2) & soft_band(dp, half - 2, 5.0)              # worn, dithered fade into grass
    img[worn] = (76, 70, 50)
    img[worn & (DITH > 0.6)] = (66, 72, 50)
    road = road | worn
    # --- town: grass + cobbled plaza and lanes
    tx0, ty0, tx1, ty1 = W_.TOWN
    town = (XX >= tx0) & (XX < tx1) & (YY >= ty0) & (YY < ty1)
    px0, py0, px1, py1 = W_.PLAZA
    dtr = np.full((H, W), 1e9, dtype=np.float32)
    for p in W_.TOWN_ROADS:
        dtr = np.minimum(dtr, W_.dist_polyline(p))
    core = ((XX >= px0) & (XX < px1) & (YY >= py0) & (YY < py1)) | (town & ((dtr < 11) | (dp < 13)))
    core = core | (dtr < 9)                                                # lanes continue past the gates
    plaza = whole_stones(core, 9, 6)
    near = dilate(plaza, 4) & ~plaza
    dist_soil = np.where(dilate(plaza, 1), 1, np.where(dilate(plaza, 2), 2, np.where(dilate(plaza, 3), 3, 4)))
    soil = near & (dist_soil <= 4) & ((dist_soil <= 1) | (DITH < (1.0 - (dist_soil - 1) / 3.5)))
    img[soil] = (78, 68, 52)
    img[soil & (DITH > 0.7)] = (70, 62, 48)
    stones(img, plaza, 9, 6, (100, 98, 108), (54, 52, 60), 1)
    rnd2 = random.Random(9)                                                # loose stones beyond the edge
    ys, xs = np.nonzero(near & (dist_soil >= 2))
    for i in rnd2.sample(range(len(xs)), min(len(xs), 700)):
        x, y = int(xs[i]), int(ys[i])
        if rnd2.random() < 0.35:
            img[y, x] = (110, 108, 118)
            if x + 1 < W:
                img[y, x + 1] = (84, 82, 92)
    plaza = plaza | soil
    # --- river: depth bands, foam line, sandy bank, sparkles
    drv = W_.dist_polyline(W_.RIVER)
    half_r = W_.RIVER_W / 2 + (nm - 0.5) * 8
    water = drv < half_r
    bank = (drv >= half_r) & (drv < half_r + 4)
    img[bank] = (110, 98, 72)
    img[(drv >= half_r + 3) & (drv < half_r + 4)] = (88, 80, 60)
    depth = 1 - drv / half_r
    bands = [(52, 92, 124), (40, 74, 108), (32, 60, 94), (26, 50, 82)]
    bz = tone(depth * 1.15, 4)
    for i, c in enumerate(bands):
        img[water & (bz == i)] = c
    img[water & (drv > half_r - 2)] = (120, 160, 180)                   # foam line
    flow = water & (np.sin((YY + XX * 0.15) / 9.0 + nm * 6) > 0.97) & (depth > 0.25)
    img[flow] = (78, 118, 148)
    # --- bridge: lit planks with rails
    by0, by1 = W_.BRIDGE_Y
    bridge = (YY >= by0) & (YY < by1) & (drv < W_.RIVER_W / 2 + 22)
    xi, yi = XX.astype(int), YY.astype(int)
    plank = (xi // 6) % 3
    img[bridge] = (104, 74, 50)
    img[bridge & (plank == 1)] = (116, 84, 56)
    img[bridge & (plank == 2)] = (96, 68, 46)
    img[bridge & ((xi % 6) == 0)] = (64, 44, 32)
    img[bridge & ((xi % 6) == 1)] = (132, 98, 66)
    for yy, c in ((by0, (60, 42, 30)), (by0 + 1, (150, 112, 74)), (by0 + 2, (120, 88, 58)),
                  (by1 - 3, (120, 88, 58)), (by1 - 2, (96, 68, 46)), (by1 - 1, (54, 38, 28))):
        img[bridge & (yi == yy)] = c
    # --- decals: tufts, flowers, pebbles, reeds (seeded, never on roads/water/stone)
    rnd = random.Random(5)
    free = ~(road | water | bank | plaza | field | ruin | bridge)
    tcol = {"a": (82, 114, 70), "b": (36, 52, 38)}
    fcols = [((196, 120, 150), (240, 210, 120)), ((150, 170, 220), (250, 240, 200)), ((220, 200, 110), (180, 90, 60))]
    pcol = {"a": (140, 132, 124), "b": (104, 98, 96), "c": (70, 64, 66)}
    for _ in range(5200):
        x, y = rnd.randrange(30, W - 30), rnd.randrange(30, H - 30)
        if not free[y, x]:
            continue
        r = rnd.random()
        if marsh[y, x]:
            put_decal(img, x, y, REED, {"a": (96, 120, 70), "b": (60, 80, 50)})
        elif r < 0.7:
            put_decal(img, x, y, TUFT if r < 0.4 else TUFT2, tcol)
        elif r < 0.85 and not forest[y, x]:
            fc = rnd.choice(fcols)
            put_decal(img, x, y, FLOWER, {"c": fc[0], "d": fc[1]})
        else:
            put_decal(img, x, y, PEBBLE, pcol)
    ys, xs = np.nonzero(road & ~plaza & (dp >= half - 3))              # grass tufts creeping over road edges
    for i in rnd.sample(range(len(xs)), min(len(xs), 2200)):
        put_decal(img, int(xs[i]) - 2, int(ys[i]) - 1, TUFT if i % 2 else TUFT2, tcol)
    for _ in range(900):                                                 # pebbles along roads
        x, y = rnd.randrange(30, W - 30), rnd.randrange(30, H - 30)
        if road[y, x] and not plaza[y, x] and rnd.random() < 0.6:
            put_decal(img, x, y, PEBBLE, pcol)
    # --- map frame
    frame = (XX < 24) | (YY < 24) | (XX > W - 25) | (YY > H - 25)
    img[frame] = (20, 26, 22)
    return Image.fromarray(img, "RGB"), drv
