"""Small, phase-continuous terrain-pair edge strips for the adventure map."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image
from . import postprocess


def periodic_strip(source: Image.Image, width: int, height: int) -> Image.Image:
    """Wrap horizontally by spreading the edge difference across the strip."""
    image = source.convert("RGBA")
    alpha = image.getchannel("A").point(lambda a: 255 if a >= 96 else 0)
    bounds = alpha.getbbox()
    if not bounds:
        raise ValueError("Terrain edge source has no visible pixels")
    image = image.crop(bounds).resize((width, height), Image.Resampling.LANCZOS)
    pixels = np.asarray(image, dtype=float)
    boundary = np.zeros_like(pixels)
    boundary[:, 0] = pixels[:, -1] - pixels[:, 0]
    boundary[:, -1] = -boundary[:, 0]
    denominator = 2 * np.cos(2 * np.pi * np.arange(width) / width) - 2
    denominator[0] = 1
    correction = np.fft.ifft(np.fft.fft(boundary, axis=1) / denominator[None, :, None], axis=1).real
    pixels = np.clip(pixels - correction, 0, 255).astype("uint8")
    # Keep transparent edges transparent; suppress weak generation halos.
    pixels[:, :, 3] = np.where(pixels[:, :, 3] < 32, 0, pixels[:, :, 3])
    return Image.fromarray(pixels, "RGBA")


def build(root: Path, spec: dict, tile_size: int) -> tuple[Image.Image, dict]:
    # A small number of phases on each axis keeps neighboring tiles continuous
    # without allocating a texture for every possible world coordinate.
    period = int(spec["period"])
    width = tile_size * period
    names = sorted(spec["types"])
    atlas = Image.new("RGBA", (tile_size * len(names) * period * period, tile_size * 256))
    records = {}
    terrain_spec = json.loads((root / "assets/specs/terrain.json").read_text())
    fields = terrain_spec["connected_fields"]
    fw, fh = fields["cells"]
    fills = {}
    yy, xx = np.indices((tile_size, tile_size))
    neighbors = ((1, 0, -1), (2, 1, -1), (4, 1, 0), (8, 1, 1),
                 (16, 0, 1), (32, -1, 1), (64, -1, 0), (128, -1, -1))
    distances = np.stack([np.hypot(xx - (dx * tile_size + tile_size / 2),
                                   yy - (dy * tile_size + tile_size / 2)) for _, dx, dy in neighbors])
    for index, name in enumerate(names):
        entry = spec["types"][name]
        source = root / entry["source"]
        if hashlib.sha256(source.read_bytes()).hexdigest() != entry["sha256"]:
            raise ValueError(f"{name}: terrain edge source changed")
        with Image.open(source) as raw:
            strip = periodic_strip(raw, width, int(spec["strip_height"]))
        if len(entry["neighbors"]) != 1:
            raise ValueError(f"{name}: each crisp contour needs exactly one neighboring terrain")
        neighbor = entry["neighbors"][0]
        if neighbor not in fills:
            field_spec = fields["terrains"][neighbor]
            field_source = root / field_spec["source"]
            if hashlib.sha256(field_source.read_bytes()).hexdigest() != field_spec["sha256"]:
                raise ValueError(f"{neighbor}: connected terrain source changed")
            with Image.open(field_source) as raw:
                fills[neighbor] = np.asarray(postprocess.connected_terrain_field(raw, (fw * tile_size, fh * tile_size)))
        pixels = np.asarray(strip)
        records[name] = {"base": entry["base"], "neighbors": entry["neighbors"], "column": index * period * period}
        for mask in range(1, 256):
            active = np.array([bool(mask & bit) for bit, _, _ in neighbors])
            candidates = np.where(active[:, None, None], distances, 1e6)
            nearest = np.argmin(candidates, axis=0)
            closest = np.min(candidates, axis=0)
            # Smoothly union adjacent water/land cells so a long coastline does
            # not become one identical circular scallop per map tile.
            distance = closest - 12.0 * np.log(np.exp(-(candidates - closest) / 12.0).sum(axis=0))
            # Horizontal boundaries use the x phase; vertical ones use y.
            horizontal = np.isin(nearest, [0, 1, 3, 4, 5, 7])
            for py in range(period):
                for px in range(period):
                    along = np.where(horizontal, (xx + px * tile_size) % width, (yy + py * tile_size) % width)
                    wave = int(spec["wave_amplitude"]) * np.sin(2 * np.pi * along / width)
                    delta = distance - (30.0 + wave)
                    band = np.clip(1.0 - np.abs(delta) / 7.0, 0.0, 1.0)
                    band = band * band * (3.0 - 2.0 * band)
                    sample_y = np.clip(np.rint(delta + strip.height / 2), 0, strip.height - 1).astype(int)
                    edge = pixels[sample_y, along].copy()
                    edge_alpha = edge[:, :, 3].astype(float) * band * 0.85 / 255.0
                    fill = fills[neighbor][py * tile_size:(py + 1) * tile_size,
                                           px * tile_size:(px + 1) * tile_size]
                    inside = delta <= 0
                    out = edge.copy()
                    out[:, :, :3] = np.where(inside[:, :, None],
                        fill[:, :, :3] * (1.0 - edge_alpha[:, :, None]) + edge[:, :, :3] * edge_alpha[:, :, None],
                        edge[:, :, :3]).astype("uint8")
                    out[:, :, 3] = np.where(inside, 255, edge_alpha * 255).astype("uint8")
                    out[out[:, :, 3] == 0, :3] = 0
                    col = index * period * period + py * period + px
                    atlas.paste(Image.fromarray(out, "RGBA"), (col * tile_size, mask * tile_size))
    return atlas, {"cell": [tile_size, tile_size], "period": period, "types": records}
