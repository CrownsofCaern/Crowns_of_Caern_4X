"""Post-processing for sprites, mainly for AI-generated sources:
background removal -> crop -> fit to target size -> palette -> outline."""
from __future__ import annotations

from collections import deque

import numpy as np
from PIL import Image

from .palette import Palette, RGB


def has_rembg() -> bool:
    try:
        import rembg  # noqa: F401
        return True
    except Exception:
        return False


def remove_background(img: Image.Image, method: str = "auto", tolerance: int = 48) -> Image.Image:
    """Makes the background transparent.

    'rembg' uses the rembg U^2-Net model (MIT; optional dependency). 'flood'
    flood-fills from the image border through pixels close to the dominant
    border colour, which is exact for flat backgrounds that generators are
    asked to produce. 'auto' keeps existing transparency, else uses rembg if
    installed, else flood.
    """
    img = img.convert("RGBA")
    a = np.array(img)
    if method == "auto":
        border_alpha = np.concatenate([a[0, :, 3], a[-1, :, 3], a[:, 0, 3], a[:, -1, 3]])
        if (border_alpha < 16).mean() > 0.9:
            return img
        method = "rembg" if has_rembg() else "flood"
    if method == "rembg":
        import rembg
        return rembg.remove(img).convert("RGBA")
    if method != "flood":
        raise ValueError(f"unknown background method {method}")
    return _flood_remove(a, tolerance)


def _flood_remove(a: np.ndarray, tolerance: int) -> Image.Image:
    h, w = a.shape[:2]
    border = np.concatenate([a[0, :, :3], a[-1, :, :3], a[:, 0, :3], a[:, -1, :3]]).astype(np.int32)
    bg = np.median(border, axis=0)
    dist = np.sqrt(((a[:, :, :3].astype(np.int32) - bg) ** 2).sum(axis=2))
    close = dist <= tolerance
    seen = np.zeros((h, w), dtype=bool)
    q: deque = deque()
    for x in range(w):
        for y in (0, h - 1):
            if close[y, x] and not seen[y, x]:
                seen[y, x] = True
                q.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if close[y, x] and not seen[y, x]:
                seen[y, x] = True
                q.append((y, x))
    while q:
        y, x = q.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and close[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True
                q.append((ny, nx))
    out = a.copy()
    out[seen, 3] = 0
    return Image.fromarray(out, "RGBA")


def crop_to_content(img: Image.Image, alpha_threshold: int = 128) -> Image.Image:
    a = np.array(img.convert("RGBA"))[:, :, 3]
    ys, xs = np.nonzero(a >= alpha_threshold)
    if len(xs) == 0:
        return img
    return img.crop((int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1))


def binarize_alpha(img: Image.Image, threshold: int = 128) -> Image.Image:
    a = np.array(img.convert("RGBA"))
    a[:, :, 3] = np.where(a[:, :, 3] >= threshold, 255, 0)
    a[a[:, :, 3] == 0, :3] = 0
    return Image.fromarray(a, "RGBA")


def fit(img: Image.Image, size: tuple[int, int], anchor: str = "bottom_center", margin: int = 1) -> Image.Image:
    """Scales `img` (keeping aspect) into `size` minus `margin`, then places it
    on a transparent canvas by anchor. Downscaling uses box filtering (the
    palette and alpha passes afterwards restore hard pixel edges); upscaling
    uses nearest neighbour."""
    w, h = size
    avail = (w - 2 * margin, h - 2 * margin)
    sw, sh = img.size
    k = min(avail[0] / sw, avail[1] / sh)
    nw, nh = max(1, round(sw * k)), max(1, round(sh * k))
    resample = Image.Resampling.BOX if k < 1 else Image.Resampling.NEAREST
    small = img.resize((nw, nh), resample)
    canvas = Image.new("RGBA", size, (0, 0, 0, 0))
    x = (w - nw) // 2
    y = h - margin - nh if anchor == "bottom_center" else (h - nh) // 2
    canvas.paste(small, (x, y))
    return canvas


def outline(img: Image.Image, color: RGB, weight: int = 1, diagonal: bool = False) -> Image.Image:
    """Adds an outline of `weight` pixels around every opaque region."""
    a = np.array(img.convert("RGBA"))
    for _ in range(weight):
        solid = a[:, :, 3] > 0
        grow = np.zeros_like(solid)
        shifts = [(1, 0), (-1, 0), (0, 1), (0, -1)]
        if diagonal:
            shifts += [(1, 1), (1, -1), (-1, 1), (-1, -1)]
        for dy, dx in shifts:
            grow |= np.roll(np.roll(solid, dy, axis=0), dx, axis=1) & _valid_shift(solid.shape, dy, dx)
        ring = grow & ~solid
        a[ring, :3] = color
        a[ring, 3] = 255
    return Image.fromarray(a, "RGBA")


def _valid_shift(shape, dy: int, dx: int) -> np.ndarray:
    # Mask out wrap-around rows/cols introduced by np.roll.
    m = np.ones(shape, dtype=bool)
    if dy > 0: m[:dy, :] = False
    if dy < 0: m[dy:, :] = False
    if dx > 0: m[:, :dx] = False
    if dx < 0: m[:, dx:] = False
    return m


def scale(img: Image.Image, k: int) -> Image.Image:
    if k == 1:
        return img
    return img.resize((img.width * k, img.height * k), Image.Resampling.NEAREST)


def shared_terrain_edges(images: list[Image.Image], band: int = 3) -> list[Image.Image]:
    """Give every variant identical opposite borders, including common corners.

    A small blend band reduces a hard boundary between the sampled border and
    the generated interior. Unlike independently wrapping each variant, this
    also makes different variants join without a mismatched outer pixel row.
    """
    pixels = np.stack([np.array(img.convert("RGBA")) for img in images]).astype(float)
    h, w = pixels.shape[1:3]
    band = min(band, h // 2, w // 2)
    vertical = pixels[:, :, [0, -1], :3].mean(axis=(0, 2))
    horizontal = pixels[:, [0, -1], :, :3].mean(axis=(0, 1))
    for offset in range(band):
        weight = (band - offset) / band
        for x in (offset, w - 1 - offset):
            pixels[:, :, x, :3] = pixels[:, :, x, :3] * (1 - weight) + vertical * weight
        for y in (offset, h - 1 - offset):
            pixels[:, y, :, :3] = pixels[:, y, :, :3] * (1 - weight) + horizontal * weight
    # Set final shared samples after blending, with one shared corner colour.
    corner = np.concatenate([vertical[[0, -1]], horizontal[[0, -1]]]).mean(axis=0)
    vertical[[0, -1]] = corner
    horizontal[[0, -1]] = corner
    pixels[:, :, 0, :3] = pixels[:, :, -1, :3] = vertical
    pixels[:, 0, :, :3] = pixels[:, -1, :, :3] = horizontal
    pixels[:, :, :, 3] = 255
    return [Image.fromarray(np.rint(a).clip(0, 255).astype("uint8"), "RGBA") for a in pixels]


def process_generated(raw: Image.Image, spec: dict, palette: Palette, bg_method: str = "auto") -> Image.Image:
    """Full chain for an AI-generated (or any external) image."""
    return finish(prepare_generated(raw, spec, palette, bg_method), spec, palette)


def prepare_generated(raw: Image.Image, spec: dict, palette: Palette, bg_method: str = "auto") -> Image.Image:
    """Generated image -> palette sprite at native size, before outline."""
    if spec.get("background") == "opaque":
        img = raw.convert("RGB").convert("RGBA").resize(tuple(spec["size"]), Image.Resampling.BOX)
        return img if spec.get("generated_palette") == "preserve" else palette.quantize(img)
    img = remove_background(raw, bg_method)
    img = crop_to_content(img)
    w, h = spec["size"]
    margin = int(spec.get("outline_weight", 1)) if spec.get("outline") else 0
    img = fit(img, (w, h), spec.get("anchor", "bottom_center"), margin)
    img = binarize_alpha(img)
    # Approved 128px sources already carry their material ramps. Keep those
    # colours rather than crushing them into the legacy pixel-grid palette.
    return img if spec.get("generated_palette") == "preserve" else palette.quantize(img)


def finish(img: Image.Image, spec: dict, palette: Palette) -> Image.Image:
    """Common tail for every sprite source: outline pass and export scale."""
    if spec.get("outline"):
        img = outline(img, palette.outline, int(spec.get("outline_weight", 1)))
    return scale(img, int(spec.get("export_scale", 1)))


def connected_terrain_field(source: Image.Image, size: tuple[int, int]) -> Image.Image:
    """Make a periodic ground field without a blurred strip at its edges.

    A periodic-plus-smooth decomposition spreads the edge mismatch across the
    whole image with a Poisson solve. Local detail stays sharp and the opposite
    edges meet with a normal pixel-to-pixel change instead of a blended band.
    """
    import numpy as np
    image = np.array(source.convert("RGB").resize(size, Image.Resampling.LANCZOS)).astype(float)
    h, w = image.shape[:2]
    boundary = np.zeros_like(image)
    boundary[0] = image[-1] - image[0]
    boundary[-1] = -boundary[0]
    boundary[:, 0] += image[:, -1] - image[:, 0]
    boundary[:, -1] -= image[:, -1] - image[:, 0]
    y, x = np.indices((h, w))
    denominator = 2 * np.cos(2 * np.pi * x / w) + 2 * np.cos(2 * np.pi * y / h) - 4
    denominator[0, 0] = 1
    correction = np.fft.ifft2(np.fft.fft2(boundary, axes=(0, 1)) / denominator[:, :, None], axes=(0, 1)).real
    return Image.fromarray(np.clip(image - correction, 0, 255).astype("uint8")).convert("RGBA")
