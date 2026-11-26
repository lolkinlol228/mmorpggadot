"""Starter map "Пепельный Брод" (Ashford).

Layout logic (borrowed from hub-style starts like Heartwood's Oakland / Curse of Aros' Brightleaf):
  * Safe walled town on spawn: stash chest right at spawn, forge, merchant stall, tavern with fire.
  * Weakest monsters (slimes) a short walk north through the north gate - the "first step out".
  * Harder zone (wolves) only across the river - the bridge is the readable "next tier" threshold.
  * Boss arena (stone circle) in the far north-east corner, reached through the wolf forest.
  * Decorative fields west of town; dense forest frames the map edge.
Outputs: assets/custom/world/ground.png, props/*.png, layout.json (props, colliders, zones).
"""
import json
import math
import random
import numpy as np
from PIL import Image

W, H = 2400, 1600
SPAWN = (1020, 1005)
TOWN = (800, 850, 1240, 1170)            # x0, y0, x1, y1 (inside the walls)
GATE_N = (990, 1050)                     # gap in the north wall (x range)
GATE_E = (980, 1040)                     # gap in the east wall (y range)
GATE_W = (1030, 1090)                    # gap in the west wall (y range)
PLAZA = (930, 940, 1110, 1070)
TOWN_ROADS = [[(1020, 822), (1020, 940)], [(1110, 1010), (1268, 1010)], [(772, 1060), (930, 1050)],
              [(880, 950), (930, 970)], [(1180, 980), (1110, 990)], [(880, 1130), (950, 1070)], [(1160, 1130), (1100, 1070)]]
MARSH = (1010, 470, 330, 200)            # cx, cy, rx, ry  -> slimes
RIVER = [(1500, -20), (1575, 380), (1535, 800), (1585, 1210), (1550, 1620)]
RIVER_W = 72
BRIDGE_Y = (986, 1034)
FOREST = (1680, 640, 2380, 1420)          # wolves
RUINS = (2060, 330, 175)                  # golem arena
FIELDS = (300, 880, 660, 1240)
PATHS = [
    [(1020, 800), (1020, 660), (1000, 520), (1030, 300), (1010, 60)],                     # north road
    [(1280, 1010), (1450, 1010), (1700, 1010), (1880, 960), (1960, 700), (2040, 480)],     # east road
    [(800, 1060), (660, 1060), (420, 1080), (80, 1100)],                                    # west road
]
PATH_W = 26

rng = np.random.default_rng(7)


# ---------- noise helpers ----------

def value_noise(scale, seed):
    r = np.random.default_rng(seed)
    gw, gh = W // scale + 2, H // scale + 2
    grid = r.random((gh, gw))
    ys = np.arange(H) / scale
    xs = np.arange(W) / scale
    y0 = ys.astype(int)
    x0 = xs.astype(int)
    fy = (ys - y0)[:, None]
    fx = (xs - x0)[None, :]
    fy = fy * fy * (3 - 2 * fy)
    fx = fx * fx * (3 - 2 * fx)
    a = grid[y0][:, x0]
    b = grid[y0][:, x0 + 1]
    c = grid[y0 + 1][:, x0]
    d = grid[y0 + 1][:, x0 + 1]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


YY, XX = np.mgrid[0:H, 0:W].astype(np.float32)
N_BIG = value_noise(96, 1)
N_MED = value_noise(24, 2)
N_SMALL = value_noise(6, 3)
SPECK = rng.random((H, W))


def dist_polyline(pts):
    d = np.full((H, W), 1e9, dtype=np.float32)
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        dx, dy = x1 - x0, y1 - y0
        L = dx * dx + dy * dy
        t = np.clip(((XX - x0) * dx + (YY - y0) * dy) / L, 0, 1)
        px, py = x0 + t * dx, y0 + t * dy
        d = np.minimum(d, np.hypot(XX - px, YY - py))
    return d


def pal(img, mask, colors, idx):
    for i, c in enumerate(colors):
        m = mask & (idx == i)
        img[m] = c


# ---------- ground ----------

def render_ground():
    img = np.zeros((H, W, 3), dtype=np.uint8)
    # grass with large tonal patches + small specks
    grass = [(38, 56, 42), (46, 66, 48), (54, 76, 54), (64, 88, 60)]
    g = np.clip((N_BIG * 0.6 + N_MED * 0.4) * 3.2 - 0.3, 0, 3).astype(int)
    g = np.where(SPECK < 0.04, np.minimum(g + 1, 3), g)
    g = np.where(SPECK > 0.975, np.maximum(g - 1, 0), g)
    pal(img, np.ones((H, W), bool), grass, g)
    # wolf forest floor: darker, needles
    fx0, fy0, fx1, fy1 = FOREST
    edge = N_MED * 60
    forest = (XX > fx0 - edge) & (XX < fx1 + edge) & (YY > fy0 - edge) & (YY < fy1 + edge)
    floor = [(30, 40, 34), (36, 48, 38), (44, 56, 42), (58, 52, 40)]
    f = np.clip(N_MED * 3.5 - 0.4, 0, 2).astype(int)
    f = np.where(SPECK > 0.96, 3, f)
    pal(img, forest, floor, f)
    # marsh around the slime pond
    cx, cy, rx, ry = MARSH
    mm = ((XX - cx) / rx) ** 2 + ((YY - cy) / ry) ** 2 < 1.0 + (N_MED - 0.5) * 0.6
    marsh = [(40, 58, 52), (48, 68, 58), (58, 80, 64)]
    m = np.clip(N_SMALL * 3, 0, 2).astype(int)
    pal(img, mm, marsh, m)
    puddle = (N_MED > 0.55) & (N_BIG > 0.5) & mm
    img[puddle] = (36, 60, 78)
    img[puddle & (N_SMALL > 0.85) & (SPECK > 0.6)] = (70, 102, 120)
    reeds = mm & ~puddle & (SPECK > 0.985)
    img[reeds] = (98, 120, 70)
    # fields: crop rows
    x0, y0, x1, y1 = FIELDS
    field = (XX > x0) & (XX < x1) & (YY > y0) & (YY < y1)
    rows = ((YY.astype(int) // 4) % 3 == 0)
    img[field] = (78, 62, 44)
    img[field & rows] = (96, 112, 58)
    img[field & rows & (SPECK > 0.7)] = (140, 140, 70)
    # ruins: gravel circle + slabs
    rx_, ry_, rr = RUINS
    dr = np.hypot(XX - rx_, YY - ry_)
    ruin = dr < rr + (N_MED - 0.5) * 30
    gravel = [(60, 58, 62), (72, 70, 74), (84, 82, 86)]
    pal(img, ruin, gravel, np.clip(N_SMALL * 3, 0, 2).astype(int))
    slabs = ruin & (dr < rr * 0.55) & (((XX.astype(int) // 14) + (YY.astype(int) // 10)) % 2 == 0) & (N_MED > 0.35)
    img[slabs] = (92, 90, 96)
    ring = (np.abs(dr - rr * 0.8) < 3) & ruin
    img[ring] = (100, 96, 104)
    # dirt roads
    dp = np.full((H, W), 1e9, dtype=np.float32)
    for p in PATHS:
        dp = np.minimum(dp, dist_polyline(p))
    road = dp < PATH_W / 2 + (N_SMALL - 0.5) * 6
    dirt = [(74, 60, 48), (86, 70, 54), (100, 84, 64)]
    pal(img, road, dirt, np.clip(N_SMALL * 2.4 + N_MED * 0.8 - 0.3, 0, 2).astype(int))
    img[road & (SPECK > 0.985)] = (126, 112, 92)
    road_edge = (dp >= PATH_W / 2 + (N_SMALL - 0.5) * 6) & (dp < PATH_W / 2 + 2 + (N_SMALL - 0.5) * 6)
    img[road_edge] = (40, 52, 40)
    # town ground: packed earth + cobbled plaza with mortar lines
    tx0, ty0, tx1, ty1 = TOWN
    town = (XX >= tx0) & (XX < tx1) & (YY >= ty0) & (YY < ty1)
    tg = np.clip(N_MED * 3, 0, 2).astype(int)
    tg = np.where(SPECK < 0.05, np.minimum(tg + 1, 2), tg)
    pal(img, town, [(54, 74, 50), (62, 84, 56), (72, 96, 62)], tg)
    flowers = town & (N_BIG > 0.62) & (SPECK > 0.94)
    img[flowers] = (190, 120, 140)
    img[flowers & (SPECK > 0.97)] = (220, 200, 120)
    px0, py0, px1, py1 = PLAZA
    plaza = (XX >= px0) & (XX < px1) & (YY >= py0) & (YY < py1)
    dtr = np.full((H, W), 1e9, dtype=np.float32)
    for p in TOWN_ROADS:
        dtr = np.minimum(dtr, dist_polyline(p))
    plaza |= town & ((dtr < 11) | (dp < 13))
    xi, yi = XX.astype(int), YY.astype(int)
    brick_row = yi // 6
    brick_x = (xi + (brick_row % 2) * 5) // 10
    shade = ((brick_x * 7 + brick_row * 3) % 4)
    stones = [(78, 76, 86), (88, 86, 96), (98, 96, 106), (84, 80, 88)]
    pal(img, plaza, stones, shade)
    mortar = plaza & (((yi % 6) == 0) | (((xi + (brick_row % 2) * 5) % 10) == 0))
    img[mortar] = (52, 50, 58)
    # river with shore, ripples and a bridge
    dr_ = dist_polyline(RIVER)
    wobble = (N_MED - 0.5) * 14
    water = dr_ < RIVER_W / 2 + wobble
    shore = (dr_ >= RIVER_W / 2 + wobble) & (dr_ < RIVER_W / 2 + 5 + wobble)
    img[shore] = (88, 80, 60)
    img[shore & (SPECK > 0.7)] = (104, 94, 70)
    deep = [(24, 40, 66), (30, 50, 80), (38, 64, 96)]
    depth = np.clip(2 - (dr_ / (RIVER_W / 2)) * 2.2, 0, 2).astype(int)
    pal(img, water, deep[::-1], depth)
    ripple = water & ((np.sin(YY / 7 + N_MED * 8) > 0.92) & (SPECK > 0.3))
    img[ripple] = (86, 124, 150)
    by0, by1 = BRIDGE_Y
    bridge = (YY >= by0) & (YY < by1) & (dr_ < RIVER_W / 2 + 22)
    plank = (xi // 5) % 2
    img[bridge] = (96, 68, 46)
    img[bridge & (plank == 1)] = (112, 80, 54)
    img[bridge & ((xi % 5) == 0)] = (58, 40, 30)
    img[bridge & ((yi == by0) | (yi == by1 - 1) | (yi == by0 + 1) | (yi == by1 - 2))] = (62, 42, 32)
    # map edge vignette
    border = (XX < 24) | (YY < 24) | (XX > W - 25) | (YY > H - 25)
    img[border] = (18, 22, 20)
    return Image.fromarray(img, "RGB"), dr_


# ---------- props + colliders ----------

def layout(river_dist):
    rnd = random.Random(11)
    props = []
    rects = []      # [x, y, w, h]
    circles = []    # [x, y, r]

    def prop(kind, x, y, col=None):
        props.append({"k": kind, "x": int(x), "y": int(y)})
        if col == "circle":
            circles.append([int(x), int(y) - 3, 7])
        elif col:
            cx, cy, cw, ch = col
            rects.append([int(x + cx), int(y + cy), cw, ch])

    tx0, ty0, tx1, ty1 = TOWN
    # walls: horizontal segments top/bottom, vertical left/right, gates as gaps with towers
    for x in range(tx0, tx1, 16):
        if not (GATE_N[0] - 8 <= x <= GATE_N[1]):
            prop("wall_h", x + 8, ty0)
        prop("wall_h", x + 8, ty1 + 14)
    rects += [[tx0, ty0 - 12, GATE_N[0] - tx0 - 6, 12], [GATE_N[1] + 6, ty0 - 12, tx1 - GATE_N[1] - 6, 12],
              [tx0, ty1, tx1 - tx0, 14]]
    for y in range(ty0, ty1 + 1, 16):
        if not (GATE_W[0] - 10 <= y <= GATE_W[1]):
            prop("wall_v", tx0 - 6, y + 16)
        if not (GATE_E[0] - 10 <= y <= GATE_E[1]):
            prop("wall_v", tx1 + 6, y + 16)
    rects += [[tx0 - 12, ty0 - 12, 12, GATE_W[0] - ty0 + 6], [tx0 - 12, GATE_W[1] + 6, 12, ty1 - GATE_W[1] + 8],
              [tx1, ty0 - 12, 12, GATE_E[0] - ty0 + 6], [tx1, GATE_E[1] + 6, 12, ty1 - GATE_E[1] + 8]]
    for (x, y) in ((GATE_N[0] - 14, ty0 + 4), (GATE_N[1] + 14, ty0 + 4), (tx1 + 6, GATE_E[0] - 8),
                   (tx1 + 6, GATE_E[1] + 24), (tx0 - 6, GATE_W[0] - 8), (tx0 - 6, GATE_W[1] + 24),
                   (tx0 - 6, ty0 + 4), (tx1 + 6, ty0 + 4), (tx0 - 6, ty1 + 16), (tx1 + 6, ty1 + 16)):
        prop("tower", x, y, (-10, -12, 20, 12))
    # town buildings (footprints are the bottom part of the sprite)
    prop("forge", 880, 935, (-38, -36, 76, 36))
    prop("anvil", 930, 958, (-8, -6, 16, 6))
    prop("barrel", 834, 950, (-6, -6, 12, 6))
    prop("barrel", 846, 956, (-6, -6, 12, 6))
    prop("stall", 1175, 965, (-28, -20, 56, 20))
    prop("crate", 1210, 975, (-6, -6, 12, 6))
    prop("crate", 1221, 966, (-6, -6, 12, 6))
    prop("house", 1150, 905, (-36, -36, 72, 36))
    prop("tavern", 880, 1150, (-40, -36, 80, 36))
    prop("campfire0", 950, 1120, (-7, -6, 14, 6))
    prop("barrel", 925, 1150, (-6, -6, 12, 6))
    prop("house", 1165, 1150, (-36, -36, 72, 36))
    for (x, y) in ((828, 880), (1212, 880), (832, 1100), (1215, 1100), (1080, 1145)):
        prop("pine_small", x, y, "circle")
    for (x, y) in ((960, 900), (1070, 900), (1100, 1125)):
        prop("bush_berry", x, y, (-8, -5, 16, 5))
    # village clutter: planters by doors, benches on the plaza, laundry, cart, hay, fences, signs
    small = (-9, -5, 18, 5)
    for (k, x, y) in (("planter", 1108, 918), ("planter2", 1196, 918), ("planter", 835, 1163), ("planter2", 926, 1163),
                      ("planter", 1124, 1163), ("planter2", 1207, 1163)):
        prop(k, x, y, small)
    prop("bench", 965, 1092, (-12, -6, 24, 6))
    prop("bench", 1078, 1092, (-12, -6, 24, 6))
    prop("laundry", 1200, 1068, (-20, -3, 40, 3))
    prop("cart", 1214, 935, (-18, -8, 36, 8))
    prop("sacks", 1140, 978, small)
    prop("haybale", 826, 992, small)
    prop("haybale", 842, 1004, small)
    prop("fence_long", 838, 1092, (-19, -4, 38, 4))
    prop("fence", 1206, 876, (-11, -4, 22, 4))
    prop("crate", 1236, 1120, (-6, -6, 12, 6))
    prop("barrel", 1224, 1128, (-6, -6, 12, 6))
    for (x, y) in ((1062, 804), (1300, 972), (758, 1028), (1640, 990)):
        prop("signpost", x, y, (-3, -3, 6, 3))
    # bridge rails
    for x in range(1503, 1612, 24):
        prop("rail", x + 12, BRIDGE_Y[0] + 2)
        prop("rail", x + 12, BRIDGE_Y[1] + 8)
    # fields: scarecrow + hay
    prop("scarecrow", 480, 992, (-3, -3, 6, 3))
    for (x, y) in ((360, 1188), (620, 950), (640, 1200)):
        prop("haybale", x, y, small)
    prop("chest", SPAWN[0] + 46, SPAWN[1] - 6, (-9, -6, 18, 6))
    prop("board", SPAWN[0] - 48, SPAWN[1] - 40, (-12, -5, 24, 5))
    prop("well", SPAWN[0], SPAWN[1] + 70, (-12, -10, 24, 10))
    for (x, y) in ((GATE_N[0] - 6, ty0 + 40), (GATE_N[1] + 6, ty0 + 40), (tx1 - 30, GATE_E[0] - 6),
                   (tx1 - 30, GATE_E[1] + 18), (PLAZA[0], PLAZA[1]), (PLAZA[2], PLAZA[3])):
        prop("lamp", x, y, (-3, -3, 6, 3))
    # landmarks outside: bridge lamps, signposts, ruins pillars
    for dx in (-48, 48):
        prop("lamp", 1555 + dx, BRIDGE_Y[0] - 6, (-3, -3, 6, 3))
    rx, ry, rr = RUINS
    for i in range(10):
        a = i * math.tau / 10
        kind = "pillar_broken" if i % 3 == 1 else "pillar"
        prop(kind, rx + math.cos(a) * rr * 0.8, ry + math.sin(a) * rr * 0.8 + 10, (-7, -5, 14, 5))

    # forest + scattered trees outside the town, off roads, off water
    dp = np.full((H, W), 1e9, dtype=np.float32)
    for p in PATHS:
        dp = np.minimum(dp, dist_polyline(p))

    def free(x, y, road_clear=30):
        if not (30 < x < W - 30 and 40 < y < H - 20):
            return False
        if tx0 - 60 < x < tx1 + 60 and ty0 - 70 < y < ty1 + 50:
            return False
        if dp[int(y), int(x)] < road_clear or river_dist[int(y), int(x)] < RIVER_W / 2 + 18:
            return False
        if math.hypot(x - rx, y - ry) < rr + 20:
            return False
        if FIELDS[0] - 10 < x < FIELDS[2] + 10 and FIELDS[1] - 10 < y < FIELDS[3] + 10:
            return False
        mx, my, mrx, mry = MARSH
        if ((x - mx) / mrx) ** 2 + ((y - my) / mry) ** 2 < 0.55:
            return False
        return True

    trees = []
    fx0, fy0, fx1, fy1 = FOREST
    for _ in range(1400):
        x, y = rnd.uniform(0, W), rnd.uniform(0, H)
        in_forest = fx0 < x < fx1 and fy0 < y < fy1
        edge = x < 110 or y < 110 or x > W - 110 or y > H - 90
        p = 0.55 if in_forest else (0.85 if edge else 0.08)
        if rnd.random() > p or not free(x, y, 34 if in_forest else 30):
            continue
        if any(abs(x - tx_) < 18 and abs(y - ty_) < 14 for tx_, ty_ in trees):
            continue
        trees.append((x, y))
        kind = rnd.choice(["pine", "pine", "pine_big", "pine_small"]) if (in_forest or edge) else \
            rnd.choice(["pine", "pine_small", "pine", "bush", "bush_berry", "rock"])
        col = "circle" if kind.startswith("pine") or kind == "deadtree" else (-8, -5, 16, 5)
        prop(kind, x, y, col)
    # stumps, logs and mushrooms near forests and map edges
    for _ in range(260):
        x, y = rnd.uniform(40, W - 40), rnd.uniform(60, H - 40)
        in_forest = fx0 - 30 < x < fx1 + 30 and fy0 - 30 < y < fy1 + 30
        edge = x < 180 or y < 160 or x > W - 180 or y > H - 140
        if not (in_forest or edge) or not free(x, y, 30):
            continue
        if any(abs(x - tx_) < 16 and abs(y - ty_) < 12 for tx_, ty_ in trees):
            continue
        trees.append((x, y))
        r = rnd.random()
        kind = "mushrooms" if r < 0.45 else ("stump" if r < 0.8 else "log")
        prop(kind, x, y, None if kind == "mushrooms" else (-7, -4, 14, 4))
    # field fence posts and crates
    for x in range(FIELDS[0], FIELDS[2], 40):
        prop("crate" if rnd.random() < 0.15 else "bush", x, FIELDS[1] - 6, (-6, -4, 12, 4))
    # river as colliders except at the bridge
    for i in range(0, H + 40, 14):
        if BRIDGE_Y[0] - 10 < i < BRIDGE_Y[1] + 10:
            continue
        xs = np.where(river_dist[min(i, H - 1)] < RIVER_W / 2 - 4)[0]
        if len(xs):
            circles.append([int(xs.mean()), i, int(len(xs) / 2)])
    zones = {
        "spawn": list(SPAWN), "town": list(TOWN),
        "slime": [MARSH[0], MARSH[1], MARSH[2] * 0.75, MARSH[3] * 0.75],
        "wolf": [FOREST[0] + 40, FOREST[1] + 40, FOREST[2] - 40, FOREST[3] - 40],
        "golem": [rx, ry],
        "npcs": [
            ["Мира", "торговка", 1175, 950, {"race": "elf", "skin": "pale", "hair": "long", "hair_color": "red"}, {"body": ["robe", 1]}, "down"],
            ["Горн", "кузнец", 930, 946, {"race": "dwarf", "skin": "mid", "hair": "short", "hair_color": "red"}, {"body": ["armor", 0], "weapon": ["axe", 0]}, "down"],
            ["Стражник", "у ворот", 978, 836, {"skin": "light", "hair": "short", "hair_color": "brown"}, {"body": ["armor", 1], "head": ["helm", 1], "weapon": ["sword", 1]}, "down"],
            ["Стражник", "у ворот", 1064, 836, {"skin": "mid", "hair": "short", "hair_color": "black"}, {"body": ["armor", 1], "head": ["helm", 1], "weapon": ["sword", 1]}, "down"],
            ["Стражница", "у ворот", 1262, 1050, {"race": "felin", "skin": "light", "hair": "tail", "hair_color": "blond"}, {"body": ["armor", 1], "weapon": ["sword", 1]}, "side_left"],
            ["Лина", "жительница", 1050, 1084, {"skin": "light", "hair": "tail", "hair_color": "blond"}, {}, "side_left"],
            ["Старый Ив", "трактирщик", 944, 1130, {"race": "human", "skin": "light", "hair": "short", "hair_color": "white"}, {}, "down"],
            ["Рыбак", "у моста", 1622, 1052, {"race": "orc", "skin": "olive", "hair": "spiky", "hair_color": "black"}, {"feet": ["boots", 0]}, "side_left"],
        ],
        "chimneys": [[p["x"], p["y"], p["k"]] for p in props if p["k"] in ("house", "forge", "tavern")],
        "interact": [
            {"kind": "bank", "x": SPAWN[0] + 46, "y": SPAWN[1] - 6, "h": 22, "label": "Хранилище"},
            {"kind": "shop", "x": 1175, "y": 962, "h": 50, "label": "Лавка Миры"},
            {"kind": "board", "x": SPAWN[0] - 48, "y": SPAWN[1] - 40, "h": 40, "label": "Доска заказов"},
            {"kind": "talk", "x": 930, "y": 946, "h": 46, "label": "Горн, кузнец", "lines": [
                "Наковальня остынет — тогда и поговорим об улучшении оружия. Скоро.",
                "Волчьи клыки тупят даже хорошую сталь. Береги клинок за мостом.",
                "Видел я Клинок Бездны однажды. Холодный, как дно колодца."]},
            {"kind": "talk", "x": 978, "y": 836, "h": 46, "label": "Стражник", "lines": [
                "На север — Слизневая топь. Для новичков самое то.",
                "Внутри стен ни одна тварь тебя не тронет. Город под защитой."]},
            {"kind": "talk", "x": 1064, "y": 836, "h": 46, "label": "Стражник", "lines": [
                "Говорят, в Круге Голема по ночам светятся руны.",
                "Сдавай добычу в хранилище — сумка не резиновая."]},
            {"kind": "talk", "x": 1262, "y": 1050, "h": 46, "label": "Стражница", "lines": [
                "Мост — граница. Дальше волки, и ходят они стаями.",
                "Без зелий в Волчий лес не суйся. Мира продаёт."]},
            {"kind": "talk", "x": 1050, "y": 1084, "h": 46, "label": "Лина", "lines": [
                "Говорят, раз в тысячу находок вещь выходит сияющей!",
                "Вода в колодце ледяная даже летом."]},
            {"kind": "talk", "x": 944, "y": 1130, "h": 46, "label": "Старый Ив", "lines": [
                "Таверна закрыта на ремонт, но у костра место всегда найдётся.",
                "Платиновый Осколок Удачи... за жизнь видел всего два."]},
            {"kind": "talk", "x": 1622, "y": 1052, "h": 46, "label": "Рыбак", "lines": [
                "Клюёт плохо. Волки распугали всю рыбу.",
                "За мостом держись дороги — в чаще легко заблудиться."]},
        ],
        "labels": [["Пепельный Брод", SPAWN[0], TOWN[1] - 34], ["Слизневая топь", MARSH[0], MARSH[1] - MARSH[3] - 10],
                   ["Волчий лес", 2010, FOREST[1] - 10], ["Круг Голема", rx, ry - rr - 18]],
    }
    props.sort(key=lambda p: p["y"])
    return {"props": props, "rects": rects, "circles": circles, "zones": zones, "size": [W, H]}


def build(out_dir):
    out_dir.mkdir(parents=True, exist_ok=True)
    import ground_clean
    img, river_dist = ground_clean.render()
    img.save(out_dir / "ground.png", optimize=True)
    mask = (river_dist < RIVER_W / 2 - 2)
    Image.fromarray((mask * 255).astype(np.uint8), "L").save(out_dir / "water_mask.png")
    lay = layout(river_dist)
    (out_dir / "layout.json").write_text(json.dumps(lay, ensure_ascii=False), encoding="utf-8")
    return img, lay
