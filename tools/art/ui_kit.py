"""UI kit: iron frames with gold rivets, inset slots, buttons, bars. All 9-slice friendly.
Margins for Godot StyleBoxTexture are listed in MARGINS (left, top, right, bottom)."""
from pixel import blank, put

OUT = (16, 13, 20)
IRON = [(44, 42, 54), (66, 64, 80), (94, 92, 110), (128, 126, 146)]
GOLD = [(120, 84, 34), (184, 138, 62), (236, 196, 110)]
BG = (24, 21, 30)
BG2 = (30, 27, 38)
INSET = (14, 12, 18)

MARGINS = {
    "panel": (8, 8, 8, 8), "title": (8, 8, 8, 8), "button": (4, 4, 4, 4), "button_hover": (4, 4, 4, 4),
    "button_pressed": (4, 4, 4, 4), "slot": (4, 4, 4, 4), "slot_hover": (4, 4, 4, 4),
    "tooltip": (4, 4, 4, 4), "bar_frame": (4, 3, 4, 3), "chat": (4, 4, 4, 4),
}


def _frame(w, h, border, fill, rivets=True, bevel=True):
    img = blank(w, h)
    for y in range(h):
        for x in range(w):
            edge = min(x, y, w - 1 - x, h - 1 - y)
            if edge == 0:
                c = OUT
            elif edge < border:
                # light top-left, dark bottom-right
                k = 3 if (x < border or y < border) and bevel else 1
                if x >= w - border or y >= h - border:
                    k = 0 if bevel else 1
                if edge == border - 1:
                    k = max(0, k - 1)
                c = IRON[k]
            elif edge == border:
                c = OUT
            else:
                c = fill(x, y) if callable(fill) else fill
            put(img, x, y, c)
    if rivets:
        for (x, y) in ((2, 2), (w - 4, 2), (2, h - 4), (w - 4, h - 4)):
            put(img, x, y, GOLD[2])
            put(img, x + 1, y, GOLD[1])
            put(img, x, y + 1, GOLD[1])
            put(img, x + 1, y + 1, GOLD[0])
    return img


def panel():
    return _frame(24, 24, 4, lambda x, y: BG if (x + y * 3) % 11 else BG2)


def title():
    img = _frame(24, 18, 4, (40, 32, 30))
    for x in range(5, 19):
        put(img, x, 5, GOLD[0])
        put(img, x, 12, GOLD[0])
    return img


def button(state):
    img = blank(12, 12)
    top = {"normal": (64, 52, 60), "hover": (84, 68, 70), "pressed": (36, 30, 36)}[state]
    bot = {"normal": (44, 36, 44), "hover": (60, 48, 52), "pressed": (48, 40, 48)}[state]
    border = GOLD[1] if state == "hover" else IRON[2]
    for y in range(12):
        for x in range(12):
            edge = min(x, y, 11 - x, 11 - y)
            if edge == 0:
                c = OUT
            elif edge == 1:
                c = border if state != "pressed" else IRON[0]
            else:
                c = top if y < 6 else bot
                if state != "pressed" and y == 2:
                    c = tuple(min(255, v + 18) for v in top)
            put(img, x, y, c)
    return img


def slot(hover=False):
    img = blank(12, 12)
    for y in range(12):
        for x in range(12):
            edge = min(x, y, 11 - x, 11 - y)
            if edge == 0:
                c = GOLD[1] if hover else IRON[2]
            elif edge == 1:
                c = (8, 6, 10) if (x == 1 or y == 1) else (40, 36, 48)    # inset bevel
            else:
                c = INSET
            put(img, x, y, c)
    return img


def tooltip():
    img = blank(12, 12)
    for y in range(12):
        for x in range(12):
            edge = min(x, y, 11 - x, 11 - y)
            c = OUT if edge == 0 else (GOLD[0] if edge == 1 else (12, 10, 16))
            put(img, x, y, c)
    for (x, y) in ((1, 1), (10, 1), (1, 10), (10, 10)):
        put(img, x, y, GOLD[2])
    return img


def chat():
    img = blank(12, 12)
    for y in range(12):
        for x in range(12):
            edge = min(x, y, 11 - x, 11 - y)
            c = OUT if edge == 0 else (IRON[1] if edge == 1 else (14, 12, 18, 170))
            put(img, x, y, c)
    return img


def bar_frame():
    img = blank(16, 9)
    for y in range(9):
        for x in range(16):
            edge = min(x, y, 15 - x, 8 - y)
            c = OUT if edge == 0 else (IRON[2] if edge == 1 else (10, 8, 12))
            put(img, x, y, c)
    return img


def bar_fill(color):
    dark = tuple(int(v * 0.6) for v in color)
    light = tuple(min(255, int(v * 1.25) + 20) for v in color)
    img = blank(4, 5)
    for x in range(4):
        put(img, x, 0, light)
        put(img, x, 1, color)
        put(img, x, 2, color)
        put(img, x, 3, dark)
        put(img, x, 4, dark)
    return img


def portrait():
    img = blank(40, 40)
    for y in range(40):
        for x in range(40):
            edge = min(x, y, 39 - x, 39 - y)
            if edge == 0:
                c = OUT
            elif edge < 3:
                c = GOLD[2] if edge == 1 and (x < 3 or y < 3) else GOLD[1 if edge == 1 else 0]
            elif edge == 3:
                c = OUT
            else:
                c = (20, 18, 26) if (x // 4 + y // 4) % 2 else (24, 22, 30)
            put(img, x, y, c)
    for (x, y) in ((0, 0), (39, 0), (0, 39), (39, 39)):
        put(img, x, y, (0, 0, 0, 0))
    return img


def close_btn():
    img = button("normal")
    for i in range(3, 9):
        put(img, i, i, (220, 200, 180))
        put(img, 11 - i, i, (220, 200, 180))
    return img


def divider():
    img = blank(32, 3)
    for x in range(32):
        put(img, x, 0, OUT)
        put(img, x, 1, GOLD[0] if 2 < x < 29 else IRON[1])
        put(img, x, 2, OUT)
    for x in (15, 16):
        put(img, x, 1, GOLD[2])
    return img


KIT = {
    "panel": panel(), "title": title(), "button": button("normal"), "button_hover": button("hover"),
    "button_pressed": button("pressed"), "slot": slot(), "slot_hover": slot(True), "tooltip": tooltip(),
    "chat": chat(), "bar_frame": bar_frame(), "bar_hp": bar_fill((190, 40, 48)), "bar_xp": bar_fill((70, 150, 210)),
    "portrait": portrait(), "close": close_btn(), "divider": divider(),
}
