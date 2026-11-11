"""Art coverage for creatures that have no sprite spec of their own.

* Upgrades (`upgrade_of` a creature with art) reuse the base sprite with the
  faction's upgrade recolour (assets/specs/factions.json) and a glint of trim.
* Anything else gets a placeholder: a dark, faceless silhouette chosen by
  role and rimmed in the faction accent, so the game always has a readable
  figure. Placeholders are listed by `pipeline.py validate` until real art
  (hand-drawn or generated) replaces them.
"""
from __future__ import annotations

import json
import random
from pathlib import Path

from PIL import Image

from .palette import Palette
from .procedural import Pen


def load_creatures(data_dir: Path) -> dict[str, dict]:
    """All creature definitions: data/creatures.json and data/creatures/*.json."""
    out: dict[str, dict] = {}
    single = data_dir / "creatures.json"
    files = ([single] if single.is_file() else []) + sorted((data_dir / "creatures").glob("*.json"))
    for f in files:
        doc = json.loads(f.read_text())
        out.update(doc.get("creatures", {}))
    return out


def faction_style(factions: dict, faction: str) -> dict:
    return factions.get(faction, factions["default"])


def recolour(img: Image.Image, pal: Palette, mapping: dict[str, str]) -> Image.Image:
    rgb_map = {pal.c(k): pal.c(v) for k, v in mapping.items()}
    out = img.copy()
    px = out.load()
    for y in range(out.height):
        for x in range(out.width):
            r, g, b, a = px[x, y]
            if a and (r, g, b) in rgb_map:
                px[x, y] = rgb_map[(r, g, b)] + (a,)
    return out


def upgrade_sprite(base: Image.Image, pal: Palette, style: dict) -> Image.Image:
    """Base sprite (before outline) recoloured, plus a trim glint along the
    top-left edge of the silhouette so upgrades read as 'finer' at a glance."""
    out = recolour(base, pal, style["upgrade"])
    px = out.load()
    glow = pal.c(style["glow"]) + (255,)
    w, h = out.size
    for x in range(w):
        for y in range(h):
            if px[x, y][3]:
                if (x * 7 + y) % 5 == 0:
                    px[x, y] = glow
                break
    return out


def placeholder(pal: Palette, role: str, style: dict, seed: int, size: tuple[int, int] = (64, 64)) -> Image.Image:
    w, h = size
    p = Pen(pal, w, h)
    rng = random.Random(seed)
    dark, mid, light = style["body"]
    base = h - 2
    cx = w // 2

    def figure(x: int, top: int, scale: float = 1.0, robe: bool = False) -> None:
        head = int(4 * scale)
        p.ellipse((x - head, top, x + head, top + head * 2), mid)
        sh = top + head * 2
        p.poly([(x - 7 * scale, sh + 2), (x + 7 * scale, sh + 2), (x + 6 * scale, sh + 20 * scale), (x - 6 * scale, sh + 20 * scale)], mid)
        if robe:
            p.poly([(x - 6 * scale, sh + 12 * scale), (x + 6 * scale, sh + 12 * scale), (x + 11 * scale, base), (x - 11 * scale, base)], dark)
        else:
            p.poly([(x - 6 * scale, sh + 19 * scale), (x - 1, sh + 19 * scale), (x - 3 * scale, base), (x - 7 * scale, base)], dark)
            p.poly([(x + 1, sh + 19 * scale), (x + 6 * scale, sh + 19 * scale), (x + 7 * scale, base), (x + 3 * scale, base)], dark)
        p.line([(x - head + 1, top + head), (x + head - 1, top + head)], dark)
        p.put(x + head - 2, top + head, style["glow"])

    if role == "cavalry":
        p.ellipse((cx - 20, base - 24, cx + 16, base - 10), mid)
        p.poly([(cx + 10, base - 22), (cx + 22, base - 34), (cx + 27, base - 30), (cx + 18, base - 16)], mid)
        for lx in (cx - 16, cx - 10, cx + 6, cx + 12):
            p.rect(lx, base - 12, lx + 2, base, dark)
        figure(cx - 2, base - 50, 0.8)
        p.line([(cx + 2, base - 34), (w - 3, base - 52)], light)
    elif role == "flyer":
        p.poly([(cx - 4, base - 30), (2, base - 50), (8, base - 36), (cx - 4, base - 20)], dark)
        p.poly([(cx + 4, base - 30), (w - 3, base - 52), (w - 9, base - 36), (cx + 4, base - 20)], dark)
        p.ellipse((cx - 9, base - 34, cx + 9, base - 12), mid)
        p.ellipse((cx + 4, base - 42, cx + 14, base - 30), mid)
        p.put(cx + 11, base - 37, style["glow"])
        p.line([(cx - 3, base - 12), (cx - 4, base)], dark)
        p.line([(cx + 3, base - 12), (cx + 4, base)], dark)
    elif role == "heavy":
        p.ellipse((cx - 22, base - 50, cx + 22, base - 14), mid)
        p.ellipse((cx - 6, base - 58, cx + 8, base - 44), mid)
        p.put(cx + 4, base - 52, style["glow"])
        p.rect(cx - 27, base - 44, cx - 19, base - 16, dark)
        p.rect(cx + 19, base - 44, cx + 27, base - 16, dark)
        p.rect(cx - 15, base - 16, cx - 5, base, dark)
        p.rect(cx + 5, base - 16, cx + 15, base, dark)
    else:
        figure(cx, base - 46, 1.0, robe=(role == "support"))
        if role == "ranged":
            p.line([(cx + 12, base - 44), (cx + 16, base - 30), (cx + 12, base - 16)], light)
            p.line([(cx + 12, base - 44), (cx + 12, base - 16)], light)
        elif role == "support":
            p.line([(cx + 12, base - 46), (cx + 12, base)], light)
            p.ellipse((cx + 9, base - 52, cx + 15, base - 46), style["glow"])
        else:
            p.line([(cx + 11, base - 54), (cx + 11, base)], light)
            p.put(cx + 11, base - 55, style["glow"])
    # faction rim light on the top-left edge of the silhouette
    px = p.img.load()
    rim = pal.c(style["rim"]) + (255,)
    for y in range(h):
        for x in range(w):
            if px[x, y][3] and (x == 0 or not px[x - 1, y][3] or y == 0 or not px[x, y - 1][3]):
                if rng.random() < 0.8:
                    px[x, y] = rim
    return p.img
