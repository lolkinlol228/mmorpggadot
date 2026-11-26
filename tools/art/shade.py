"""Tiny pixel-art lighting renderer.

Shapes write (depth, normal, material, ao) into a G-buffer; render() lights every pixel with a
top-left key light + ambient + rim, quantises to a hue-shifted ramp with ordered dithering on band
edges, and finishes with a coloured selective outline. That is what gives sprites volume instead of
flat fills.

Screen space: x right, y down, z towards the viewer. Ground-facing "top" surfaces in the 3/4 view use
normal (0, -0.75, 0.66).
"""
import colorsys
import math
import numpy as np
from PIL import Image

LIGHT = np.array([-0.62, -0.68, 0.38])
LIGHT = LIGHT / np.linalg.norm(LIGHT)
TOP = (0.0, -0.75, 0.66)
FRONT = (0.0, 0.22, 0.97)
BAYER = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16.0


def ramp(base, n=6, hue_shift=0.08, lo=0.30, hi=1.45):
    """Hue-shifted ramp: darks drift to blue/purple and desaturate less, lights drift to warm."""
    r, g, b = [c / 255 for c in base]
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    out = []
    for i in range(n):
        t = i / (n - 1)
        vv = min(1.0, v * (lo + (hi - lo) * t))
        target = 0.66 if t < 0.5 else 0.13                      # blue-ish shadows, yellow-ish lights
        dh = ((target - h + 0.5) % 1.0) - 0.5
        hh = (h + dh * hue_shift * abs(t - 0.5) * 2) % 1.0
        ss = min(1.0, s * (1.15 - 0.45 * t) + (0.08 if t < 0.3 else 0))
        rr, gg, bb = colorsys.hsv_to_rgb(hh, ss, vv)
        out.append((int(rr * 255), int(gg * 255), int(bb * 255)))
    return out


class Mat:
    def __init__(self, base, spec=0.0, rough=1.0, tex=None, n=6, emissive=False):
        self.ramp = ramp(base, n) if not emissive else [base] * n
        self.spec = spec
        self.tex = tex          # fn(x, y) -> (albedo_offset, normal_tilt(dx, dy))
        self.emissive = emissive


PAD = 3          # transparent margin so outlines/limbs never get cut by the canvas edge


class Canvas:
    def __init__(self, w, h, pad=PAD):
        self.pad = pad
        w, h = w + 2 * pad, h + 2 * pad
        self.w, self.h = w, h
        self.depth = np.full((h, w), -1e9)
        self.nrm = np.zeros((h, w, 3))
        self.mat = np.full((h, w), -1, dtype=int)
        self.ao = np.ones((h, w))
        self.off = np.zeros((h, w))
        self.mats = []

    def _mid(self, m):
        if m not in self.mats:
            self.mats.append(m)
        return self.mats.index(m)

    def px(self, x, y, z, n, m, ao=1.0):
        x, y = int(x) + self.pad, int(y) + self.pad
        if 0 <= x < self.w and 0 <= y < self.h and z >= self.depth[y, x]:
            nn = np.array(n, dtype=float)
            off = 0.0
            if m.tex:
                o, dx, dy = m.tex(x, y)
                off = o
                nn = nn + np.array([dx, dy, 0.0])
            nn /= (np.linalg.norm(nn) + 1e-9)
            self.depth[y, x] = z
            self.nrm[y, x] = nn
            self.mat[y, x] = self._mid(m)
            self.ao[y, x] = ao
            self.off[y, x] = off

    # ---- primitives ----
    def box(self, x0, x1, y_top, top_h, y_bot, m, z=0.0, ao_bottom=True, top_m=None):
        """3/4 block: top face (top_h rows) above a front face down to y_bot."""
        for y in range(y_top, y_bot + 1):
            for x in range(x0, x1 + 1):
                if y < y_top + top_h:
                    self.px(x, y, z + 1, TOP, top_m or m)
                else:
                    t = (y - y_top - top_h) / max(1, y_bot - y_top - top_h)
                    ao = 1.0 - (0.35 * max(0, t - 0.7) / 0.3 if ao_bottom else 0)
                    edge = 0.25 if x == x0 else (-0.25 if x == x1 else 0)
                    self.px(x, y, z + 1, (-edge, FRONT[1], FRONT[2]), m, ao)

    def cylinder(self, cx, r, y_top, y_bot, m, cap_m=None, cap_ry=None, z=0.0):
        """Vertical cylinder: elliptic cap on top, curved front."""
        ry = cap_ry if cap_ry is not None else max(1.5, r * 0.45)
        for y in range(int(y_top), int(y_bot + ry) + 1):
            for x in range(int(cx - r) - 1, int(cx + r) + 2):
                nx = (x + 0.5 - cx) / r
                if abs(nx) > 1:
                    continue
                nz = math.sqrt(max(0, 1 - nx * nx))
                if y > y_bot + ry * nz:          # rounded bottom edge
                    continue
                t = (y - y_top) / max(1, y_bot + ry - y_top)
                ao = 1.0 - 0.4 * max(0, t - 0.75) / 0.25
                self.px(x, y, z + nz, (nx, 0.15, nz), m, ao)
        for y in range(int(y_top - ry), int(y_top + ry) + 1):
            for x in range(int(cx - r) - 1, int(cx + r) + 2):
                nx, ny = (x + 0.5 - cx) / r, (y + 0.5 - y_top) / ry
                if nx * nx + ny * ny <= 1:
                    self.px(x, y, z + 2, TOP, cap_m or m)

    def sphere(self, cx, cy, rx, ry, m, z=0.0, squash_top=1.0, ao_floor=None, keep=None):
        for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
            for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
                nx, ny = (x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry
                d = nx * nx + ny * ny
                if d <= 1 and (keep is None or keep(x, y)):
                    nz = math.sqrt(1 - d)
                    ao = 1.0
                    if ao_floor is not None and y > ao_floor - 3:
                        ao = 0.75
                    self.px(x, y, z + nz * min(rx, ry), (nx, ny * squash_top, nz), m, ao)

    def capsule(self, x0, y0, x1, y1, r, m, z=0.0):
        """Round limb/handle from (x0,y0) to (x1,y1)."""
        L2 = max(1e-6, (x1 - x0) ** 2 + (y1 - y0) ** 2)
        for y in range(int(min(y0, y1) - r) - 1, int(max(y0, y1) + r) + 2):
            for x in range(int(min(x0, x1) - r) - 1, int(max(x0, x1) + r) + 2):
                px_, py_ = x + 0.5, y + 0.5
                t = max(0.0, min(1.0, ((px_ - x0) * (x1 - x0) + (py_ - y0) * (y1 - y0)) / L2))
                dx, dy = px_ - (x0 + t * (x1 - x0)), py_ - (y0 + t * (y1 - y0))
                d = math.hypot(dx, dy)
                if d <= r:
                    nz = math.sqrt(max(0.0, 1 - (d / r) ** 2))
                    self.px(x, y, z + nz * r, (dx / r, dy / r, nz), m)

    def blade(self, x0, y0, x1, y1, w, m, z=0.0, taper=0.25):
        """Flat blade facing the viewer: the edges tilt away so they catch the light; tip tapers."""
        L = max(1e-6, math.hypot(x1 - x0, y1 - y0))
        ux, uy = (x1 - x0) / L, (y1 - y0) / L
        for y in range(int(min(y0, y1) - w) - 2, int(max(y0, y1) + w) + 3):
            for x in range(int(min(x0, x1) - w) - 2, int(max(x0, x1) + w) + 3):
                px_, py_ = x + 0.5 - x0, y + 0.5 - y0
                t = (px_ * ux + py_ * uy) / L
                if t < 0 or t > 1:
                    continue
                side = -px_ * uy + py_ * ux
                ww = w * min(1.0, (1.0 - t) / taper) if taper > 0 else w
                if abs(side) <= max(0.5, ww):
                    k = side / max(0.5, ww)
                    self.px(x, y, z + 1 - abs(k) * 0.5, (-uy * k * 0.9, ux * k * 0.9, 0.55), m)

    def slope(self, x0, x1, y0, y1, m, n=(0.0, -0.55, 0.83), z=0.0, taper=0):
        """A flat tilted plane (roof slope). taper>0 narrows the top by taper px per side."""
        for y in range(y0, y1 + 1):
            t = (y - y0) / max(1, y1 - y0)
            inset = int(taper * (1 - t))
            for x in range(x0 + inset, x1 - inset + 1):
                self.px(x, y, z, n, m)

    def cone(self, cx, top_y, base_y, r, m, z=0.0):
        for y in range(int(top_y), int(base_y) + 1):
            t = (y - top_y) / max(1, base_y - top_y)
            rr = max(0.6, r * t)
            for x in range(int(cx - rr) - 1, int(cx + rr) + 2):
                nx = (x + 0.5 - cx) / rr
                if abs(nx) <= 1:
                    nz = math.sqrt(max(0, 1 - nx * nx))
                    self.px(x, y, z + nz, (nx, -0.45, nz + 0.3), m)

    def occlude(self, x0, y0, x1, y1, amount=0.6):
        """Contact shadow / AO band (e.g. under eaves)."""
        p = self.pad
        for y in range(max(0, y0 + p), min(self.h, y1 + p + 1)):
            for x in range(max(0, x0 + p), min(self.w, x1 + p + 1)):
                if self.mat[y, x] >= 0:
                    self.ao[y, x] *= amount

    # ---- render ----
    def render(self, outline=True, ambient=0.12, rim=0.22):
        img = np.zeros((self.h, self.w, 4), dtype=np.uint8)
        for y in range(self.h):
            for x in range(self.w):
                mi = self.mat[y, x]
                if mi < 0:
                    continue
                m = self.mats[mi]
                n = self.nrm[y, x]
                if m.emissive:
                    img[y, x] = (*m.ramp[0], 255)
                    continue
                diff = max(0.0, float(np.dot(n, LIGHT)))
                lum = ambient + (1 - ambient) * diff ** 0.85
                if m.spec > 0:
                    hvec = LIGHT + np.array([0, 0, 1.0])
                    hvec /= np.linalg.norm(hvec)
                    lum += m.spec * max(0.0, float(np.dot(n, hvec))) ** (18 * m.spec + 6)
                if n[0] > 0.55 and diff < 0.25:
                    lum += rim * n[0]                          # bounce/rim on the shadow side
                lum *= self.ao[y, x]
                lum += self.off[y, x] * 0.07
                v = min(0.999, max(0.0, lum)) * len(m.ramp)
                v += (BAYER[y % 4, x % 4] - 0.5) * 0.22       # narrow ordered-dither band on tone edges
                k = max(0, min(len(m.ramp) - 1, int(v)))
                img[y, x] = (*m.ramp[k], 255)
        out = Image.fromarray(img, "RGBA")
        return selout(out) if outline else out


def selout(img, dark=0.42):
    """Selective outline: outline pixel = darkened neighbour colour, not black."""
    src = img.copy()
    img = img.copy()
    px = src.load()
    out = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            if px[x, y][3]:
                continue
            best = None
            for dx, dy in ((0, 1), (1, 0), (-1, 0), (0, -1)):
                xx, yy = x + dx, y + dy
                if 0 <= xx < w and 0 <= yy < h and px[xx, yy][3] > 200:
                    c = px[xx, yy]
                    lum = c[0] * 0.3 + c[1] * 0.59 + c[2] * 0.11
                    if best is None or lum < best[0]:
                        best = (lum, c)
            if best:
                c = best[1]
                out[x, y] = (int(c[0] * dark * 0.8), int(c[1] * dark * 0.8), int(c[2] * dark), 255)
    return img


# ---- texture helpers (return albedo offset, normal tilt dx, dy) ----

def tex_bricks(bw=8, bh=5, groove=0.6):
    def f(x, y):
        row = y // bh
        xx = (x + (row % 2) * (bw // 2)) % bw
        if y % bh == 0:
            return (-1.2, 0.0, -groove)
        if xx == 0:
            return (-1.0, -groove, 0.0)
        return (((x * 7 + row * 13) % 5 - 2) * 0.35, 0.0, 0.0)
    return f


def tex_planks(pw=4, horizontal=False):
    def f(x, y):
        a = y if horizontal else x
        b = x if horizontal else y
        if a % pw == 0:
            return (-1.0, 0.0 if horizontal else -0.4, -0.4 if horizontal else 0.0)
        grain = ((b * 3 + a * 11) % 9 == 0)
        return (-0.6 if grain else ((a // pw) % 3 - 1) * 0.3, 0.0, 0.0)
    return f


def tex_shingles(sw=5, sh=4):
    def f(x, y):
        row = y // sh
        xx = (x + (row % 2) * 2) % sw
        if y % sh == sh - 1:
            return (-1.4, 0.0, 0.6)          # lower lip of each shingle row faces down
        if xx == 0:
            return (-0.6, -0.3, 0.0)
        return (((x * 5 + row * 7) % 4 - 1.5) * 0.3, 0.0, -0.15)
    return f


def tex_noise(amount=0.5, seed=1):
    def f(x, y):
        v = ((x * 73856093) ^ (y * 19349663) ^ seed * 83492791) % 7
        return ((v - 3) / 3 * amount, 0.0, 0.0)
    return f
