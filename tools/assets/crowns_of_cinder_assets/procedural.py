"""Procedural pixel-art drawers. Every drawer is deterministic for a given
seed and only paints palette colours, so its output passes validation without
quantisation. These are the placeholder/production source for terrain, roads,
fog, map decorations, structures and UI frames until (or unless) AI-generated
sources replace them; see assets/specs/*.json for which drawer each asset uses.
"""
from __future__ import annotations

import math
import random
from typing import Callable

from PIL import Image, ImageDraw

from .palette import Palette, RGB

TILE = 40

# ----------------------------------------------------------------- helpers --


class Pen:
    """Tiny pixel canvas with palette-char colours."""

    def __init__(self, pal: Palette, w: int, h: int, fill: str | None = None):
        self.pal = pal
        self.img = Image.new("RGBA", (w, h), (0, 0, 0, 0) if fill is None else pal.c(fill) + (255,))
        self.px = self.img.load()
        self.w, self.h = w, h

    def put(self, x: int, y: int, ch: str, alpha: int = 255) -> None:
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[x, y] = self.pal.c(ch) + (alpha,)

    def get_alpha(self, x: int, y: int) -> int:
        if 0 <= x < self.w and 0 <= y < self.h:
            return self.px[x, y][3]
        return 0

    def rect(self, x0: int, y0: int, x1: int, y1: int, ch: str) -> None:
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                self.put(x, y, ch)

    def poly(self, pts: list[tuple[float, float]], ch: str) -> None:
        d = ImageDraw.Draw(self.img)
        d.polygon(pts, fill=self.pal.c(ch) + (255,))

    def line(self, pts: list[tuple[float, float]], ch: str) -> None:
        d = ImageDraw.Draw(self.img)
        d.line(pts, fill=self.pal.c(ch) + (255,), width=1)

    def ellipse(self, box: tuple[float, float, float, float], ch: str) -> None:
        d = ImageDraw.Draw(self.img)
        d.ellipse(box, fill=self.pal.c(ch) + (255,))


# -------------------------------------------------------------- ground tiles --
# Tiles are TILE px and drawn at 1x. Every terrain has a smooth mottling field
# that is periodic over one tile and shared by all its variants, so variants
# tile seamlessly with each other; variants differ only in their features.


def periodic_field(seed: int, n: int = TILE, cells: tuple[int, ...] = (4, 8)) -> list[list[float]]:
    """Smooth value noise in [0, 1], periodic with period n in x and y."""
    rng = random.Random(seed)
    out = [[0.0] * n for _ in range(n)]
    total = 0.0
    for octave, c in enumerate(cells):
        amp = 1.0 / (octave + 1)
        total += amp
        g = [[rng.random() for _ in range(c)] for _ in range(c)]
        for y in range(n):
            fy = y * c / n
            y0, ty = int(fy), fy - int(fy)
            ty = ty * ty * (3 - 2 * ty)
            for x in range(n):
                fx = x * c / n
                x0, tx = int(fx), fx - int(fx)
                tx = tx * tx * (3 - 2 * tx)
                a = g[y0 % c][x0 % c] * (1 - tx) + g[y0 % c][(x0 + 1) % c] * tx
                b = g[(y0 + 1) % c][x0 % c] * (1 - tx) + g[(y0 + 1) % c][(x0 + 1) % c] * tx
                out[y][x] += amp * (a * (1 - ty) + b * ty)
    lo = min(min(r) for r in out)
    hi = max(max(r) for r in out)
    return [[(v - lo) / (hi - lo + 1e-9) for v in r] for r in out]


def mottle(p: Pen, rng: random.Random, field: list[list[float]], tones: list[str], dither: float = 0.08) -> None:
    """Paints tones (dark..light) by field value with dithered boundaries."""
    k = len(tones)
    for y in range(p.h):
        for x in range(p.w):
            v = field[y % len(field)][x % len(field)] + (rng.random() - 0.5) * dither * 2
            i = max(0, min(k - 1, int(v * k)))
            p.put(x, y, tones[i])


def speckle(p: Pen, rng: random.Random, weights: list[tuple[str, float]]) -> None:
    for y in range(p.h):
        for x in range(p.w):
            r = rng.random()
            acc = 0.0
            for ch, wgt in weights:
                acc += wgt
                if r < acc:
                    p.put(x, y, ch)
                    break


def periodic_offsets(rng: random.Random, n: int = TILE, lo: int = -3, hi: int = 3) -> list[int]:
    """A bumpy profile whose ends meet, so fringes join across tiles."""
    vals = [0]
    for _ in range(n - 1):
        vals.append(max(lo, min(hi, vals[-1] + rng.choice((-1, 0, 0, 0, 1)))))
    for i in range(n - 1, n - 6, -1):
        vals[i] = int(round(vals[i] * (n - 1 - i) / 5.0))
    return vals


def _blade(p: Pen, x: int, y: int, h: int, lean: int, ch: str, tip: str) -> None:
    for i in range(h):
        p.put(x + (lean * i) // max(1, h), y - i, ch if i < h - 1 else tip)


def _tufts(p: Pen, rng: random.Random, n: int, top: str, side: str, shadow: str) -> None:
    for _ in range(n):
        x, y = rng.randint(2, p.w - 3), rng.randint(5, p.h - 2)
        p.put(x - 1, y + 1, shadow)
        p.put(x, y + 1, shadow)
        p.put(x + 1, y + 1, shadow)
        _blade(p, x, y, rng.randint(3, 5), 0, side, top)
        _blade(p, x - 1, y, rng.randint(2, 4), -2, side, top)
        _blade(p, x + 1, y, rng.randint(2, 4), 2, side, side)


def _rock(p: Pen, rng: random.Random, cx: int, cy: int, r: int, body: str, light: str, hi: str, dark: str,
          outline: str | None = "K") -> None:
    pts = set()
    for y in range(cy - r - 1, cy + r + 2):
        for x in range(cx - r - 2, cx + r + 3):
            dx, dy = (x - cx) / (r + 1.4), (y - cy) / (r + 0.3)
            if dx * dx + dy * dy <= 1.0:
                pts.add((x, y))
    for (x, y) in pts:
        dx, dy = (x - cx) / (r + 1.4), (y - cy) / (r + 0.3)
        ch = body
        if dx + dy < -0.45:
            ch = light
        if dx + dy < -0.95:
            ch = hi
        if dx + dy > 0.55:
            ch = dark
        p.put(x, y, ch)
    if outline:
        for (x, y) in pts:
            for ddx, ddy in ((1, 0), (0, 1), (-1, 0)):
                q = (x + ddx, y + ddy)
                if q not in pts and (ddy == 1 or ddx == 1):
                    p.put(*q, outline)
    # contact shadow
    for x in range(cx - r, cx + r + 3):
        if (x, cy + r + 1) not in pts:
            p.put(x, cy + r + 2, dark)


def ground_grass(p: Pen, rng: random.Random, field) -> None:
    mottle(p, rng, field, ["M", "n", "n", "N"])
    speckle(p, rng, [("m", 0.03), ("z", 0.02)])
    _tufts(p, rng, rng.randint(6, 9), "z", "N", "M")
    for _ in range(rng.randint(2, 4)):
        _blade(p, rng.randint(2, p.w - 3), rng.randint(6, p.h - 2), rng.randint(3, 5), rng.choice((-2, 2)), "A", "d")
    if rng.random() < 0.35:
        x, y = rng.randint(4, p.w - 5), rng.randint(4, p.h - 5)
        p.put(x, y, "e")
        p.put(x + 1, y, "E")
        p.put(x, y + 1, "M")
    if rng.random() < 0.4:
        _rock(p, rng, rng.randint(6, p.w - 7), rng.randint(6, p.h - 7), 1, "5", "6", "7", "3")


def ground_forest(p: Pen, rng: random.Random, field) -> None:
    mottle(p, rng, field, ["m", "M", "M", "n"])
    speckle(p, rng, [("W", 0.05), ("l", 0.03), ("m", 0.06)])
    for _ in range(rng.randint(2, 3)):
        x, y = rng.randint(2, p.w - 10), rng.randint(3, p.h - 3)
        for i in range(rng.randint(5, 9)):
            p.put(x + i, y + (1 if i % 4 == 2 else 0), "W")
    _tufts(p, rng, 3, "N", "n", "m")


def ground_desert(p: Pen, rng: random.Random, field) -> None:
    mottle(p, rng, field, ["A", "d", "d", "D"])
    speckle(p, rng, [("a", 0.02), ("f", 0.02)])
    for _ in range(rng.randint(3, 4)):
        x0, y = rng.randint(0, p.w - 18), rng.randint(4, p.h - 4)
        length = rng.randint(12, 18)
        for i in range(length):
            yy = y + int(1.5 * math.sin(i / length * math.pi))
            p.put(x0 + i, yy, "A")
            p.put(x0 + i, yy - 1, "f" if i % 3 else "D")
    for _ in range(rng.randint(2, 4)):
        x, y = rng.randint(2, p.w - 3), rng.randint(2, p.h - 3)
        p.put(x, y, "a")
        p.put(x - 1, y, "f")
        p.put(x, y + 1, "A")
    if rng.random() < 0.35:
        x, y = rng.randint(4, p.w - 12), rng.randint(6, p.h - 6)
        p.line([(x, y), (x + 4, y + 2), (x + 9, y + 1)], "a")


def ground_snow(p: Pen, rng: random.Random, field) -> None:
    mottle(p, rng, field, ["+", "*", "*", "#"])
    speckle(p, rng, [("#", 0.04), ("=", 0.01)])
    for _ in range(rng.randint(2, 3)):
        x0, y = rng.randint(0, p.w - 16), rng.randint(5, p.h - 3)
        length = rng.randint(10, 16)
        for i in range(length):
            yy = y - int(2 * math.sin(i / length * math.pi))
            p.put(x0 + i, yy, "#")
            p.put(x0 + i, yy + 1, "+")
            p.put(x0 + i, yy + 2, "=")
    if rng.random() < 0.5:
        _rock(p, rng, rng.randint(6, p.w - 7), rng.randint(6, p.h - 7), 1, "5", "+", "#", "-")


def ground_swamp(p: Pen, rng: random.Random, field) -> None:
    mottle(p, rng, field, [";", ",", ",", "_"])
    speckle(p, rng, [("M", 0.04), ("/", 0.03)])
    for _ in range(rng.randint(2, 3)):
        cx, cy = rng.randint(9, p.w - 10), rng.randint(9, p.h - 10)
        rx, ry = rng.randint(5, 8), rng.randint(3, 5)
        for y in range(cy - ry - 2, cy + ry + 3):
            for x in range(cx - rx - 2, cx + rx + 3):
                d = ((x - cx) / (rx + 0.5)) ** 2 + ((y - cy) / (ry + 0.5)) ** 2
                if d <= 1.0:
                    p.put(x, y, ")" if d > 0.5 else "(")
                elif d <= 1.35:
                    p.put(x, y, ";" if y >= cy else "/")
        for i in range(rng.randint(2, 4)):
            p.put(cx - rx + 2 + i, cy - ry + 1, "[")
        p.put(cx + 1, cy, "N")
        p.put(cx + 2, cy, "N")
    for _ in range(rng.randint(3, 5)):
        x, y = rng.randint(2, p.w - 3), rng.randint(6, p.h - 2)
        _blade(p, x, y, rng.randint(4, 7), rng.choice((-1, 0, 1)), "N", "z")
        _blade(p, x + 1, y, rng.randint(3, 5), 1, "n", "Z")


def ground_infernal(p: Pen, rng: random.Random, field) -> None:
    mottle(p, rng, field, ["^", "~", "~", ":"])
    speckle(p, rng, [("2", 0.03), ("^", 0.05)])

    def crack(x: float, y: float, ang: float, length: int, depth: int) -> None:
        for i in range(length):
            xi, yi = int(x), int(y)
            hot = i > 1 and i < length - 2
            p.put(xi, yi + 1, "^")
            p.put(xi, yi, "o" if hot and depth == 0 else "e")
            if hot and depth == 0 and i % 3 == 1:
                p.put(xi, yi, "O")
            x += math.cos(ang)
            y += math.sin(ang)
            ang += rng.uniform(-0.5, 0.5)
            if depth < 1 and rng.random() < 0.12:
                crack(x, y, ang + rng.choice((-1.1, 1.1)), length // 2, depth + 1)

    for _ in range(rng.randint(1, 2)):
        crack(rng.randint(3, 12), rng.randint(8, p.h - 8), rng.uniform(-0.4, 0.4), rng.randint(18, 28), 0)
    for _ in range(rng.randint(1, 3)):
        x, y = rng.randint(1, p.w - 2), rng.randint(1, p.h - 2)
        p.put(x, y, "O")
        p.put(x, y + 1, "e")
    if rng.random() < 0.4:
        _rock(p, rng, rng.randint(6, p.w - 7), rng.randint(6, p.h - 7), 1, "~", ":", "4", "^", None)


def ground_rough(p: Pen, rng: random.Random, field) -> None:
    mottle(p, rng, field, ["3", "4", "4", "5"])
    speckle(p, rng, [("2", 0.04), ("6", 0.03)])
    for _ in range(rng.randint(3, 5)):
        _rock(p, rng, rng.randint(4, p.w - 5), rng.randint(4, p.h - 5), rng.randint(1, 3), "5", "6", "7", "2")
    for _ in range(rng.randint(1, 2)):
        _tufts(p, rng, 1, "N", "n", "3")


def ground_river(p: Pen, rng: random.Random, field) -> None:
    mottle(p, rng, field, ["[", "]", "]", "{"])
    for _ in range(rng.randint(7, 10)):
        x, y = rng.randint(1, p.w - 2), rng.randint(0, p.h - 7)
        length = rng.randint(3, 6)
        for i in range(length):
            p.put(x + int(math.sin(i / 2.0)), y + i, "}" if i < 2 else "{")
    for _ in range(rng.randint(1, 3)):
        _rock(p, rng, rng.randint(4, p.w - 5), rng.randint(4, p.h - 5), 1, "4", "5", "6", "[", None)
        x, y = rng.randint(3, p.w - 4), rng.randint(3, p.h - 4)
        p.put(x, y, "*")


def ground_mountain(p: Pen, rng: random.Random, field) -> None:
    mottle(p, rng, field, ["2", "3", "3", "4"])
    speckle(p, rng, [("1", 0.04), ("5", 0.02)])
    for _ in range(rng.randint(2, 3)):
        _rock(p, rng, rng.randint(4, p.w - 5), rng.randint(4, p.h - 5), rng.randint(1, 2), "4", "5", "6", "1")


def ground_water(p: Pen, rng: random.Random, field) -> None:
    mottle(p, rng, field, ["(", ")", ")", "["])
    for _ in range(rng.randint(3, 5)):
        x, y = rng.randint(1, p.w - 9), rng.randint(3, p.h - 2)
        w = rng.randint(4, 7)
        for i in range(w):
            p.put(x + i, y - (1 if 1 <= i < w - 1 else 0), "]" if i in (0, w - 1) else "{")
        p.put(x + w // 2, y - 1, "}")


def fog_shroud(p: Pen, rng: random.Random, field) -> None:
    """Near-black smoke; low contrast so the shroud never shows a tile grid."""
    speckle(p, rng, [("1", 0.30), ("K", 0.25), ("2", 0.04)])
    for _ in range(rng.randint(1, 2)):
        x, y = rng.randint(0, p.w - 12), rng.randint(2, p.h - 3)
        for i in range(rng.randint(8, 14)):
            p.put(x + i, y + int(1.5 * math.sin(i / 3.0)), "2")


GROUNDS: dict[str, Callable] = {
    "grass": ground_grass, "forest": ground_forest, "desert": ground_desert, "snow": ground_snow,
    "swamp": ground_swamp, "infernal": ground_infernal, "rough": ground_rough, "river": ground_river,
    "mountain": ground_mountain, "water": ground_water, "fog": fog_shroud,
}


def ground_tile(pal: Palette, style: str, base: str, seed: int, field_seed: int | None = None) -> Image.Image:
    p = Pen(pal, TILE, TILE, base)
    field = periodic_field(field_seed if field_seed is not None else seed)
    GROUNDS[style](p, random.Random(seed), field)
    return p.img


# ------------------------------------------------------------- transitions --

# Neighbour bits, clockwise from north. Corners only count when neither
# adjacent edge does (an edge fringe already covers that corner).
N, NE, E, SE, S, SW, W, NW = 1, 2, 4, 8, 16, 32, 64, 128
EDGES = (N, E, S, W)
CORNERS = ((NE, N, E), (SE, S, E), (SW, S, W), (NW, N, W))


def reduce_mask(bits: int) -> int:
    m = bits & (N | E | S | W)
    for c, a, b in CORNERS:
        if bits & c and not bits & a and not bits & b:
            m |= c
    return m


def all_transition_masks() -> list[int]:
    """The 46 distinct non-empty reduced masks, in canonical order."""
    return sorted({reduce_mask(b) for b in range(1, 256)} - {0})


def fringe_mask(mask: int, depth: int, offs: list[int]) -> list[list[float]]:
    """Coverage 0..1 per pixel: 1 inside the fringe of the neighbouring
    terrain, falling off over one pixel outside (used for soft fog)."""
    t = TILE
    out = [[0.0] * t for _ in range(t)]
    for y in range(t):
        for x in range(t):
            best = -99.0
            if mask & N:
                best = max(best, depth + offs[x] - y)
            if mask & S:
                best = max(best, depth + offs[x] - (t - 1 - y))
            if mask & W:
                best = max(best, depth + offs[y] - x)
            if mask & E:
                best = max(best, depth + offs[y] - (t - 1 - x))
            for c, cx, cy in ((NE, t - 1, 0), (SE, t - 1, t - 1), (SW, 0, t - 1), (NW, 0, 0)):
                if mask & c:
                    best = max(best, depth + 0.5 - math.hypot(x - cx, y - cy))
            out[y][x] = best
    return out


def transition_tile(pal: Palette, src: Image.Image, mask: int, depth: int, offs: list[int], rim: str | None) -> Image.Image:
    """Blend halfway toward neighbouring terrain at each shared edge.

    Both sides of a border contribute, so the tile boundary is the middle of
    a transition rather than the edge of a fully opaque square. Smooth maxima
    round the places where two adjacent edge fringes meet.
    """
    out = Image.new("RGBA", (TILE, TILE), (0, 0, 0, 0))
    sp, op = src.load(), out.load()
    for y in range(TILE):
        for x in range(TILE):
            weights = []
            for bit, distance, offset in ((N, y, offs[x]), (S, TILE - 1 - y, offs[x]),
                                           (W, x, offs[y]), (E, TILE - 1 - x, offs[y])):
                if mask & bit:
                    reach = max(1, depth + offset)
                    weights.append(max(0.0, 1.0 - distance / reach))
            for bit, cx, cy in ((NE, TILE - 1, 0), (SE, TILE - 1, TILE - 1),
                                (SW, 0, TILE - 1), (NW, 0, 0)):
                if mask & bit:
                    weights.append(max(0.0, 1.0 - math.hypot(x - cx, y - cy) / depth))
            coverage = 0.0
            for weight in weights:
                if weight <= 0:
                    continue
                if coverage <= 0:
                    coverage = weight
                    continue
                # Smooth union, bounded to keep exactly half at a shared edge.
                k = 0.35
                h = max(k - abs(coverage - weight), 0.0) / k
                coverage = min(1.0, max(coverage, weight) + h * h * k * 0.25)
            if coverage <= 0:
                continue
            coverage = 0.5 * coverage * coverage * (3.0 - 2.0 * coverage)
            color = sp[x, y]
            op[x, y] = color[:3] + (round(color[3] * coverage),)
    return out


def ground_detail_tile(terrain: str, seed: int) -> Image.Image:
    """Tiny translucent surface marks; kept inside their tile to avoid seams."""
    from PIL import ImageDraw
    rng = random.Random(seed)
    out = Image.new("RGBA", (TILE, TILE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(out)
    colors = {
        "grass": (141, 143, 77, 110), "forest": (154, 119, 68, 110),
        "swamp": (116, 131, 77, 105), "rough": (155, 146, 129, 120),
        "mountain": (165, 171, 171, 100), "snow": (214, 225, 229, 105),
        "desert": (184, 151, 95, 105), "infernal": (170, 87, 48, 110),
        "water": (101, 151, 162, 80), "river": (127, 155, 151, 85),
    }
    color = colors.get(terrain, (155, 143, 111, 90))
    for _ in range(rng.randint(2, 5)):
        x, y = rng.randint(6, TILE - 7), rng.randint(6, TILE - 7)
        if terrain in ("grass", "forest", "swamp"):
            draw.line((x - 2, y, x, y + 1, x + 1, y - 2), fill=color, width=1)
            draw.point((x + 2, y + 1), fill=color)
        elif terrain in ("water", "river", "snow", "desert"):
            draw.line((x - 2, y, x + rng.randint(1, 3), y), fill=color, width=1)
        elif terrain == "infernal":
            draw.line((x - 2, y - 1, x, y, x + 1, y + 2), fill=color, width=1)
        else:
            draw.ellipse((x - 1, y - 1, x + 1, y + 1), fill=color)
            draw.point((x + 3, y + 2), fill=color)
    return out


def fog_fringe_tile(pal: Palette, src: Image.Image, mask: int, depth: int, offs: list[int]) -> Image.Image:
    """Soft smoky shroud edge: stepped, dithered alpha over a band of TILE/5 px."""
    cov = fringe_mask(mask, depth, offs)
    out = Image.new("RGBA", (TILE, TILE), (0, 0, 0, 0))
    sp, op = src.load(), out.load()
    k = TILE / 20.0
    for y in range(TILE):
        for x in range(TILE):
            v = cov[y][x] / k
            if v <= -3:
                continue
            chk = (x + y) % 2 == 0
            if v > 3:
                a = 255
            elif v > 1.5:
                a = 225
            elif v > 0:
                a = 180 if chk else 150
            elif v > -1.5:
                a = 110 if chk else 80
            else:
                a = 50 if chk else 0
            if a:
                op[x, y] = sp[x, y][:3] + (a,)
    return out


# ------------------------------------------------------------------- roads --

RN, RE, RS, RW = 1, 2, 4, 8


def road_tile(pal: Palette, mask: int, seed: int, bridge: bool = False) -> Image.Image:
    rng = random.Random(seed)
    p = Pen(pal, TILE, TILE)
    half = TILE // 2
    lo, hi = half - 6, half + 5
    cells = set()
    for y in range(lo, hi + 1):
        for x in range(lo, hi + 1):
            cells.add((x, y))
    if mask & RN:
        cells |= {(x, y) for y in range(0, lo) for x in range(lo, hi + 1)}
    if mask & RS:
        cells |= {(x, y) for y in range(hi + 1, TILE) for x in range(lo, hi + 1)}
    if mask & RW:
        cells |= {(x, y) for y in range(lo, hi + 1) for x in range(0, lo)}
    if mask & RE:
        cells |= {(x, y) for y in range(lo, hi + 1) for x in range(hi + 1, TILE)}
    if mask == 0:
        cells = {(x, y) for (x, y) in cells if (x - half + 0.5) ** 2 + (y - half + 0.5) ** 2 < 40}
    # ragged verges (not on tile edges, so roads join seamlessly)
    for (x, y) in list(cells):
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            q = (x + dx, y + dy)
            if q not in cells and 1 <= q[0] < TILE - 1 and 1 <= q[1] < TILE - 1 and rng.random() < 0.18:
                cells.add(q)
    vertical = bool(mask & (RN | RS)) and not mask & (RE | RW)
    for (x, y) in cells:
        border = any((x + dx, y + dy) not in cells and 0 <= x + dx < TILE and 0 <= y + dy < TILE
                     for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
        if bridge:
            along = y if vertical else x
            across = x if vertical else y
            if border or across in (lo, hi):
                ch = "w"
            elif along % 4 == 0:
                ch = "W"
            else:
                ch = "L" if across in (lo + 1,) else "l"
        else:
            ch = "a" if border else rng.choice(("A", "A", "A", "A", "d", "a"))
            if not border and rng.random() < 0.05:
                ch = "D"
            if not border and rng.random() < 0.03:
                ch = "5"
        p.put(x, y, ch)
    if not bridge:  # wheel ruts
        for (x, y) in cells:
            if vertical and x in (lo + 3, hi - 3) and (x, y - 1) in cells and rng.random() < 0.7:
                p.put(x, y, "a")
            if not vertical and mask & (RE | RW) and y in (lo + 3, hi - 3) and rng.random() < 0.7:
                p.put(x, y, "a")
    return p.img


# ------------------------------------------------------------- decorations --
# Decoration sprites are deco_size (48x64) and stand on the bottom of their
# cell; the pipeline adds a 1 px outline.


def _pine(p: Pen, cx: int, base: int, height: int, snow: bool = False, dead: bool = False) -> None:
    trunk_h = max(3, height // 7)
    p.rect(cx - 1, base - trunk_h, cx + 1, base, "W")
    p.put(cx - 1, base - trunk_h, "l")
    tiers = 4 if height >= 28 else 3
    top = base - height
    for t in range(tiers):
        ty = top + t * (height - trunk_h) // (tiers + 1)
        hh = (height - trunk_h) // tiers + 4
        half = 3 + t * 3
        for y in range(hh):
            w = int(half * (y + 1) / hh) + (1 if y > 1 else 0)
            for x in range(cx - w, cx + w + 1):
                rel = (x - cx) / max(1, w + 1)
                ch = "n" if rel < -0.35 else ("m" if rel > 0.35 else "M")
                if y >= hh - 2:
                    ch = "m"
                if dead:
                    ch = "3" if rel < 0 else "2"
                if snow and y < 3 and rel < 0.5:
                    ch = "#" if rel < 0 else "+"
                p.put(x, ty + y, ch)
        # drooping branch tips and needle highlights
        p.put(cx - half - 1, ty + hh - 2, "m")
        p.put(cx + half + 1, ty + hh - 2, "m")
        if not dead and not snow:
            for i in range(0, half, 2):
                p.put(cx - i, ty + hh // 2 + i // 2, "N")
    p.put(cx, top - 1, "+" if snow else "M")


def deco_forest(pal: Palette, rng: random.Random, size: tuple[int, int]) -> Image.Image:
    w, h = size
    p = Pen(pal, w, h)
    spots = [(11, h - 12, 40), (33, h - 16, 44), (23, h - 2, 38), (39, h - 3, 34), (8, h - 1, 32)]
    rng.shuffle(spots)
    for cx, base, ht in sorted(spots[: rng.choice((3, 4, 4, 5))], key=lambda s: s[1]):
        _pine(p, cx + rng.randint(-2, 2), base, ht + rng.randint(-4, 4))
    return p.img


def deco_snow_pine(pal: Palette, rng: random.Random, size: tuple[int, int]) -> Image.Image:
    w, h = size
    p = Pen(pal, w, h)
    _pine(p, w // 2 + rng.randint(-6, 6), h - 3, 30 + rng.randint(-4, 4), snow=True)
    return p.img


def deco_mountain(pal: Palette, rng: random.Random, size: tuple[int, int]) -> Image.Image:
    w, h = size
    p = Pen(pal, w, h)
    base = h - 1
    peaks = [(rng.randint(18, 28), rng.randint(3, 10), 22),
             (rng.randint(6, 12), rng.randint(24, 32), 13),
             (rng.randint(36, 42), rng.randint(22, 30), 13)]
    for px_, py_, half in [peaks[1], peaks[2], peaks[0]] if rng.random() < 0.5 else [peaks[2], peaks[1], peaks[0]]:
        p.poly([(px_, py_), (px_ - half - 1, base), (px_, base)], "6")
        p.poly([(px_, py_), (px_ + half + 1, base), (px_, base)], "3")
        # ridges and strata
        for k in range(3):
            rx = px_ + rng.randint(-half // 2, half // 2)
            p.line([(px_ + (rx - px_) // 4, py_ + 4 + k * 3), (rx, base)], "4" if rx > px_ else "5")
        for y in range(py_ + 4, base, 4):
            span = (y - py_) * (half + 1) / (base - py_)
            for x in range(int(px_ - span) + 1, px_):
                if (x * 3 + y) % 7 == 0:
                    p.put(x, y, "7")
            for x in range(px_ + 1, int(px_ + span)):
                if (x + y * 2) % 5 == 0:
                    p.put(x, y, "2")
        p.line([(px_, py_), (px_ - 1, base)], "7")
        cap = max(4, (base - py_) // 3)
        for y in range(py_, py_ + cap):
            span = (y - py_) * (half + 1) / (base - py_)
            for x in range(int(px_ - span), int(px_ + span) + 1):
                jag = (x * 7 + 3) % 4
                if y < py_ + cap - jag:
                    p.put(x, y, "#" if x <= px_ else "+")
        p.line([(px_ - half - 1, base), (px_ + half + 1, base)], "2")
    return p.img


def deco_dead_tree(pal: Palette, rng: random.Random, size: tuple[int, int]) -> Image.Image:
    w, h = size
    p = Pen(pal, w, h)
    x = w // 2 + rng.randint(-6, 6)
    top = h - rng.randint(32, 40)
    p.poly([(x - 3, h - 1), (x + 3, h - 1), (x + 1, top), (x - 1, top)], "W")
    p.line([(x + 1, top + 4), (x + 2, h - 1)], "w")
    p.line([(x - 1, top + 3), (x - 2, h - 2)], "l")
    for i, (dx, dy) in enumerate(((-11, -7), (9, -9), (-7, -12), (12, -5), (-13, -2))):
        by = top + 3 + i * 5
        p.line([(x, by), (x + dx, by + dy)], "W")
        p.line([(x + dx, by + dy), (x + dx + (2 if dx > 0 else -2), by + dy - 3)], "l")
    p.line([(x - 4, h - 1), (x - 8, h - 1)], "W")
    p.line([(x + 4, h - 1), (x + 7, h - 2)], "W")
    for i in range(5):
        rx = rng.randint(2, w - 3)
        _blade(p, rx, h - 1, rng.randint(3, 6), rng.choice((-1, 1)), "N", "z")
    return p.img


def deco_obsidian(pal: Palette, rng: random.Random, size: tuple[int, int]) -> Image.Image:
    w, h = size
    p = Pen(pal, w, h)
    for i in range(rng.randint(3, 4)):
        cx = rng.randint(8, w - 9)
        tall = rng.randint(14, 28)
        lean = rng.randint(-4, 4)
        base = h - 1 - rng.randint(0, 4)
        p.poly([(cx - 5, base), (cx + 5, base), (cx + lean, base - tall)], "^")
        p.poly([(cx + lean, base - tall), (cx + 5, base), (cx + 1, base)], "~")
        p.line([(cx - 3, base), (cx + lean, base - tall)], ":")
        p.put(cx - 4, base, "o")
        p.put(cx - 3, base, "O")
        p.put(cx + 3, base, "e")
        p.line([(cx - 1, base - 2), (cx, base - tall // 2)], "e")
    return p.img


def deco_boulders(pal: Palette, rng: random.Random, size: tuple[int, int]) -> Image.Image:
    w, h = size
    p = Pen(pal, w, h)
    _rock(p, rng, rng.randint(14, 20), h - 9, 6, "5", "6", "7", "3", None)
    _rock(p, rng, rng.randint(28, 34), h - 5, 4, "4", "5", "6", "2", None)
    _rock(p, rng, rng.randint(6, 9), h - 3, 2, "4", "5", "6", "2", None)
    return p.img


def deco_bones(pal: Palette, rng: random.Random, size: tuple[int, int]) -> Image.Image:
    w, h = size
    p = Pen(pal, w, h)
    bx = rng.randint(10, 16)
    by = h - 4
    p.line([(bx, by), (bx + 24, by - 2)], "I")
    p.line([(bx, by + 1), (bx + 24, by - 1)], "i")
    for i in range(6):
        x = bx + 4 + i * 4
        top = by - 12 + (i % 2) * 2 - (i * 2 if i < 3 else (5 - i) * 2)
        p.line([(x, by - i // 3), (x - 3, top)], "j")
        p.line([(x - 3, top), (x - 1, top - 2)], "J")
    p.ellipse((bx - 8, by - 6, bx - 1, by + 1), "j")
    p.put(bx - 6, by - 4, "w")
    p.put(bx - 4, by - 4, "w")
    p.line([(bx - 7, by - 1), (bx - 2, by - 1)], "I")
    p.line([(bx - 8, by - 6), (bx - 12, by - 12)], "I")
    return p.img


def deco_gravestone(pal: Palette, rng: random.Random, size: tuple[int, int]) -> Image.Image:
    w, h = size
    p = Pen(pal, w, h)
    for k in range(rng.randint(1, 2)):
        x = rng.randint(10, 22) + k * 12
        top = h - rng.randint(16, 20)
        p.rect(x, top + 2, x + 8, h - 3, "5")
        p.ellipse((x, top, x + 8, top + 5), "5")
        p.line([(x, top + 3), (x, h - 3)], "6")
        p.line([(x + 8, top + 3), (x + 8, h - 3)], "3")
        p.line([(x + 4, top + 4), (x + 4, top + 10)], "2")
        p.line([(x + 2, top + 6), (x + 6, top + 6)], "2")
        p.put(x + 7, top + 12, "N")
        p.line([(x + 1, top + 14), (x + 3, top + 11)], "M")
        p.rect(x - 2, h - 2, x + 10, h - 1, "M")
    return p.img


DECOS = {
    "pines": deco_forest, "snow_pine": deco_snow_pine, "peaks": deco_mountain, "dead_tree": deco_dead_tree,
    "obsidian": deco_obsidian, "boulders": deco_boulders, "bones": deco_bones, "gravestone": deco_gravestone,
}


# -------------------------------------------------------------- structures --

def _crenels(p: Pen, x0: int, x1: int, y: int, ch: str, dark: str) -> None:
    for x in range(x0, x1 + 1):
        if (x - x0) % 3 != 2:
            p.put(x, y, ch)
            p.put(x, y + 1, ch)
    p.line([(x0, y + 2), (x1, y + 2)], dark)


def _tower(p: Pen, x: int, top: int, base: int, w: int, roof: str, roof_dark: str, wall: str = "6", shade: str = "4") -> None:
    p.rect(x, top, x + w - 1, base, wall)
    p.rect(x + w - 2, top, x + w - 1, base, shade)
    p.poly([(x - 1, top), (x + w, top), (x + w // 2 - 0.5, top - w - 2)], roof)
    p.poly([(x + w // 2, top), (x + w, top), (x + w // 2, top - w - 2)], roof_dark)
    p.put(x + w // 2 - 1, top + 3, "y")
    p.put(x + w // 2 - 1, top + 4, "O")


def _brick_wall(p: Pen, x0: int, y0: int, x1: int, y1: int, light: str, mid: str, dark: str, mortar: str) -> None:
    """Stone wall lit from the left: courses of offset blocks."""
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            rel = (x - x0) / max(1, x1 - x0)
            ch = light if rel < 0.25 else (mid if rel < 0.75 else dark)
            row = (y - y0) // 3
            if (y - y0) % 3 == 2 or (x + row * 3) % 7 == 0:
                ch = mortar
            p.put(x, y, ch)


def _battlements(p: Pen, x0: int, x1: int, y: int, ch: str, dark: str) -> None:
    for x in range(x0, x1 + 1):
        if (x - x0) % 4 < 2:
            p.rect(x, y, x, y + 2, ch)
    p.line([(x0, y + 3), (x1, y + 3)], dark)


def _round_tower(p: Pen, x: int, w: int, top: int, base: int, roof: str, roof_dark: str, roof_h: int) -> None:
    _brick_wall(p, x, top, x + w - 1, base, "7", "6", "4", "5")
    _battlements(p, x - 1, x + w, top - 3, "6", "3")
    cx = x + w / 2 - 0.5
    p.poly([(x - 2, top - 3), (x + w + 1, top - 3), (cx, top - 3 - roof_h)], roof)
    p.poly([(cx, top - 3 - roof_h), (x + w + 1, top - 3), (cx + 1, top - 3)], roof_dark)
    for i in range(2, roof_h, 3):
        p.line([(cx - i * (w + 3) / (2 * roof_h), top - 3 - roof_h + i), (cx, top - 3 - roof_h + i)], roof_dark)
    for wy in range(top + 4, base - 6, 9):
        p.rect(int(cx) - 1, wy, int(cx), wy + 3, "1")
        p.put(int(cx) - 1, wy + 1, "O")
        p.put(int(cx), wy + 2, "o")


def struct_town_concord(pal: Palette, rng: random.Random, size: tuple[int, int]) -> Image.Image:
    """Grim walled citadel: curtain wall, round corner towers with slate
    roofs, a tall keep, a gatehouse with portcullis and torches."""
    w, h = size
    p = Pen(pal, w, h)
    base = h - 2
    # keep (behind the wall)
    _brick_wall(p, 28, 26, 67, base - 16, "7", "6", "4", "5")
    _battlements(p, 27, 68, 22, "7", "4")
    _round_tower(p, 41, 14, 14, 30, "B", "b", 13)
    for x in (32, 38, 58, 63):
        p.rect(x, 32, x + 1, 36, "1")
        p.put(x, 33, "O")
        p.put(x + 1, 34, "o")
    for bx in (31, 60):  # hanging banners
        p.rect(bx, 40, bx + 4, 50, "B")
        p.line([(bx, 40), (bx, 50)], "c")
        p.line([(bx, 40), (bx + 4, 40)], "h")
        p.rect(bx + 1, 43, bx + 3, 46, "h")
        p.put(bx + 2, 44, "g")
        p.put(bx + 1, 51, "B")
        p.put(bx + 3, 51, "B")
    # curtain wall
    _brick_wall(p, 8, base - 20, w - 9, base, "6", "5", "4", "3")
    _battlements(p, 7, w - 8, base - 24, "6", "3")
    for x in range(10, w - 10, 6):  # weathering streaks
        p.line([(x, base - 19), (x, base - 12 - (x % 5))], "4")
    # corner towers
    _round_tower(p, 1, 13, 36, base, "B", "b", 12)
    _round_tower(p, w - 14, 13, 36, base, "B", "b", 12)
    # gatehouse
    _brick_wall(p, 38, base - 28, 57, base, "7", "6", "4", "5")
    _battlements(p, 37, 58, base - 31, "7", "4")
    p.ellipse((42, base - 18, 53, base - 6), "1")
    p.rect(42, base - 12, 53, base, "1")
    for x in range(43, 53, 2):
        p.line([(x, base - 15), (x, base - 3)], "Q")
    for y in range(base - 13, base - 2, 3):
        p.line([(43, y), (52, y)], "Q")
    p.line([(42, base - 18), (53, base - 18)], "8")
    for tx in (39, 56):
        p.line([(tx, base - 10), (tx, base - 7)], "W")
        p.put(tx, base - 11, "O")
        p.put(tx, base - 12, "y")
    p.rect(44, base - 24, 51, base - 21, "h")
    p.rect(46, base - 23, 49, base - 22, "B")
    # ground rubble
    for x in range(3, w - 3, 5):
        p.put(x, base + 1, "4")
    return p.img


def struct_town_ashen(pal: Palette, rng: random.Random, size: tuple[int, int]) -> Image.Image:
    """Obsidian bastion: a forest of jagged spires veined with lava, a wall
    weeping molten seams and a horned gate around a burning maw."""
    w, h = size
    p = Pen(pal, w, h)
    base = h - 2
    spires = [(48, 0, 11), (30, 12, 7), (66, 10, 7), (19, 26, 5), (78, 24, 5), (39, 20, 5), (57, 18, 5), (8, 38, 4), (88, 36, 4)]
    for cx, top, half in sorted(spires, key=lambda s: -s[2]):
        bottom = base - 10
        p.poly([(cx - half, bottom), (cx + half, bottom), (cx + 1, top)], "^")
        p.poly([(cx + 1, top), (cx + half, bottom), (cx + 2, bottom)], "~")
        p.line([(cx - half + 2, bottom), (cx, top + 2)], ":")
        # barbs
        for y in range(top + 8, bottom - 4, 7):
            span = (y - top) * half / (bottom - top)
            p.line([(cx - span, y), (cx - span - 3, y - 3)], "^")
            p.line([(cx + span, y), (cx + span + 3, y - 3)], "~")
        # lava vein and glowing slits
        x = cx
        for y in range(top + 6, bottom, 2):
            x += rng.choice((-1, 0, 1)) if abs(x - cx) < half // 2 else (1 if x < cx else -1)
            p.put(x, y, "e")
            p.put(x, y + 1, "o" if y % 6 == 0 else "e")
        for y in range(top + 10, bottom - 6, 12):
            p.rect(cx - 1, y, cx, y + 2, "O")
            p.put(cx, y + 1, "y")
    # wall with molten cascades
    for y in range(base - 14, base + 1):
        for x in range(4, w - 4):
            p.put(x, y, "^" if (x // 6 + y // 3) % 3 else "~")
    for x in range(4, w - 4):
        if x % 3 != 1:
            p.rect(x, base - 17, x, base - 15, ":")
    for x in range(9, w - 8, 11):
        for y in range(base - 14, base + 1):
            p.put(x + (y % 3 == 0), y, "o" if y % 4 else "O")
            p.put(x + 1, y, "e")
    # horned gate
    p.ellipse((38, base - 22, 58, base + 2), "^")
    p.poly([(38, base - 14), (26, base - 34), (31, base - 33), (42, base - 18)], "I")
    p.poly([(58, base - 14), (70, base - 34), (65, base - 33), (54, base - 18)], "I")
    p.line([(27, base - 33), (38, base - 15)], "j")
    p.line([(69, base - 33), (58, base - 15)], "i")
    p.ellipse((42, base - 17, 54, base + 1), "e")
    p.ellipse((44, base - 14, 52, base + 1), "o")
    p.ellipse((46, base - 11, 50, base + 1), "y")
    for x in range(42, 55, 3):
        p.line([(x, base - 16), (x + 1, base - 12)], "^")
    p.rect(46, base - 26, 50, base - 23, "j")
    p.put(47, base - 25, "o")
    p.put(49, base - 25, "o")
    # lava pool spilling from the gate
    p.ellipse((30, base - 1, 66, base + 3), "e")
    p.ellipse((38, base, 58, base + 2), "o")
    return p.img


ORE_COLOURS = {
    "gold": ("G", "h", "H"), "wood": ("W", "l", "L"), "ore": ("Q", "u", "S"), "mercury": ("u", "x", "X"),
    "sulfur": ("G", "h", "y"), "crystal": ("R", "e", "E"), "gems": ("]", "{", "}"),
}


def struct_mine(pal: Palette, rng: random.Random, size: tuple[int, int], resource: str = "ore") -> Image.Image:
    """Timber-framed shaft in a rock outcrop, with a cart of its resource."""
    w, h = size
    p = Pen(pal, w, h)
    base = h - 2
    p.poly([(1, base), (w - 2, base), (w * 0.62, 3), (w * 0.35, 6)], "4")
    p.poly([(w * 0.62, 3), (w - 2, base), (w * 0.62, base)], "3")
    p.line([(w * 0.35, 6), (2, base)], "6")
    p.rect(5, base - 9, 13, base, "1")
    p.rect(4, base - 10, 14, base - 10, "L")
    p.line([(4, base - 10), (4, base)], "l")
    p.line([(14, base - 10), (14, base)], "W")
    p.line([(6, base), (12, base)], "u")
    p.put(8, base - 4, "O")
    dark, mid, hi = ORE_COLOURS.get(resource, ORE_COLOURS["ore"])
    p.rect(15, base - 4, 21, base - 1, "W")
    p.line([(15, base - 4), (21, base - 4)], "l")
    for x in range(16, 21):
        p.put(x, base - 5, mid if x % 2 else dark)
    p.put(17, base - 6, hi)
    p.put(19, base - 6, mid)
    p.put(16, base, "u")
    p.put(20, base, "u")
    return p.img


def struct_flag(pal: Palette, rng: random.Random, size: tuple[int, int]) -> Image.Image:
    """Greyscale swallowtail pennant on a pole at the horizontal centre (so
    the bottom-centre anchor is the foot of the pole); tinted in game."""
    w, h = size
    p = Pen(pal, w, h)
    cx = w // 2
    p.line([(cx, 1), (cx, h - 2)], "w")
    p.put(cx, 1, "h")
    for y in range(2, 7):
        for x in range(cx + 1, w - 1 - (1 if y == 4 else 0)):
            p.put(x, y, "9" if y < 4 else "8")
    p.line([(cx + 1, 6), (w - 2, 6)], "7")
    return p.img


# ---------------------------------------------------------------- encounters --

def _ground_patch(p: Pen, w: int, base: int, ch: str = "3") -> None:
    p.ellipse((2, base - 3, w - 3, base + 1), ch)


def enc_shrine(p: Pen, rng: random.Random, w: int, h: int) -> None:
    base = h - 2
    p.rect(7, base - 12, 16, base, "5")
    p.poly([(6, base - 12), (17, base - 12), (11.5, base - 18)], "4")
    p.rect(9, base - 9, 14, base - 3, "^")
    p.rect(10, base - 8, 13, base - 5, "j")
    p.put(11, base - 7, "K")
    p.put(12, base - 7, "K")
    p.line([(10, base - 9), (13, base - 9)], "x")
    p.line([(16, base - 12), (16, base)], "3")
    p.put(5, base, "O")
    p.put(5, base - 1, "y")
    p.put(18, base, "O")


def enc_wagon(p: Pen, rng: random.Random, w: int, h: int, upright: bool = False) -> None:
    base = h - 3
    if upright:
        p.rect(3, base - 7, 19, base - 2, "l")
        p.poly([(3, base - 7), (19, base - 7), (16, base - 13), (6, base - 13)], "7")
        p.line([(6, base - 13), (16, base - 13)], "8")
        for cx in (6, 16):
            p.ellipse((cx - 3, base - 3, cx + 3, base + 3), "W")
            p.put(cx, base, "L")
        p.rect(9, base - 10, 11, base - 8, "S")
        return
    p.poly([(3, base), (18, base - 4), (19, base - 10), (5, base - 7)], "l")
    p.line([(3, base), (18, base - 4)], "W")
    p.line([(5, base - 7), (19, base - 10)], "L")
    p.ellipse((14, base - 15, 21, base - 8), "W")
    p.ellipse((16, base - 13, 19, base - 10), "l")
    p.put(17, base - 12, "L")
    for x, y in ((6, base), (9, base + 1), (12, base)):
        p.rect(x, y - 2, x + 2, y, "L")
        p.put(x, y - 2, "D")


def enc_tent(p: Pen, rng: random.Random, w: int, h: int, cloth: str = "D", trim: str = "e") -> None:
    base = h - 2
    p.poly([(2, base), (16, base), (9, base - 15)], cloth)
    p.poly([(9, base - 15), (16, base), (10, base)], "A")
    p.poly([(7, base), (11, base), (9, base - 6)], "w")
    p.line([(9, base - 15), (9, base - 18)], "W")
    p.rect(10, base - 18, 13, base - 16, trim)
    p.put(19, base, "o")
    p.put(20, base, "O")
    p.put(19, base - 1, "y")
    p.put(20, base - 2, "O")
    p.line([(17, base), (22, base)], "W")


def enc_chapel(p: Pen, rng: random.Random, w: int, h: int) -> None:
    base = h - 3
    p.ellipse((0, base - 3, w - 1, base + 2), ")")
    p.ellipse((3, base - 2, w - 4, base + 1), "(")
    p.rect(8, base - 16, 15, base, "5")
    p.rect(14, base - 16, 15, base, "3")
    p.poly([(7, base - 16), (16, base - 16), (11.5, base - 22)], "3")
    p.rect(10, base - 13, 12, base - 9, "^")
    p.put(11, base - 11, "h")
    p.line([(4, base - 1), (4, base - 5)], "N")
    p.line([(19, base), (19, base - 4)], "N")
    p.put(6, base, "}")


def enc_barrows(p: Pen, rng: random.Random, w: int, h: int) -> None:
    base = h - 2
    for cx, cy, r in ((6, base - 1, 5), (16, base - 3, 5), (11, base, 4)):
        p.ellipse((cx - r, cy - r + 1, cx + r, cy + 2), "M")
        p.ellipse((cx - r + 1, cy - r + 1, cx + r - 2, cy - 1), "n")
        p.rect(cx - 1, cy - r - 1, cx + 1, cy - r + 1, "S")
        p.put(cx - 1, cy - r - 1, "t")


def enc_pit(p: Pen, rng: random.Random, w: int, h: int) -> None:
    base = h - 3
    p.ellipse((1, base - 7, w - 2, base + 2), "3")
    p.ellipse((4, base - 5, w - 5, base), "^")
    for x in range(2, w - 2, 3):
        y = base - 4 + (2 if x % 2 else 0)
        p.line([(x, y), (x, y - 5)], "x")
        p.put(x, y - 5, "X")
    p.put(11, base - 3, "e")
    p.put(13, base - 2, "R")


def enc_rift(p: Pen, rng: random.Random, w: int, h: int) -> None:
    base = h - 3
    p.ellipse((1, base - 6, w - 2, base + 2), "~")
    pts = [(3, base - 1), (8, base - 4), (12, base - 1), (17, base - 5), (21, base - 2)]
    p.line(pts, "o")
    p.line([(x, y + 1) for x, y in pts], "e")
    for x, y in pts[1:-1]:
        p.put(x, y - 1, "y")
    for cx in (5, 15, 19):
        p.poly([(cx - 2, base - 2), (cx + 2, base - 2), (cx, base - 10 + cx % 3)], "^")
        p.line([(cx - 1, base - 3), (cx, base - 9 + cx % 3)], ":")


def enc_den(p: Pen, rng: random.Random, w: int, h: int) -> None:
    base = h - 2
    p.ellipse((1, base - 14, w - 2, base + 4), "W")
    p.ellipse((4, base - 9, w - 5, base + 4), "w")
    p.ellipse((6, base - 7, w - 7, base + 4), "K")
    p.put(9, base - 3, "y")
    p.put(11, base - 3, "y")
    p.put(14, base - 2, "y")
    p.put(16, base - 2, "y")
    for x in (2, 5, 18, 21):
        p.line([(x, base - 8), (x - 1, base - 13)], "l")
        p.put(x - 1, base - 13, "z")
    p.rect(3, base, 6, base, "j")
    p.put(18, base, "J")


def enc_toll(p: Pen, rng: random.Random, w: int, h: int) -> None:
    base = h - 2
    for x in (3, 18):
        p.rect(x, base - 10, x + 2, base, "W")
        p.put(x, base - 10, "l")
    for x in range(5, 18):
        p.put(x, base - 7 + (1 if 8 <= x <= 14 else 0), "u" if x % 2 else "U")
    p.rect(9, base - 2, 13, base, "Q")
    p.put(10, base - 3, "o")
    p.put(11, base - 4, "O")
    p.put(12, base - 3, "y")
    p.put(11, base - 5, "y")


def enc_milestone(p: Pen, rng: random.Random, w: int, h: int) -> None:
    base = h - 2
    p.rect(13, base - 12, 18, base, "6")
    p.rect(17, base - 12, 18, base, "4")
    p.rect(14, base - 13, 17, base - 13, "6")
    p.line([(14, base - 9), (16, base - 9)], "3")
    p.line([(14, base - 6), (16, base - 6)], "3")
    # slumped rider with an arrow
    p.rect(7, base - 6, 12, base, "B")
    p.rect(8, base - 9, 11, base - 7, "t")
    p.put(9, base - 8, "K")
    p.line([(5, base - 6), (11, base - 3)], "L")
    p.put(4, base - 7, "E")
    p.rect(3, base - 1, 6, base, "W")
    p.line([(2, base + 1), (12, base + 1)], "e")


def enc_ruin(p: Pen, rng: random.Random, w: int, h: int) -> None:
    base = h - 2
    p.rect(2, base - 1, w - 3, base, "4")
    for i, (x, top) in enumerate(((3, 6), (8, 2), (13, 9), (18, 4))):
        p.rect(x, top, x + 2, base - 1, "6")
        p.line([(x + 2, top), (x + 2, base - 1)], "4")
        p.put(x, top, "7")
        if i % 2 == 0:
            p.rect(x - 1, top - 1, x + 3, top - 1, "5")
    p.line([(8, 4), (12, 4)], "7")
    p.put(10, 12, "h")


ENCOUNTER_DRAWERS = {
    "shrine": enc_shrine, "wagon": enc_wagon, "cart": lambda p, r, w, h: enc_wagon(p, r, w, h, True),
    "tent": enc_tent, "camp": lambda p, r, w, h: enc_tent(p, r, w, h, "R", "E"),
    "chapel": enc_chapel, "barrows": enc_barrows, "pit": enc_pit, "rift": enc_rift, "den": enc_den,
    "toll": enc_toll, "milestone": enc_milestone, "ruin": enc_ruin,
}


def struct_encounter(pal: Palette, rng: random.Random, size: tuple[int, int], look: str = "ruin") -> Image.Image:
    p = Pen(pal, *size)
    ENCOUNTER_DRAWERS[look](p, rng, size[0], size[1])
    return p.img


STRUCTURES = {"town_concord": struct_town_concord, "town_ashen": struct_town_ashen, "mine": struct_mine,
              "flag": struct_flag, "encounter": struct_encounter}


# --------------------------------------------------------------------- UI --

def ui_panel(pal: Palette, rng: random.Random, size: tuple[int, int]) -> Image.Image:
    """Dark wood planks inside an iron band with a tarnished-brass inner trim
    and angular iron corner brackets with a brass stud."""
    w, h = size
    p = Pen(pal, w, h, "w")
    for x in range(w):
        for y in range(h):
            plank = (x // 8) % 2
            ch = "w" if plank else "~"
            r = rng.random()
            if r < 0.07:
                ch = "W"
            elif r < 0.12:
                ch = "^"
            p.put(x, y, ch)
        if x % 8 == 0:
            p.line([(x, 0), (x, h - 1)], "^")
    # iron band
    for i, ch in enumerate(("K", "Q", "u", "Q", "q")):
        p.line([(i, i), (w - 1 - i, i)], ch)
        p.line([(i, h - 1 - i), (w - 1 - i, h - 1 - i)], "q" if ch == "u" else ch)
        p.line([(i, i), (i, h - 1 - i)], ch)
        p.line([(w - 1 - i, i), (w - 1 - i, h - 1 - i)], "q" if ch == "u" else ch)
    # brass trim
    p.line([(5, 5), (w - 6, 5)], "h")
    p.line([(5, 5), (5, h - 6)], "h")
    p.line([(w - 6, 6), (w - 6, h - 6)], "G")
    p.line([(6, h - 6), (w - 6, h - 6)], "G")
    # corner brackets
    for cx, cy, sx, sy in ((0, 0, 1, 1), (w - 1, 0, -1, 1), (0, h - 1, 1, -1), (w - 1, h - 1, -1, -1)):
        for i in range(9):
            for j in range(9 - i):
                if i + j > 6:
                    continue
                ch = "Q" if i + j < 6 else "q"
                if i == 0 or j == 0:
                    ch = "K"
                p.put(cx + sx * i, cy + sy * j, ch)
        p.put(cx + sx * 3, cy + sy * 3, "H")
        p.put(cx + sx * 4, cy + sy * 3, "h")
        p.put(cx + sx * 3, cy + sy * 4, "G")
        p.put(cx + sx * 4, cy + sy * 4, "g")
    return p.img


def _button(pal: Palette, size: tuple[int, int], face: str, face_hi: str, rim: str, rim_hi: str, pressed: bool) -> Image.Image:
    w, h = size
    p = Pen(pal, w, h, face)
    for y in range(h):
        for x in range(w):
            if (x * 7 + y * 3) % 11 == 0:
                p.put(x, y, face_hi)
    p.line([(0, 0), (w - 1, 0)], "K")
    p.line([(0, h - 1), (w - 1, h - 1)], "K")
    p.line([(0, 0), (0, h - 1)], "K")
    p.line([(w - 1, 0), (w - 1, h - 1)], "K")
    tl, br = (rim, rim_hi) if pressed else (rim_hi, rim)
    p.line([(1, 1), (w - 2, 1)], tl)
    p.line([(1, 1), (1, h - 2)], tl)
    p.line([(1, h - 2), (w - 2, h - 2)], br)
    p.line([(w - 2, 1), (w - 2, h - 2)], br)
    for x, y in ((2, 2), (w - 3, 2), (2, h - 3), (w - 3, h - 3)):
        p.put(x, y, rim_hi)
    return p.img


def ui_button(pal: Palette, rng: random.Random, size: tuple[int, int], state: str = "normal") -> Image.Image:
    if state == "hover":
        return _button(pal, size, "l", "L", "G", "H", False)
    if state == "pressed":
        return _button(pal, size, "w", "W", "g", "G", True)
    if state == "disabled":
        return _button(pal, size, "2", "3", "3", "4", False)
    return _button(pal, size, "W", "l", "g", "h", False)


def ui_slot(pal: Palette, rng: random.Random, size: tuple[int, int]) -> Image.Image:
    w, h = size
    p = Pen(pal, w, h, "^")
    speckle(p, rng, [("1", 0.2), ("~", 0.08)])
    p.line([(0, 0), (w - 1, 0)], "K")
    p.line([(0, 0), (0, h - 1)], "K")
    p.line([(0, h - 1), (w - 1, h - 1)], "K")
    p.line([(w - 1, 0), (w - 1, h - 1)], "K")
    p.line([(1, 1), (w - 2, 1)], "G")
    p.line([(1, 1), (1, h - 2)], "G")
    p.line([(1, h - 2), (w - 2, h - 2)], "h")
    p.line([(w - 2, 1), (w - 2, h - 2)], "h")
    p.line([(2, 2), (w - 3, 2)], "K")
    p.line([(2, 2), (2, h - 3)], "K")
    for x, y in ((1, 1), (w - 2, 1), (1, h - 2), (w - 2, h - 2)):
        p.put(x, y, "H")
    return p.img


def ui_divider(pal: Palette, rng: random.Random, size: tuple[int, int]) -> Image.Image:
    w, h = size
    p = Pen(pal, w, h)
    mid = h // 2
    p.line([(2, mid), (w - 3, mid)], "G")
    p.line([(2, mid - 1), (w - 3, mid - 1)], "h")
    c = w // 2
    p.poly([(c - 3, mid), (c, mid - 3), (c + 3, mid), (c, mid + 3)], "h")
    p.put(c, mid - 1, "H")
    p.put(c, mid, "e")
    return p.img


from .ui_art import cursor as ui_cursor

UI = {"panel": ui_panel, "button": ui_button, "slot": ui_slot, "divider": ui_divider, "cursor": ui_cursor}


def draw(kind: str, name: str, pal: Palette, seed: int, size: tuple[int, int], params: dict | None = None) -> Image.Image:
    rng = random.Random(seed)
    params = params or {}
    if kind == "deco":
        return DECOS[name](pal, rng, size)
    if kind == "structure":
        return STRUCTURES[name](pal, rng, size, **params)
    if kind == "ui":
        return UI[name](pal, rng, size, **params)
    raise KeyError(f"unknown procedural kind {kind}")
