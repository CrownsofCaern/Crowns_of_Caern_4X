"""Deterministic shelf packer for sprite atlases."""
from __future__ import annotations

from PIL import Image


def pack(images: dict[str, Image.Image], max_width: int = 512, padding: int = 1) -> tuple[Image.Image, dict[str, list[int]]]:
    """Packs images (tallest first, then by id) into rows. Returns the atlas and
    id -> [x, y, w, h]."""
    order = sorted(images, key=lambda k: (-images[k].height, -images[k].width, k))
    widest = max((images[k].width for k in order), default=1) + 2 * padding
    max_width = max(max_width, widest)
    rects: dict[str, list[int]] = {}
    x = y = padding
    row_h = 0
    for k in order:
        im = images[k]
        if x + im.width + padding > max_width:
            x = padding
            y += row_h + padding
            row_h = 0
        rects[k] = [x, y, im.width, im.height]
        x += im.width + padding
        row_h = max(row_h, im.height)
    height = y + row_h + padding
    width = max((r[0] + r[2] for r in rects.values()), default=1) + padding
    atlas = Image.new("RGBA", (width, max(1, height)), (0, 0, 0, 0))
    for k, r in rects.items():
        atlas.paste(images[k], (r[0], r[1]))
    return atlas, {k: rects[k] for k in sorted(rects)}
