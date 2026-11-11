"""Builds every asset from assets/specs into assets/build (per-sprite PNGs,
for review), assets/atlases (what the game loads) and assets/manifest.json."""
from __future__ import annotations

import json
import zlib
from pathlib import Path

from PIL import Image, ImageDraw

from . import atlas, creatures_auto, pixel, postprocess, procedural, specs
from .palette import Palette

MANIFEST_VERSION = 1


def seed_of(*parts: object) -> int:
    return zlib.crc32(":".join(str(p) for p in parts).encode()) & 0x7FFFFFFF


class Paths:
    def __init__(self, root: Path, out_root: Path | None = None):
        self.root = Path(root)
        out = Path(out_root) if out_root else self.root
        self.specs = self.root / "assets" / "specs"
        self.generated = self.root / "assets" / "source" / "generated"
        self.data = self.root / "data"
        self.build = out / "assets" / "build"
        self.atlases = out / "assets" / "atlases"
        self.manifest = out / "assets" / "manifest.json"


def res_path(p: Path, root: Path) -> str:
    return "res://" + p.relative_to(root).as_posix()


# ------------------------------------------------------------------ sprites --

def render_source(spec: dict, pal: Palette, paths: Paths, use_generated: bool = True) -> tuple[Image.Image, str]:
    """The sprite before outline/export scale, and its source label."""
    raw = paths.generated / f"{spec['id']}.png"
    if use_generated and spec.get("generate", True) and raw.is_file():
        return postprocess.prepare_generated(Image.open(raw), spec, pal), "generated"
    src = spec["source"]
    size = tuple(spec["size"])
    if src["kind"] == "pixel":
        return pixel.load(paths.specs / src["file"], pal, size), "pixel"
    return procedural.draw(src["drawer"], src["name"], pal, seed_of(spec["id"]), size, src.get("params")), "procedural"


def render_sprite(spec: dict, pal: Palette, paths: Paths, use_generated: bool = True) -> tuple[Image.Image, str]:
    """Returns (final image, source label)."""
    img, label = render_source(spec, pal, paths, use_generated)
    return postprocess.finish(img, spec, pal), label


def auto_creature_specs(sprite_specs: list[dict], paths: Paths) -> list[dict]:
    """Specs for creatures in data/ that have no sprite spec: upgrades of a
    creature with art (recolour, same size) or role placeholders (64 px).
    Deterministic order."""
    by_id = {s["id"]: s for s in sprite_specs}
    defaults = json.loads((paths.specs / "creatures.json").read_text())["defaults"]
    creatures = creatures_auto.load_creatures(paths.data)

    def art_base(cid: str, depth: int = 0) -> dict | None:
        """The drawn spec an upgrade chain ends in, if any."""
        if f"creature_{cid}" in by_id:
            return by_id[f"creature_{cid}"]
        up = creatures.get(cid, {}).get("upgrade_of", "")
        return art_base(up, depth + 1) if up and depth < 4 else None

    out = []
    for cid in sorted(creatures):
        sid = f"creature_{cid}"
        if sid in by_id:
            continue
        c = creatures[cid]
        spec = dict(defaults)
        spec.update({"id": sid, "data": {"type": "creature", "id": cid}, "_file": "(auto)",
                     "faction": c.get("faction", ""), "role": c.get("role", "infantry"),
                     "upgrade_of": c.get("upgrade_of", ""), "prompt": c.get("desc", c.get("name", cid))})
        base = art_base(spec["upgrade_of"]) if spec["upgrade_of"] else None
        if base is not None:
            spec.update({"_kind": "upgrade", "size": list(base["size"]), "map_scale": base.get("map_scale", 1)})
        else:
            spec.update({"_kind": "placeholder", "size": [64, 64], "map_scale": 1})
        out.append(spec)
    return out


def anchor_px(spec: dict) -> list[int]:
    w, h = spec["size"]
    return [w // 2, h - 1] if spec.get("anchor") == "bottom_center" else [w // 2, h // 2]


# ------------------------------------------------------------------ terrain --

def deco_variant(drawings: list[Image.Image], v: int) -> Image.Image:
    """Variant v of a decoration: drawing v % n, mirrored on odd passes, and a
    slight shade shift once mirrored copies run out (2 drawings -> 4 distinct, ...)."""
    from PIL import ImageOps
    n = len(drawings)
    img = drawings[v % n]
    rnd = v // n
    if rnd % 2 == 1:
        img = ImageOps.mirror(img)
    shift = rnd // 2
    if shift:
        import numpy as np
        a = np.array(img.convert("RGBA")).astype(np.float32)
        f = 1.0 + (0.07 if shift % 2 else -0.07) * ((shift + 1) // 2)
        warm = np.array([1.0 + 0.03 * shift, 1.0, 1.0 - 0.03 * shift])
        a[..., :3] = np.clip(a[..., :3] * f * warm, 0, 255)
        img = Image.fromarray(a.astype(np.uint8), "RGBA")
    return img


def recolor_deco(img: Image.Image, recipe: dict) -> Image.Image:
    """Recolours a decoration drawing (see terrain.json deco_derived):
    hue (degrees), saturation and value factors, a tint colour mixed by
    tint_amount, and frost (whitens the upward-lit, brighter pixels)."""
    import colorsys
    import numpy as np
    a = np.array(img.convert("RGBA")).astype(np.float32) / 255.0
    rgb = a[..., :3]
    mask = a[..., 3] > 0
    hsv = np.zeros_like(rgb)
    flat = rgb[mask]
    conv = np.array([colorsys.rgb_to_hsv(*px) for px in flat]) if len(flat) else np.zeros((0, 3))
    if len(conv):
        conv[:, 0] = (conv[:, 0] + float(recipe.get("hue", 0.0)) / 360.0) % 1.0
        conv[:, 1] = np.clip(conv[:, 1] * float(recipe.get("saturation", 1.0)), 0, 1)
        conv[:, 2] = np.clip(conv[:, 2] * float(recipe.get("value", 1.0)), 0, 1)
        back = np.array([colorsys.hsv_to_rgb(*px) for px in conv])
        if "tint" in recipe:
            t = recipe["tint"].lstrip("#")
            tint = np.array([int(t[i:i + 2], 16) / 255.0 for i in (0, 2, 4)])
            k = float(recipe.get("tint_amount", 0.3))
            back = back * (1 - k) + tint * k * (0.4 + 0.6 * back.mean(axis=1, keepdims=True))
        frost = float(recipe.get("frost", 0.0))
        if frost > 0:
            lum = back.mean(axis=1, keepdims=True)
            ys = np.nonzero(mask)[0].astype(np.float32)
            top = 1.0 - (ys - ys.min()) / max(1.0, ys.max() - ys.min())
            k = np.clip((lum - 0.25) * 2.0, 0, 1) * frost * (0.5 + 0.5 * top[:, None])
            back = back * (1 - k) + np.array([0.9, 0.93, 0.97]) * k
        rgb[mask] = np.clip(back, 0, 1)
    a[..., :3] = rgb
    return Image.fromarray((a * 255).round().astype(np.uint8), "RGBA")


def build_terrain(tspec: dict, pal: Palette, deco_dir: Path | None = None,
                  tile_dir: Path | None = None, generated_dir: Path | None = None) -> tuple[Image.Image, Image.Image, dict]:
    """tile_dir/<ground>_<v>.txt, road_<mask>.txt and bridge_<mask>.txt are hand-drawn grids that win over
    the procedural drawers (kept as a fallback for a missing file)."""
    t = int(tspec["tile_size"])

    def hand(name: str, fallback):
        src = tile_dir / f"{name}.txt" if tile_dir else None
        if src is not None and src.is_file():
            return pixel.load(src, pal, (t, t))
        return fallback()

    nv = int(tspec["variants"])
    masks = procedural.all_transition_masks()
    order = sorted(tspec["terrains"], key=lambda k: tspec["terrains"][k]["priority"])
    field_spec = tspec.get("connected_fields", {}) if generated_dir else {}
    fw, fh = field_spec.get("cells", [0, 0])
    transition_variants = int(tspec.get("transition_variants", 1))
    field_column = nv + len(masks) * transition_variants
    detail_variants = int(tspec.get("detail_variants", 0))
    detail_column = field_column + fw * fh
    cols = max(detail_column + detail_variants, (len(masks) + 1) * 4, 32)
    rows = len(order) + 12
    sheet = Image.new("RGBA", (cols * t, rows * t), (0, 0, 0, 0))
    info: dict = {"terrains": {}}

    def paste(img: Image.Image, col: int, row: int) -> None:
        sheet.paste(img, (col * t, row * t))

    for row, tid in enumerate(order):
        ts = tspec["terrains"][tid]
        grounds = [hand(f"{ts['ground']}_{v}", lambda v=v: procedural.ground_tile(
            pal, ts["ground"], ts["base"], seed_of(tid, v), seed_of(tid, "field"))) for v in range(nv)]
        raw = generated_dir / f"terrain_{tid}.png" if generated_dir else None
        variants = sorted(generated_dir.glob(f"terrain_{tid}_[0-9].png")) if generated_dir else []
        if variants:
            grounds = [Image.open(variants[v % len(variants)]).convert("RGBA").resize((t, t), Image.Resampling.BOX)
                       for v in range(nv)]
        elif raw is not None and raw.is_file():
            import numpy as np
            texture = Image.open(raw).convert("RGB").resize((t, t), Image.Resampling.BOX)
            grounds = []
            for v in range(nv):
                pixels = np.roll(np.roll(np.array(texture), v * 11, axis=0), v * 7, axis=1)
                # Shared opposite edge samples make each native tile periodic.
                edge = ((pixels[:, 0].astype(int) + pixels[:, -1].astype(int)) // 2).astype("uint8")
                pixels[:, 0] = pixels[:, -1] = edge
                edge = ((pixels[0].astype(int) + pixels[-1].astype(int)) // 2).astype("uint8")
                pixels[0] = pixels[-1] = edge
                grounds.append(Image.fromarray(pixels).convert("RGBA"))
        if variants or (raw is not None and raw.is_file()):
            grounds = postprocess.shared_terrain_edges(grounds)
        for v, g in enumerate(grounds):
            paste(g, v, row)
        info["terrains"][tid] = {"row": row, "priority": ts["priority"], "deco": ts.get("deco", {})}
        field = field_spec.get("terrains", {}).get(tid)
        transition_grounds = grounds
        if field:
            import hashlib
            from .postprocess import connected_terrain_field
            source = generated_dir.parents[2] / field["source"]
            if hashlib.sha256(source.read_bytes()).hexdigest() != field["sha256"]:
                raise ValueError(f"{tid}: connected terrain source changed")
            image = connected_terrain_field(Image.open(source), (fw * t, fh * t))
            # Match the transition material to the actual connected field, not
            # the older stand-alone ground texture.
            transition_grounds = postprocess.shared_terrain_edges([
                image.crop(((v * 3 % fw) * t, (v * 5 % fh) * t,
                            (v * 3 % fw + 1) * t, (v * 5 % fh + 1) * t))
                for v in range(transition_variants)])
            for fy in range(fh):
                for fx in range(fw):
                    paste(image.crop((fx*t, fy*t, (fx+1)*t, (fy+1)*t)), field_column + fy * fw + fx, row)
            info["terrains"][tid]["field"] = {"column": field_column, "cells": [fw, fh]}
        for v in range(transition_variants):
            offs = procedural.periodic_offsets(_rng(tid, "fringe", v), lo=-5, hi=5)
            for i, m in enumerate(masks):
                depth = min(t // 2, int(ts["fringe"]) + int(tspec.get("transition_expansion", 0)))
                source = transition_grounds[(m + v) % len(transition_grounds)]
                paste(procedural.transition_tile(pal, source, m, depth, offs, ts.get("rim")), nv + v * len(masks) + i, row)
        for v in range(detail_variants):
            paste(procedural.ground_detail_tile(tid, seed_of(tid, "detail", v)), detail_column + v, row)

    fog_row = len(order)
    fs = tspec["fog"]
    shrouds = [hand(f"{fs['ground']}_{v}", lambda v=v: procedural.ground_tile(
        pal, fs["ground"], fs["base"], seed_of("fog", v), seed_of("fog", "field"))) for v in range(nv)]
    for v, g in enumerate(shrouds):
        paste(g, v, fog_row)
    offs = procedural.periodic_offsets(_rng("fog", "fringe"))
    for i, m in enumerate(masks):
        paste(procedural.fog_fringe_tile(pal, shrouds[m % nv], m, int(fs["fringe"]), offs), nv + i, fog_row)
    fog_source = generated_dir / "fog_field.png" if generated_dir else None
    fog_field = None
    if fog_source is not None and fog_source.is_file() and fw and fh:
        fog_field = postprocess.connected_terrain_field(Image.open(fog_source), (fw*t, fh*t))
        for fy in range(fh):
            for fx in range(fw):
                paste(fog_field.crop((fx*t, fy*t, (fx+1)*t, (fy+1)*t)), field_column + fy*fw + fx, fog_row)
    road_row = fog_row + 1
    def weather_bridge(image: Image.Image) -> Image.Image:
        # Keep the authored connection silhouette and plank details while
        # replacing the saturated pixel palette with weathered timber grain.
        import numpy as np
        pixels = np.asarray(image.convert("RGBA")).copy()
        yy, xx = np.indices(pixels.shape[:2])
        grain = (np.sin(xx * 1.73 + np.sin(yy * 0.61)) +
                 np.cos(yy * 1.31 + np.sin(xx * 0.43))) * 3.0
        luminance = (pixels[:, :, 0] * 0.30 + pixels[:, :, 1] * 0.59 +
                     pixels[:, :, 2] * 0.11)
        shade = np.clip((luminance - 65) * 0.60 + grain, -25, 35)
        for channel, base in enumerate((83, 70, 57)):
            pixels[:, :, channel] = np.clip(base + shade, 0, 255).astype("uint8")
        return Image.fromarray(pixels)

    for m in range(16):
        paste(hand(f"road_{m}", lambda m=m: procedural.road_tile(pal, m, seed_of("road", m))), m, road_row)
        bridge = hand(f"bridge_{m}", lambda m=m: procedural.road_tile(pal, m, seed_of("bridge", m), bridge=True))
        paste(weather_bridge(bridge), 16 + m, road_row)
    barrier_row = road_row + 1
    barrier_fields = {}
    # Match strip ends so repeated two-cell runs join smoothly.
    import numpy as np
    def periodic_strip(image, axis):
        pixels = np.array(image).astype(float)
        strip = np.swapaxes(pixels, 0, axis)
        edge = (strip[0].copy() + strip[-1].copy()) / 2
        for i in range(4):
            weight = (1 - i / 4) ** 2
            strip[i] = strip[i] * (1 - weight) + edge * weight
            strip[-1-i] = strip[-1-i] * (1 - weight) + edge * weight
        return Image.fromarray(np.clip(pixels, 0, 255).astype("uint8"))
    # The fortress uses one triangular master: its bottom and left sides,
    # hypotenuse, and corner tower share the same stones and proportions.
    road_fields = {}
    for triangle_name, triangle_row in (("wall", barrier_row), ("lava", barrier_row + 1),
                                        ("jungle", barrier_row + 2), ("chasm", barrier_row + 3),
                                        ("sandstone", barrier_row + 4), ("ice", barrier_row + 5),
                                        ("bones", barrier_row + 6), ("road_stone", barrier_row + 7),
                                        ("road_dirt", barrier_row + 8), ("road_desert", barrier_row + 9)):
        filename = f"{triangle_name}_triangle.png" if triangle_name.startswith("road_") else f"barrier_{triangle_name}_triangle.png"
        triangle = generated_dir / filename if generated_dir else None
        if triangle is not None and triangle.is_file():
            from PIL import ImageOps, ImageChops
            master = Image.open(triangle).convert("RGBA")
            if triangle_name.startswith("road_"):
                from PIL import ImageEnhance
                brightness = {"road_dirt": .78, "road_stone": 1.45, "road_desert": .66}[triangle_name]
                master = ImageEnhance.Brightness(master).enhance(brightness)
            w, h = master.size
            def region(box):
                return master.crop(tuple(round(v * (w if i % 2 == 0 else h)) for i, v in enumerate(box)))
            width = (22 if triangle_name.startswith("road_") else 15) * t // 40
            hs = region((.144, .845, .861, 1.0)).resize((2*t, width), Image.Resampling.LANCZOS)
            vs = region((0, .135, .120, .845)).resize((width, 2*t), Image.Resampling.LANCZOS)
            hs, vs = periodic_strip(hs, 1), periodic_strip(vs, 0)
            def join_middle(image, axis):
                pixels = np.array(image).astype(float)
                strip = np.swapaxes(pixels, 0, axis)
                edge = (strip[t-1].copy() + strip[t].copy()) / 2
                for i in range(4):
                    weight = (1 - i / 4) ** 2
                    strip[t-1-i] = strip[t-1-i] * (1-weight) + edge * weight
                    strip[t+i] = strip[t+i] * (1-weight) + edge * weight
                return Image.fromarray(np.clip(pixels, 0, 255).astype("uint8"))
            hs, vs = join_middle(hs, 1), join_middle(vs, 0)
            tower = region((0, .830, .145, 1.0)).resize((t//2, t//2), Image.Resampling.LANCZOS)
            diag = region((.279, .279, .638, .638)).resize((t, t), Image.Resampling.LANCZOS)
            tile_masks = [0] + masks
            for variant in range(4):
                for index, mask in enumerate(tile_masks):
                    piece = Image.new("RGBA", (t, t))
                    hx, vy = variant % 2, variant // 2
                    hpart = hs.crop((hx*t, 0, (hx+1)*t, width))
                    vpart = vs.crop((0, vy*t, width, (vy+1)*t))
                    horizontal = Image.new("RGBA", (t, t))
                    horizontal.alpha_composite(hpart, (0, (t-width)//2))
                    vertical = Image.new("RGBA", (t, t))
                    vertical.alpha_composite(vpart, ((t-width)//2, 0))
                    # Clip to the connected half, leaving all edge joins aligned.
                    for bit, box in ((4, (t//2, 0, t, t)), (64, (0, 0, t//2, t))):
                        if mask & bit:
                            part = horizontal.crop(box)
                            piece.alpha_composite(part, box[:2])
                    for bit, box in ((1, (0, 0, t, t//2)), (16, (0, t//2, t, t))):
                        if mask & bit:
                            part = vertical.crop(box)
                            piece.alpha_composite(part, box[:2])
                    for bit, polygon, art in ((128, [(0, 0), (t, 0), (0, t)], diag),
                                              (8, [(t, t), (t, 0), (0, t)], diag),
                                              (2, [(0, 0), (t, 0), (t, t)], ImageOps.mirror(diag)),
                                              (32, [(0, 0), (0, t), (t, t)], ImageOps.mirror(diag))):
                        if mask & bit:
                            clip = Image.new("L", (t, t))
                            ImageDraw.Draw(clip).polygon(polygon, fill=255)
                            part = art.copy()
                            part.putalpha(ImageChops.multiply(art.getchannel("A"), clip))
                            piece.alpha_composite(part)
                    arms = sum(bool(mask & bit) for bit in (1, 2, 4, 8, 16, 32, 64, 128))
                    straight = mask in (1 | 16, 4 | 64, 2 | 32, 8 | 128)
                    if arms != 2 or not straight:
                        piece.alpha_composite(tower, ((t-t//2)//2, (t-t//2)//2))
                    paste(piece, index + variant * len(tile_masks), triangle_row)
            entry = {"row": triangle_row, "column": 0, "masks": tile_masks, "variants": 4}
            if triangle_name.startswith("road_"):
                road_fields[triangle_name.removeprefix("road_")] = entry
            else:
                barrier_fields[triangle_name] = entry
    info.update({
        "tile_size": t, "display_scale": int(tspec["display_scale"]), "variants": nv,
        "transition_column": nv, "transition_masks": masks, "transition_variants": transition_variants,
        "detail_column": detail_column, "detail_variants": detail_variants,
        "barriers": barrier_fields,
        "fog": {"row": fog_row, **({"field": {"column": field_column, "cells": [fw, fh]}} if fog_field else {})}, "roads": {"row": road_row, "road_column": 0, "bridge_column": 16,
                                            "bridge_over": tspec["roads"]["bridge_over"], "styles": road_fields},
        "order": order,
    })

    # decorations: one row per kind, outlined sprites in uniform cells. A hand-drawn
    # grid in deco_dir/<kind>_<variant>.txt wins over the procedural drawer; a
    # generated drawing (generated_dir/deco_<kind>_<n>.png) wins over both.
    # Variants beyond the distinct drawings reuse them mirrored and, once those
    # run out, with a slight shade shift (deco_variant_rules), so no two cells of
    # a row are identical. deco_derived adds kinds recoloured from another kind's
    # drawings (frost, char, autumn...), keeping the same painted style.
    dw, dh = tspec["deco_size"]
    dv = int(tspec["deco_variants"])
    derived = {k: v for k, v in tspec.get("deco_derived", {}).items() if not k.startswith("_")}
    kinds = sorted({k for ts in tspec["terrains"].values() for k in ts.get("deco", {}).get("kinds", [])} | set(derived))
    deco = Image.new("RGBA", (dw * dv, dh * max(1, len(kinds))), (0, 0, 0, 0))
    drawn_per_kind = int(tspec.get("deco_drawings", 5))

    def drawings(kind: str) -> list[Image.Image]:
        out = []
        raws = []
        if generated_dir is not None:
            raws = [generated_dir / f"deco_{kind}_{n}.png" for n in range(drawn_per_kind)]
            raws = [r for r in raws if r.is_file()]
        if raws:
            for raw in raws:
                out.append(postprocess.prepare_generated(Image.open(raw), {
                    "size": [dw, dh], "anchor": "bottom_center", "outline": True,
                    "outline_weight": 1, "generated_palette": "preserve"}, pal))
            return out
        for n in range(drawn_per_kind):
            src = deco_dir / f"{kind}_{n}.txt" if deco_dir else None
            if src is not None and src.is_file():
                out.append(pixel.load(src, pal, (dw, dh)))
            else:
                out.append(procedural.draw("deco", kind, pal, seed_of("deco", kind, n), (dw, dh)))
        return out

    for r, kind in enumerate(kinds):
        recipe = derived.get(kind)
        base = drawings(recipe["from"] if recipe else kind)
        for v in range(dv):
            img = deco_variant(base, v)
            if recipe:
                img = recolor_deco(img, recipe)
            img = postprocess.outline(img, pal.outline)
            deco.paste(img, (v * dw, r * dh))
    info["deco"] = {"cell": [dw, dh], "variants": dv, "kinds": {k: {"row": r} for r, k in enumerate(kinds)}}
    return sheet, deco, info


def _rng(*parts: object):
    import random
    return random.Random(seed_of(*parts))


# --------------------------------------------------------------------- all --

def build_highres_overlays(tspec: dict, pal: Palette, generated_dir: Path) -> tuple[Image.Image, dict]:
    """Render map overlays at double resolution while keeping the map grid unchanged."""
    spec = dict(tspec)
    spec["tile_size"] = int(tspec["tile_size"]) * 2
    size = spec["tile_size"]
    source, _, info = build_terrain(spec, pal, generated_dir=generated_dir)
    groups = [("barriers", name, entry) for name, entry in info["barriers"].items() if "masks" in entry]
    groups += [("roads", name, entry) for name, entry in info["roads"]["styles"].items()]
    masks = [0] + procedural.all_transition_masks()
    sheet = Image.new("RGBA", (len(masks) * size, max(1, len(groups) * 4) * size))
    result = {"tile_size": size, "masks": masks, "barriers": {}, "roads": {}}
    for group_index, (kind, name, entry) in enumerate(groups):
        row = group_index * 4
        result[kind][name] = {"row": row}
        for variant in range(4):
            for index in range(len(masks)):
                x = (int(entry["column"]) + variant * len(masks) + index) * size
                y = int(entry["row"]) * size
                sheet.paste(source.crop((x, y, x + size, y + size)), (index * size, (row + variant) * size))
    return sheet, result


def build_all(root: Path, out_root: Path | None = None, use_generated: bool = True, log=print) -> dict:
    paths = Paths(root, out_root)
    pal = Palette.load(paths.specs / "palette.json")
    sprite_specs = specs.load_sprite_specs(paths.specs)
    errs = specs.check_sprite_specs(sprite_specs, paths.specs)
    if errs:
        raise ValueError("spec errors:\n  " + "\n  ".join(errs))

    paths.atlases.mkdir(parents=True, exist_ok=True)
    paths.build.mkdir(parents=True, exist_ok=True)
    (paths.build / ".gdignore").write_text("")
    by_atlas: dict[str, dict[str, Image.Image]] = {a: {} for a in specs.ATLASES}
    sprites: dict[str, dict] = {}
    factions = json.loads((paths.specs / "factions.json").read_text())
    sources: dict[str, Image.Image] = {}
    auto = auto_creature_specs(sprite_specs, paths)
    specs_by_id = {x["id"]: x for x in sprite_specs}

    def source_of(sid: str) -> Image.Image:
        if sid not in sources:
            if sid in specs_by_id:
                sources[sid] = render_source(specs_by_id[sid], pal, paths, use_generated)[0]
            else:
                a = next(x for x in auto if x["id"] == sid)
                style = creatures_auto.faction_style(factions, a["faction"])
                if a["_kind"] == "upgrade":
                    sources[sid] = creatures_auto.upgrade_sprite(source_of(f"creature_{a['upgrade_of']}"), pal, style)
                else:
                    sources[sid] = creatures_auto.placeholder(pal, a["role"], style, seed_of(sid), tuple(a["size"]))
        return sources[sid]

    for a in auto:
        source_of(a["id"])
        a["_label"] = a["_kind"]
    for s in sprite_specs + auto:
        if s["id"] in sources and s in auto:
            img, label = postprocess.finish(sources[s["id"]], s, pal), s["_label"]
        else:
            img, label = render_sprite(s, pal, paths, use_generated)
        out = paths.build / s["category"] / f"{s['id']}.png"
        out.parent.mkdir(parents=True, exist_ok=True)
        img.save(out, optimize=True)
        atlas_name = f"dlc_{s['faction']}_{s['atlas']}" if s.get("dlc") else s["atlas"]
        by_atlas.setdefault(atlas_name, {})[s["id"]] = img
        k = int(s.get("export_scale", 1))
        entry = {"atlas": atlas_name, "category": s["category"], "source": label, "scale": k,
                 "anchor": [v * k for v in anchor_px(s)]}
        if s.get("data"):
            entry["data"] = s["data"]
        if s.get("nine_slice"):
            entry["nine_slice"] = [v * k for v in s["nine_slice"]]
        if s.get("upgrade_of"):
            entry["upgrade_of"] = s["upgrade_of"]
        if s.get("map_scale"):
            entry["map_scale"] = s["map_scale"]
        if s.get("flag"):
            entry["flag"] = [v * k for v in s["flag"]]
        if s.get("tint"):
            entry["tint"] = s["tint"]
        if s.get("hotspot"):
            entry["hotspot"] = s["hotspot"]
        sprites[s["id"]] = entry

    atlases: dict[str, dict] = {}
    for name, imgs in by_atlas.items():
        # Optional faction packs keep the main atlases stable and stay within
        # common GPU texture limits instead of accumulating a very tall strip.
        sheet, rects = atlas.pack(imgs, max_width=2048 if name.startswith("dlc_") else 512)
        p = paths.atlases / f"{name}.png"
        sheet.save(p, optimize=True)
        atlases[name] = {"path": res_path(p, paths.atlases.parent.parent), "size": list(sheet.size)}
        for sid, r in rects.items():
            sprites[sid]["rect"] = r

    tspec = specs.load_terrain_spec(paths.specs)
    terrain_ids = list(json.loads((paths.data / "terrains.json").read_text())["terrains"])
    terrs = specs.check_terrain_spec(tspec, terrain_ids, sorted(procedural.DECOS))
    if terrs:
        raise ValueError("terrain spec errors:\n  " + "\n  ".join(terrs))
    tsheet, dsheet, tinfo = build_terrain(tspec, pal, paths.specs / "pixel" / "deco", paths.specs / "pixel" / "terrain",
                                       paths.generated if use_generated else None)
    tp, dp = paths.atlases / "terrain.png", paths.atlases / "deco.png"
    tsheet.save(tp, optimize=True)
    dsheet.save(dp, optimize=True)
    base = paths.atlases.parent.parent
    tinfo["atlas"] = res_path(tp, base)
    tinfo["deco"]["atlas"] = res_path(dp, base)
    if use_generated:
        high_sheet, high_info = build_highres_overlays(tspec, pal, paths.generated)
        high_path = paths.atlases / "terrain_overlays_2x.png"
        high_sheet.save(high_path, optimize=True)
        high_info["atlas"] = res_path(high_path, base)
        tinfo["highres"] = high_info
    if use_generated and tspec.get("edge_patterns"):
        from . import terrain_edges
        edge_sheet, edge_info = terrain_edges.build(paths.root, tspec["edge_patterns"], int(tspec["tile_size"]))
        edge_path = paths.atlases / "terrain_edges.png"
        edge_sheet.save(edge_path, optimize=True)
        edge_info["atlas"] = res_path(edge_path, base)
        tinfo["edges"] = edge_info

    manifest = {
        "_doc": "Generated by tools/assets/pipeline.py build. Do not edit; change assets/specs instead.",
        "version": MANIFEST_VERSION,
        "atlases": atlases,
        "sprites": {k: sprites[k] for k in sorted(sprites)},
        "terrain": tinfo,
    }
    if (paths.specs / "creature_animations.json").is_file():
        from . import animations
        animations.build(paths.root, paths.atlases.parent.parent)
    paths.manifest.write_text(json.dumps(manifest, indent=1, sort_keys=False) + "\n")
    if (paths.specs / "campaign_illustrations.json").is_file():
        from . import illustrations
        illustrations.build(paths.root, paths.atlases.parent.parent)
    if (paths.specs / "menu_art.json").is_file():
        from . import menu_art
        menu_art.build(paths.root, paths.atlases.parent.parent)
    if (paths.specs / "town_scenes.json").is_file():
        from . import town_scenes
        town_scenes.build(paths.root, paths.atlases.parent.parent)
    if (paths.specs / "battlefields.json").is_file():
        from . import battlefields
        battlefields.build(paths.root, paths.atlases.parent.parent)
    if (paths.root / "assets/source/artifacts-001").is_dir():
        from . import artifacts
        artifacts.build(paths.root, paths.atlases.parent.parent)
    log(f"built {len(sprites)} sprites in {len(atlases)} atlases, terrain {tsheet.size[0]}x{tsheet.size[1]}, deco {dsheet.size[0]}x{dsheet.size[1]}")
    return manifest
