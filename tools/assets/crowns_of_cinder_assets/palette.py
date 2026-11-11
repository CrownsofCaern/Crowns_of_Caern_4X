"""Master palette: loading, colour lookup and quantisation."""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np
from PIL import Image

RGB = tuple[int, int, int]


def hex_to_rgb(h: str) -> RGB:
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))


class Palette:
    def __init__(self, data: dict):
        self.transparent: str = data.get("transparent", ".")
        self.outline_char: str = data.get("outline", "K")
        self.chars: dict[str, RGB] = {k: hex_to_rgb(v) for k, v in data["colors"].items()}
        if self.transparent in self.chars:
            raise ValueError("transparent char must not be a colour")
        self.ramps: dict[str, list[RGB]] = {}
        for name, chars in data.get("ramps", {}).items():
            for c in chars:
                if c not in self.chars:
                    raise ValueError(f"ramp {name} uses unknown colour char {c!r}")
            self.ramps[name] = [self.chars[c] for c in chars]
        self.rgb_list: list[RGB] = list(dict.fromkeys(self.chars.values()))
        self.rgb_set: set[RGB] = set(self.rgb_list)
        self._arr = np.array(self.rgb_list, dtype=np.int32)

    @classmethod
    def load(cls, path: Path) -> "Palette":
        return cls(json.loads(Path(path).read_text()))

    @property
    def outline(self) -> RGB:
        return self.chars[self.outline_char]

    def c(self, char: str) -> RGB:
        return self.chars[char]

    def ramp(self, name: str) -> list[RGB]:
        return self.ramps[name]

    def nearest(self, rgb: RGB) -> RGB:
        return tuple(int(v) for v in self._arr[self._nearest_idx(np.array([rgb]))[0]])

    def _nearest_idx(self, px: np.ndarray) -> np.ndarray:
        # Weighted RGB distance (cheap perceptual approximation).
        w = np.array([3, 4, 2], dtype=np.int64)
        d = ((px[:, None, :].astype(np.int64) - self._arr[None, :, :]) ** 2 * w).sum(axis=2)
        return d.argmin(axis=1)

    def quantize(self, img: Image.Image) -> Image.Image:
        """Snaps every visible pixel to the nearest palette colour (alpha kept)."""
        a = np.array(img.convert("RGBA"))
        flat = a.reshape(-1, 4)
        vis = flat[:, 3] > 0
        if vis.any():
            flat[vis, :3] = self._arr[self._nearest_idx(flat[vis, :3])]
        return Image.fromarray(flat.reshape(a.shape), "RGBA")

    def off_palette_pixels(self, img: Image.Image) -> int:
        a = np.array(img.convert("RGBA")).reshape(-1, 4)
        vis = a[a[:, 3] > 0][:, :3]
        if len(vis) == 0:
            return 0
        uniq, counts = np.unique(vis, axis=0, return_counts=True)
        return int(sum(n for u, n in zip(uniq, counts) if tuple(int(v) for v in u) not in self.rgb_set))
