"""Cut faction building sheets (3x3 concept sheets on transparency) into clean town layers.

The sheets in assets/source/concept-library-2026-11/buildings are painted art: this module only
cuts, cleans and names them. It never repaints. Cleaning removes the faint red halo the
generator left around each object (near-transparent background pixels and red-tinted edge
pixels) and loose specks that belong to no building.

A batch `layout.json` names the sheets and which cell (row-major, 0..8) becomes which building
id. `stage()` writes `assets/source/generated/town_<faction>_<id>.png`, which
`assets/specs/town_scenes.json` then references by hash, exactly like the Concord crops.
"""
from __future__ import annotations

import hashlib
import io
import json
from collections import deque
from pathlib import Path

import numpy as np

ALPHA_FLOOR = 48        # below this the pixel is generator halo, not paint
ALPHA_SOLID = 240       # the generator stores paint at 250-252: treat as opaque
MIN_COMPONENT = 400     # smaller islands are specks
EDGE_RED_MARGIN = 55    # red exceeds both green and blue by this much: halo colour
PAD = 4


def _components(mask: np.ndarray) -> tuple[np.ndarray, int]:
    """4-connected labels of a boolean mask (deterministic scan order)."""
    h, w = mask.shape
    labels = np.zeros((h, w), dtype=np.int32)
    count = 0
    ys, xs = np.nonzero(mask)
    for y0, x0 in zip(ys.tolist(), xs.tolist()):
        if labels[y0, x0]:
            continue
        count += 1
        labels[y0, x0] = count
        queue = deque([(y0, x0)])
        while queue:
            y, x = queue.popleft()
            for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not labels[ny, nx]:
                    labels[ny, nx] = count
                    queue.append((ny, nx))
    return labels, count


def _clean_edges(rgba: np.ndarray) -> np.ndarray:
    """Drop halo alpha and replace red-tinted edge colour with the nearest opaque paint."""
    out = rgba.copy()
    alpha = out[..., 3].astype(np.int32)
    out[alpha < ALPHA_FLOOR] = 0
    out[..., 3][alpha >= ALPHA_SOLID] = 255
    rgb = out[..., :3].astype(np.int32)
    alpha = out[..., 3].astype(np.int32)
    red = (rgb[..., 0] - np.maximum(rgb[..., 1], rgb[..., 2]) > EDGE_RED_MARGIN)
    # Halo lives only in partially transparent pixels; opaque red paint (banners, embers) stays.
    edge = (alpha > 0) & (alpha < 255) & red
    solid = alpha == 255
    # Fill edge colour from solid neighbours, growing outward a few rings.
    fixed = out.copy()
    todo = edge.copy()
    for _ in range(6):
        if not todo.any():
            break
        acc = np.zeros(rgb.shape, dtype=np.int64)
        n = np.zeros(alpha.shape, dtype=np.int64)
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if dy == 0 and dx == 0:
                    continue
                s = np.roll(np.roll(solid, dy, 0), dx, 1)
                c = np.roll(np.roll(fixed[..., :3].astype(np.int64), dy, 0), dx, 1)
                acc += c * s[..., None]
                n += s
        take = todo & (n > 0)
        fixed[..., :3][take] = (acc[take] // n[take][:, None]).astype(np.uint8)
        solid = solid | take
        todo = todo & ~take
    # Edge pixels with no paint nearby are halo: remove them.
    fixed[todo] = 0
    return fixed


def extract_cells(sheet: Path) -> list[np.ndarray]:
    """Nine cleaned, tightly cropped RGBA arrays, row-major."""
    from PIL import Image
    rgba = np.array(Image.open(sheet).convert("RGBA"))
    h, w = rgba.shape[:2]
    cleaned = _clean_edges(rgba)
    labels, count = _components(cleaned[..., 3] > 0)
    sizes = np.bincount(labels.ravel(), minlength=count + 1)
    cells: list[list[int]] = [[] for _ in range(9)]
    for label in range(1, count + 1):
        if sizes[label] < MIN_COMPONENT:
            continue
        ys, xs = np.nonzero(labels == label)
        cy, cx = float(ys.mean()), float(xs.mean())
        cell = min(int(cy * 3 / h), 2) * 3 + min(int(cx * 3 / w), 2)
        cells[cell].append(label)
    result = []
    for members in cells:
        if not members:
            raise ValueError(f"{sheet.name}: empty cell")
        keep = np.isin(labels, members)
        layer = np.where(keep[..., None], cleaned, 0).astype(np.uint8)
        ys, xs = np.nonzero(keep)
        y0, y1 = max(int(ys.min()) - PAD, 0), min(int(ys.max()) + 1 + PAD, h)
        x0, x1 = max(int(xs.min()) - PAD, 0), min(int(xs.max()) + 1 + PAD, w)
        result.append(layer[y0:y1, x0:x1])
    return result


def _png(array: np.ndarray) -> bytes:
    from PIL import Image
    buffer = io.BytesIO()
    Image.fromarray(array, "RGBA").save(buffer, format="PNG", optimize=True)
    return buffer.getvalue()


def stage(root: Path, batch: Path) -> dict[str, str]:
    """Write every building of a batch layout to assets/source/generated; returns id -> sha256."""
    layout = json.loads((batch / "layout.json").read_text())
    faction = layout["faction"]
    written: dict[str, str] = {}
    for sheet in layout["sheets"]:
        path = root / sheet["source"]
        if hashlib.sha256(path.read_bytes()).hexdigest() != sheet["sha256"]:
            raise ValueError(f"{sheet['source']}: source sheet changed")
        cells = extract_cells(path)
        for index, bid in enumerate(sheet["cells"]):
            if not bid:
                continue
            data = _png(cells[index])
            destination = root / "assets/source/generated" / f"town_{faction}_{bid}.png"
            destination.write_bytes(data)
            written[bid] = hashlib.sha256(data).hexdigest()
    return written
