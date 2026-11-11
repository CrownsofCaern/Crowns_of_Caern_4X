"""Battle clips baked from rigged 3D models.

A unit listed in assets/specs/creature_models.json with an approved bake
sheet gets its battle clips (idle, move, attack, death) from that sheet
instead of the drawn move/attack sheets. Everything else (map, town, still
sprite) keeps the drawn art.

The bake sheet is made by tools/assets/bake_models.py: Godot renders the GLB,
then the frames are reduced to pixel art (box downscale, master palette, 1 px
outline) and laid out one action per row in 320x256 cells, feet on the battle
anchor. GPU renders are not byte-reproducible, so the sheet itself is the
reviewed source: `bake_models.py approve <id>` records its hash and
`pipeline.py build` only slices it, exactly like the drawn sheets.
"""
from __future__ import annotations

import json
from pathlib import Path

from PIL import Image

from . import animations

SPEC = "assets/specs/creature_models.json"
ACTIONS = ("idle", "move", "attack", "death")
# Extra clips only the 3D battle units play (tools/assets/export_live_units.gd);
# the sprite bake ignores them.
LIVE_ONLY_ACTIONS = ("idle_alt", "attack_alt")
DEFAULT_MS = {"idle": 160, "move": 110, "attack": 90, "death": 110}
LOOPS = {"idle": True, "move": True, "attack": False, "death": False}


def load_spec(root: Path) -> dict:
    path = root / SPEC
    return json.loads(path.read_text()) if path.is_file() else {"schema_version": 1, "units": []}


def sheet_path(unit: dict) -> str:
    return unit.get("bake", {}).get("sheet", f"assets/source/models/{unit['id']}/{unit['id']}_bake.png")


def approved(unit: dict) -> bool:
    return "sheet_sha256" in unit.get("bake", {})


def layout(unit: dict) -> list[tuple[str, int]]:
    """Rows of the bake sheet: (action, frame count), in sheet order. Clips
    marked "live_only" feed only the live 3D export (export_live_units.gd),
    so an approved sheet keeps its rows."""
    rows = []
    for action in ACTIONS:
        clip = unit.get("clips", {}).get(action)
        if clip and not clip.get("live_only"):
            rows.append((action, int(clip.get("frames", 6))))
    return rows


def clip_entry(unit: dict, action: str, row: int, count: int, atlas: str) -> dict:
    size = animations.SIZE
    clip = unit["clips"][action]
    ms = int(clip.get("ms", DEFAULT_MS[action]))
    entry = {"atlas": atlas, "frames": [[c * size[0], row * size[1], *size] for c in range(count)],
             "durations_ms": [ms] * count, "loop": bool(clip.get("loop", LOOPS[action]))}
    if action == "attack":
        hit = int(clip.get("impact_frame", count // 2))
        if not 0 <= hit < count:
            raise ValueError(f"{unit['id']}: attack impact_frame {hit} outside 0..{count - 1}")
        entry["events"] = [{"time_ms": hit * ms, "name": "impact"}]
    return entry


def build(root: Path, out: Path, manifest: dict) -> None:
    """Replaces the battle clips of every unit with an approved bake sheet and
    writes its atlas under `out`. Pending units change nothing."""
    size = animations.SIZE
    for unit in load_spec(root).get("units", []):
        if not approved(unit):
            continue
        source = root / sheet_path(unit)
        if not source.is_file():
            raise ValueError(f"model {unit['id']}: approved bake sheet {source} is missing")
        if animations.digest(source) != unit["bake"]["sheet_sha256"]:
            raise ValueError(f"model {unit['id']}: unreviewed bake sheet change; run bake_models.py approve")
        rows = layout(unit)
        sheet = Image.open(source).convert("RGBA")
        expected = (max(n for _, n in rows) * size[0], len(rows) * size[1])
        if sheet.size != expected:
            raise ValueError(f"model {unit['id']}: bake sheet is {sheet.size}, expected {expected}")
        sid = "creature_" + unit["id"]
        atlas = "animation_model_" + unit["id"]
        actions = {action: clip_entry(unit, action, row, n, atlas) for row, (action, n) in enumerate(rows)}
        entry = manifest["units"].get(sid, {})
        # Drawn clips stay for actions the model does not cover.
        entry["actions"] = {**entry.get("actions", {}), **actions}
        entry.setdefault("atlas", atlas)
        entry["model_source"] = sheet_path(unit)
        entry["model_sha256"] = unit["bake"]["sheet_sha256"]
        manifest["units"][sid] = entry
        if sid in manifest.get("pending", []):
            manifest["pending"].remove(sid)
        relative = f"assets/atlases/{atlas}.png"
        destination = out / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        sheet.save(destination, optimize=True)
        manifest["atlases"][atlas] = {"path": "res://" + relative, "size": list(sheet.size)}
