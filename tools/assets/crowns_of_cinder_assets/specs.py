"""Loading and schema checks for assets/specs/*.json."""
from __future__ import annotations

import json
import re
from pathlib import Path

SPRITE_SPEC_FILES = ("creatures.json", "objects.json", "ui.json")
ATLASES = ("units", "objects", "ui")
SOURCE_KINDS = ("pixel", "procedural")
ID_RE = re.compile(r"^[a-z][a-z0-9_]*$")


def load_sprite_specs(spec_dir: Path) -> list[dict]:
    """All sprite specs with file defaults applied, in file order."""
    out: list[dict] = []
    for name in SPRITE_SPEC_FILES:
        doc = json.loads((spec_dir / name).read_text())
        defaults = doc.get("defaults", {})
        for entry in doc["assets"]:
            spec = dict(defaults)
            spec.update(entry)
            spec["_file"] = name
            out.append(spec)
    optional = spec_dir / "dlc_factions.json"
    if optional.is_file():
        for entry in json.loads(optional.read_text())["assets"]:
            out.append({**entry, "_file": "dlc_factions.json"})
    return out


def check_sprite_specs(specs: list[dict], spec_dir: Path) -> list[str]:
    errors: list[str] = []
    seen: set[str] = set()
    for s in specs:
        sid = s.get("id", "?")
        where = f"{s.get('_file')}:{sid}"
        if not ID_RE.match(sid):
            errors.append(f"{where}: id must be snake_case ([a-z][a-z0-9_]*)")
        if sid in seen:
            errors.append(f"{where}: duplicate id")
        seen.add(sid)
        size = s.get("size")
        if not (isinstance(size, list) and len(size) == 2 and all(isinstance(v, int) and 4 <= v <= 256 for v in size)):
            errors.append(f"{where}: size must be [w, h] with 4..256 px")
            continue
        if s.get("atlas") not in ATLASES:
            errors.append(f"{where}: atlas must be one of {ATLASES}")
        if s.get("anchor") not in ("bottom_center", "center"):
            errors.append(f"{where}: anchor must be bottom_center or center")
        if int(s.get("export_scale", 1)) not in (1, 2, 3, 4):
            errors.append(f"{where}: export_scale must be 1..4")
        if not s.get("prompt"):
            errors.append(f"{where}: every asset needs a prompt (used for generation and as its description)")
        if s.get("generated_palette", "master") not in ("master", "preserve"):
            errors.append(f"{where}: generated_palette must be master or preserve")
        src = s.get("source", {})
        kind = src.get("kind")
        if kind not in SOURCE_KINDS:
            errors.append(f"{where}: source.kind must be one of {SOURCE_KINDS}")
        elif kind == "pixel" and not (spec_dir / src.get("file", "")).is_file():
            errors.append(f"{where}: pixel source {src.get('file')} not found")
        elif kind == "procedural" and src.get("drawer") not in ("structure", "ui", "deco"):
            errors.append(f"{where}: procedural drawer must be structure, ui or deco")
        ns = s.get("nine_slice")
        if ns is not None:
            if not (isinstance(ns, list) and len(ns) == 4 and ns[0] + ns[2] < size[0] and ns[1] + ns[3] < size[1]):
                errors.append(f"{where}: nine_slice [l, t, r, b] must leave a centre")
    return errors


def load_terrain_spec(spec_dir: Path) -> dict:
    return json.loads((spec_dir / "terrain.json").read_text())


def check_terrain_spec(spec: dict, terrain_ids: list[str], deco_kinds: list[str]) -> list[str]:
    errors: list[str] = []
    ts = spec.get("terrains", {})
    for tid in terrain_ids:
        if tid not in ts:
            errors.append(f"terrain.json: no tiles for terrain '{tid}' from data/terrains.json")
    base_kinds = {k for t in ts.values() for k in t.get("deco", {}).get("kinds", [])}
    for kind, recipe in spec.get("deco_derived", {}).items():
        if kind.startswith("_"):
            continue
        if kind in base_kinds or kind in deco_kinds:
            errors.append(f"terrain.json: derived deco '{kind}' shadows a drawn kind")
        if recipe.get("from") not in base_kinds:
            errors.append(f"terrain.json: derived deco '{kind}' needs 'from' naming a drawn kind")
    prios = [t.get("priority") for t in ts.values()]
    if len(set(prios)) != len(prios):
        errors.append("terrain.json: priorities must be unique (they order the transition layers)")
    for tid, t in ts.items():
        if tid not in terrain_ids:
            errors.append(f"terrain.json: '{tid}' is not a terrain in data/terrains.json")
        for k in ("ground", "base", "priority", "fringe", "rim", "prompt"):
            if k not in t:
                errors.append(f"terrain.json:{tid}: missing '{k}'")
        for kind in t.get("deco", {}).get("kinds", []):
            if kind not in deco_kinds:
                errors.append(f"terrain.json:{tid}: unknown deco kind '{kind}'")
        ch = t.get("deco", {}).get("chance", 0)
        if not 0 <= ch <= 1:
            errors.append(f"terrain.json:{tid}: deco chance must be 0..1")
    return errors
