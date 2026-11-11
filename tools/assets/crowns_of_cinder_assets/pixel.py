"""Hand-authored pixel sprites: a text grid where each character is a palette
key (see assets/specs/palette.json) and '.' is transparent."""
from __future__ import annotations

from pathlib import Path

from PIL import Image

from .palette import Palette


class PixelFormatError(ValueError):
    pass


def parse(text: str, palette: Palette, size: tuple[int, int], name: str = "?") -> Image.Image:
    w, h = size
    lines = [ln.rstrip("\n") for ln in text.splitlines()]
    while lines and lines[-1].strip() == "":
        lines.pop()
    if len(lines) > h:
        raise PixelFormatError(f"{name}: {len(lines)} rows, spec allows {h}")
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    for y, line in enumerate(lines):
        line = line.rstrip()
        if len(line) > w:
            raise PixelFormatError(f"{name}: row {y} has {len(line)} columns, spec allows {w}")
        for x, ch in enumerate(line):
            if ch == palette.transparent or ch == " ":
                continue
            if ch not in palette.chars:
                raise PixelFormatError(f"{name}: unknown palette char {ch!r} at {x},{y}")
            px[x, y] = palette.chars[ch] + (255,)
    return img


def load(path: Path, palette: Palette, size: tuple[int, int]) -> Image.Image:
    return parse(Path(path).read_text(), palette, size, str(path))


def mirror_text(text: str, width: int) -> str:
    """Helper for authoring: horizontally mirrored grid."""
    return "\n".join(ln.ljust(width, ".")[::-1] for ln in text.splitlines())
