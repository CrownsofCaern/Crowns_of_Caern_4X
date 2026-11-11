"""Idle, walk and double-strike attack clips from reference-conditioned sheets.

Second animation pass on top of creature_animations.json (move + attack).
Each group in assets/specs/creature_idle_animations.json gets TWO generated
sheets, one row per unit, every cell facing right:

  sheet A (7 columns)  columns 1-3 idle (rest/inhale, weight shift, exhale;
                       played 1-2-3-2 as a loop), columns 4-7 walk cycle
  sheet B (6 columns)  attack: anticipation, wind-up, MAIN HIT (column 3),
                       a follow-up blow or follow-through (4-5), recovery
                       (sheet A column 1 closes the clip as the rest pose)

Cells are cut and registered exactly like the move/attack sheets
(animations.extract_cells / register) into atlases animation_idle_<group>_a
and _b (still + poses per row). Until BOTH sheets of a group have a reviewed
hash the group is pending and changes nothing. Sheets come from
tools/assets/generate_idle_sheets.py (OpenAI API or ChatGPT by hand).
"""
from __future__ import annotations

import json
from pathlib import Path

from PIL import Image

from . import animations

SPEC = "assets/specs/creature_idle_animations.json"
SHEETS = {"A": 7, "B": 6}
# The generator rarely lands exactly on the still, so the loop uses its own
# rest pose (sheet A column 1) and ping-pongs; the attack returns to it too.
IDLE_COLUMNS = [1, 2, 3, 2]
IDLE_MS = [420, 300, 380, 300]
MOVE_COLUMNS = [4, 5, 6, 7]
MOVE_MS = [150, 150, 150, 150]
ATTACK_MS = [140, 150, 120, 120, 130, 140, 140]
# The main hit is always column B3; a follow-up blow, if drawn, is cosmetic.
IMPACTS_MS = [sum(ATTACK_MS[:2])]

COMMON = (
    "Create a production ANIMATION sprite sheet for the FOUR EXACT existing dark fantasy pixel-art creatures in the "
    "attached horizontal reference strip. Preserve original anatomy, equipment, colors, outline weight and identity "
    "pixel for pixel wherever the pose allows. Reference left-to-right becomes rows TOP-TO-BOTTOM. Generate EXACTLY "
    "{cols} COLUMNS and FOUR ROWS, {cells} separate full-body sprites, on transparent alpha, landscape 1536x1024. No "
    "background, shadows, grid, labels or extra figures. Keep wide transparent gutters. Each equal cell {cw}x256. Body "
    "root centered in the cell, the SAME body size, camera and grounded baseline as the reference in every cell. Full "
    "weapons, tails and wings fit inside the cell. SAME unit in every column of its row. All face RIGHT. Upper-left "
    "lighting, crisp detailed serious pixel art, no redesign, no bright cartoon look.\n")

SHEET_A = (
    "Columns 1-3: IDLE loop starting from the reference pose: column 1 rest pose matching the reference as closely as "
    "possible (inhale: chest and shoulders rise one or two pixels), column 2 weight shift (head turns or tilts a "
    "little, weapon or free hand shifts its grip, tail or cloak sways, wings fold and resettle, eyes or flames "
    "flicker), column 3 exhale. SMALL, believable motion of individual parts only: feet stay planted, no stepping, no "
    "whole-image stretching or bouncing. Flying units hover with a slow wing beat, spectral units drift and billow, "
    "constructs hum with tiny mechanical shifts, plants rustle, swarms mill about.\n"
    "Columns 4-7: WALK cycle in place: first contact pose, first passing/support pose, opposite contact pose, opposite "
    "passing/support pose. Animate individual limbs with alternating planted feet and bending knees; quadrupeds move "
    "all four legs in a coherent gait, flying units flap wings with a steady body, spectral units billow and float, "
    "plants crawl with roots, mechanical artillery rolls its wheels and does not grow legs, swarms move as a coherent "
    "cluster. Keep torso shape steady and smooth continuity from the last column back to column 4.\n")

SHEET_B = (
    "Columns 1-6: one ATTACK toward the RIGHT, six poses with real weight and flow: column 1 anticipation (weight "
    "drawn back), column 2 wind-up peak (fully coiled, weapon, claws or jaws raised behind, strongest silhouette), "
    "column 3 the MAIN HIT at full contact or release to the right, column 4 and column 5 whatever suits THIS "
    "creature best: either a follow-up blow (for example a spearman's second quick thrust, a bite followed by a claw "
    "swipe, a cut and backswing) or a powerful follow-through and recoil, column 6 recovery back towards the rest "
    "pose. Archers draw the SAME bow and loose a straight arrow in column 3; spellcasters gather and release a "
    "modest effect from their existing staff or hand in column 3; artillery fires with barrel recoil in column 3 and "
    "settles. Use the SAME weapon and anatomy as the reference; not every creature uses a sword. Avoid gigantic "
    "particle effects; preserve anatomy, number of limbs and rigid weapon construction.\n")


def rows_line(group: dict) -> str:
    return "; ".join(
        f"Row{i + 1}: {u['id']} ({u['name']}), {u['role']}, {', '.join(u.get('tags', []))}; exactly reference character {i + 1}"
        for i, u in enumerate(group["units"]))


def prompt(group: dict, sheet: str = "A") -> str:
    """The image prompt for one of a group's sheets (reference strip attached)."""
    cols = SHEETS[sheet]
    words = {7: "SEVEN", 6: "SIX"}[cols]
    head = COMMON.format(cols=words, cells=cols * 4, cw=1536 // cols)
    body = SHEET_A if sheet == "A" else SHEET_B
    return (head + body + f"ROWS: {rows_line(group)}\n"
            "Every frame must be clearly distinct in the appropriate limb, head or weapon positions while keeping exact "
            "character continuity. Undead remain frightening, demons monstrous, beasts keep their actual anatomy.")


def load_spec(root: Path) -> dict:
    path = root / SPEC
    return json.loads(path.read_text()) if path.is_file() else {}


def _sheet_frames(root: Path, group: dict, key: str, spec: dict) -> tuple[list, dict]:
    """Registered poses per unit row for one sheet: [[pose, ...] per row]."""
    sheet_info = group["sheets"][key]
    source = root / sheet_info["source"]
    if animations.digest(source) != sheet_info["source_sha256"]:
        raise ValueError(f"idle {group['id']} {key}: unreviewed animation source change")
    sheet = Image.open(source).convert("RGBA")
    columns, rows = sheet_info["grid"]
    if [columns, rows] != [SHEETS[key], len(group["units"])]:
        raise ValueError(f"idle {group['id']} {key}: expected {SHEETS[key]} columns and one row per unit")
    row_data, row_warnings = animations.extract_rows(sheet, rows)
    out, qcs = [], {}
    for row, unit in enumerate(group["units"]):
        ref_path = root / unit["reference_source"]
        if animations.digest(ref_path) != unit["reference_sha256"]:
            raise ValueError(f"{unit['id']}: approved reference changed; review idle continuity")
        cells, extraction = animations.extract_cells(sheet, row, columns, rows, row_data)
        frames, qc = animations.register(cells, Image.open(ref_path).convert("RGBA"), int(spec.get("alpha_floor", 64)))
        qc["extraction"] = extraction
        qc["warnings"] += extraction["warnings"] + row_warnings
        qcs[unit["id"]] = qc
        out.append(frames)
    return out, qcs


def ready(group: dict) -> bool:
    return all("source_sha256" in group.get("sheets", {}).get(k, {}) for k in SHEETS)


def build(root: Path, out: Path, manifest: dict) -> None:
    """Adds idle, walk and attack clips of every reviewed group to `manifest`
    and writes their atlases under `out`."""
    spec = load_spec(root)
    size = animations.SIZE
    for group in spec.get("groups", []):
        if not ready(group):
            continue   # pending: nothing changes until both sheets are reviewed
        poses = {k: _sheet_frames(root, group, k, spec) for k in SHEETS}
        names = {k: f"animation_idle_{group['id']}_{k.lower()}" for k in SHEETS}
        atlases = {k: Image.new("RGBA", ((SHEETS[k] + 1) * size[0], len(group["units"]) * size[1])) for k in SHEETS}
        for row, unit in enumerate(group["units"]):
            sid = "creature_" + unit["id"]
            if sid not in manifest["units"]:
                raise ValueError(f"idle {group['id']}: {sid} has no move/attack clips yet")
            reference = Image.open(root / unit["reference_source"]).convert("RGBA")
            rest = Image.new("RGBA", size)
            rest.paste(reference, (96, 80))
            for k in SHEETS:
                for c, frame in enumerate([rest, *poses[k][0][row]]):
                    atlases[k].paste(frame, (c * size[0], row * size[1]))
                manifest["qc"][f"{sid}/sheet_{k}"] = poses[k][1][unit["id"]]

            def rect(c: int) -> list:
                return [c * size[0], row * size[1], *size]

            unit_entry = manifest["units"][sid]
            actions = unit_entry["actions"]
            actions["idle"] = {"atlas": names["A"], "frames": [rect(c) for c in IDLE_COLUMNS],
                               "durations_ms": list(IDLE_MS), "loop": True}
            actions["move"] = {"atlas": names["A"], "frames": [rect(c) for c in MOVE_COLUMNS],
                               "durations_ms": list(MOVE_MS), "loop": True}
            # Attack: B1-B6, then sheet A's rest pose as the recovery.
            actions["attack"] = {"atlas": names["B"], "frames": [rect(c) for c in range(1, 7)] + [rect(1)],
                                 "frame_atlases": [names["B"]] * 6 + [names["A"]],
                                 "durations_ms": list(ATTACK_MS), "loop": False,
                                 "events": [{"time_ms": t, "name": "impact"} for t in IMPACTS_MS]}
            unit_entry["idle_sources"] = [group["sheets"][k]["source"] for k in SHEETS]
        for k in SHEETS:
            relative = f"assets/atlases/{names[k]}.png"
            destination = out / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            atlases[k].save(destination, optimize=True)
            manifest["atlases"][names[k]] = {"path": "res://" + relative, "size": list(atlases[k].size)}


def plan(root: Path) -> dict:
    """A fresh idle spec mirroring the move/attack groups (same units, same
    reference strips and stills), every group pending."""
    base = json.loads((root / "assets/specs/creature_animations.json").read_text())
    groups = []
    for g in base["groups"]:
        groups.append({
            "id": g["id"],
            "faction": g.get("faction", ""),
            "reference": g["reference"],
            "sheets": {k: {"source": f"assets/source/batches/creature-idle-001/{g['id']}-{k.lower()}-source.png",
                           "grid": [n, len(g["units"])]} for k, n in SHEETS.items()},
            "units": [{k: u[k] for k in ("id", "name", "role", "tags", "reference_source", "reference_sha256") if k in u}
                      for u in g["units"]],
        })
    return {"schema_version": 1,
            "_doc": "Idle, walk and double-strike attack clips: two generated sheets per group, A (idle + walk, 7 columns) "
                    "and B (attack, 6 columns); see tools/assets/crowns_of_cinder_assets/idle_animations.py. "
                    "A sheet without source_sha256 is pending.",
            "alpha_floor": base.get("alpha_floor", 64), "groups": groups}
