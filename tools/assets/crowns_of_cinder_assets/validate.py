"""Validation of built assets against specs, palette and game data."""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np
from PIL import Image

from . import specs
from .build import Paths
from .palette import Palette


def validate(root: Path, out_root: Path | None = None) -> list[str]:
    paths = Paths(root, out_root)
    errors: list[str] = []
    from . import dlc
    errors += dlc.validate(root)
    pal = Palette.load(paths.specs / "palette.json")
    sprite_specs = specs.load_sprite_specs(paths.specs)
    errors += specs.check_sprite_specs(sprite_specs, paths.specs)
    if not paths.manifest.is_file():
        return errors + ["assets/manifest.json missing: run tools/assets/pipeline.py build"]
    man = json.loads(paths.manifest.read_text())
    sprites = man.get("sprites", {})
    base = paths.manifest.parent.parent

    # coverage against game data
    data = paths.data
    from .creatures_auto import load_creatures
    for cid in load_creatures(data):
        if f"creature_{cid}" not in sprites:
            errors.append(f"creature '{cid}' has no sprite (expected id creature_{cid})")
    for rid in json.loads((data / "resources.json").read_text())["resources"]:
        if f"resource_{rid}" not in sprites:
            errors.append(f"resource '{rid}' has no sprite (expected id resource_{rid})")
    buildings = json.loads((data / "buildings.json").read_text()) if (data / "buildings.json").is_file() else {}
    for town in buildings.get("towns", {}):
        if f"town_{town}" not in sprites:
            errors.append(f"town type '{town}' has no sprite (expected id town_{town})")
    mine_res = set(buildings.get("economy", {}).get("mines", {}))
    for m in _map_objects(data, "mine"):
        mine_res.add(m.get("resource", ""))
    for rid in sorted(mine_res):
        if f"mine_{rid}" not in sprites:
            errors.append(f"mine of '{rid}' has no sprite (expected id mine_{rid})")
    if (data / "encounters.json").is_file():
        for eid in json.loads((data / "encounters.json").read_text())["encounters"]:
            if f"encounter_{eid}" not in sprites:
                errors.append(f"encounter '{eid}' has no sprite (expected id encounter_{eid})")
    for tid in json.loads((data / "terrains.json").read_text())["terrains"]:
        if tid not in man.get("terrain", {}).get("terrains", {}):
            errors.append(f"terrain '{tid}' missing from the terrain atlas")

    atlases: dict[str, Image.Image] = {}
    for name, a in man.get("atlases", {}).items():
        p = base / a["path"].removeprefix("res://")
        if not p.is_file():
            errors.append(f"atlas {name}: {p} missing")
            continue
        atlases[name] = Image.open(p).convert("RGBA")

    from .build import auto_creature_specs
    for s in sprite_specs + auto_creature_specs(sprite_specs, paths):
        sid = s["id"]
        if sid not in sprites:
            errors.append(f"{sid}: not in manifest (stale build?)")
            continue
        m = sprites[sid]
        k = int(s.get("export_scale", 1))
        want = (s["size"][0] * k, s["size"][1] * k)
        if m.get("atlas") not in atlases:
            continue
        x, y, w, h = m["rect"]
        if (w, h) != want:
            errors.append(f"{sid}: {w}x{h} in atlas, spec says {want[0]}x{want[1]}")
            continue
        img = atlases[m["atlas"]].crop((x, y, x + w, y + h))
        errors += check_image(sid, img, pal, s.get("background", "transparent"),
                              preserve_palette=s.get("generated_palette") == "preserve" and m.get("source") == "generated")

    t = man.get("terrain", {})
    if "atlas" in t:
        sheet = Image.open(base / t["atlas"].removeprefix("res://")).convert("RGBA")
        ts = int(t["tile_size"])
        for tid, info in t["terrains"].items():
            for v in range(int(t["variants"])):
                tile = sheet.crop((v * ts, info["row"] * ts, (v + 1) * ts, (info["row"] + 1) * ts))
                errors += check_image(f"terrain {tid} variant {v}", tile, pal, "opaque",
                                      preserve_palette=(paths.generated / f"terrain_{tid}.png").is_file())
        if len(t.get("transition_masks", [])) != 46:
            errors.append("terrain: expected 46 transition masks")
        if not any(paths.generated.glob("terrain_*.png")) and pal.off_palette_pixels(sheet):
            errors.append("terrain atlas: off-palette pixels")
        deco = Image.open(base / t["deco"]["atlas"].removeprefix("res://")).convert("RGBA")
        if not any(paths.generated.glob("deco_*.png")) and pal.off_palette_pixels(deco):
            errors.append("deco atlas: off-palette pixels")
    from . import illustrations
    errors += illustrations.validate(root, out_root)
    from . import town_scenes
    errors += town_scenes.validate(root, out_root)
    from . import ultimate_buildings
    errors += ultimate_buildings.validate(root, out_root)
    from . import animations
    errors += animations.validate(root, out_root)
    from . import battlefields
    errors += battlefields.validate(root, out_root)
    return errors


def placeholders(root: Path) -> list[str]:
    """Creature sprites that are still generated placeholders."""
    man = json.loads(Paths(root).manifest.read_text())
    return sorted(k for k, v in man.get("sprites", {}).items() if v.get("source") == "placeholder")


def _map_objects(data: Path, kind: str) -> list[dict]:
    out = []
    for mp in sorted((data / "maps").glob("*.json")):
        out += [o for o in json.loads(mp.read_text()).get("objects", []) if o.get("type") == kind]
    return out


def check_image(name: str, img: Image.Image, pal: Palette, background: str, preserve_palette: bool = False) -> list[str]:
    errs: list[str] = []
    a = np.array(img.convert("RGBA"))
    alpha = a[:, :, 3]
    if not (alpha > 0).any():
        errs.append(f"{name}: image is empty")
        return errs
    if background == "opaque":
        if (alpha < 255).any():
            errs.append(f"{name}: must be fully opaque")
    else:
        if not np.isin(alpha, (0, 255)).all():
            errs.append(f"{name}: alpha must be 0 or 255 (hard pixel edges)")
        border = np.concatenate([alpha[0, :], alpha[:, 0], alpha[:, -1]])
        if (border == 0).sum() == 0:
            errs.append(f"{name}: background is not transparent (no transparent border pixels)")
    off = 0 if preserve_palette else pal.off_palette_pixels(img)
    if off:
        errs.append(f"{name}: {off} pixels outside the master palette")
    return errs
