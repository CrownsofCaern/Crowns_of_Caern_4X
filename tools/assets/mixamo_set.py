"""Give a unit a class animation set retargeted from Mixamo clips.

  python3 tools/assets/mixamo_set.py ID CLASS --fbx-dir DIR [--keep-attack]
  python3 tools/assets/mixamo_set.py classes
  python3 tools/assets/mixamo_set.py alts [ID,ID...]   # live-only variants (ALTS),
      then restore_clips.py IDs to retarget them

Mixamo clips (FBX, "Without Skin", 30 fps) are shared by every unit of a
class, since the Tripo biped rigs all use Mixamo bone names. For each action
of the class this runs tools/assets/retarget_mixamo.gd (Godot headless, the
GODOT environment variable as for bake_models.py) to write assets/source/models/ID/ID_mx_<action>.glb
and points the unit's clip in assets/specs/creature_models.json at it, with
the frame window the class asks for, and sets the view yaw so the unit faces
screen right. --keep-attack leaves a posed attack (pole_thrust, bow_draw, ...)
in place, now starting from the retargeted idle. Weapons fixed with
rigid_weapon.py are turned to sit in the hand the way Mixamo's clips expect.
--mirror plays every clip left-right mirrored, for units whose weapon sits in
the left hand (Tripo often rigs it there): the swing then uses the weapon arm.
Then bake with bake_models.py render.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

ROOT = Path(__file__).resolve().parents[2]
SPEC = ROOT / "assets/specs/creature_models.json"

# action: (FBX name, frames, window as fractions of the clip, in_place)
HUMAN_DEATH = ("Sword And Shield Death", 8, (0.0, 0.85), False)
CLASSES: dict[str, dict[str, tuple]] = {
    "sword_shield": {
        "idle": ("Sword And Shield Idle", 6, (0.0, 0.12), False),
        "move": ("Sword And Shield Run", 8, (0.0, 1.0), True),
        "attack": ("Sword And Shield Slash", 8, (0.1, 0.8), False),
        "death": HUMAN_DEATH,
    },
    "spear": {
        "idle": ("Idle", 6, (0.0, 0.6), False),
        "move": ("Running", 8, (0.0, 1.0), True),
        "death": HUMAN_DEATH,
    },
    "bow": {
        "idle": ("Idle", 6, (0.0, 0.6), False),
        "move": ("Running", 8, (0.0, 1.0), True),
        "attack": ("Standing Draw Arrow", 8, (0.0, 1.0), False),
        "death": HUMAN_DEATH,
    },
    "caster": {
        "idle": ("Idle", 6, (0.0, 0.6), False),
        "move": ("Running", 8, (0.0, 1.0), True),
        "attack": ("Standing 1H Magic Attack 01", 8, (0.1, 0.8), False),
        "death": HUMAN_DEATH,
    },
    "caster_2h": {
        "idle": ("Idle", 6, (0.0, 0.6), False),
        "move": ("Running", 8, (0.0, 1.0), True),
        "attack": ("Standing 2H Magic Attack 02", 8, (0.1, 0.8), False),
        "death": ("Mutant Dying", 8, (0.0, 0.8), False),
    },
    # Throwers carry their missile in the right hand ("throw" in the spec
    # cuts it out of the mesh) and let it fly from an overhand throw.
    "thrower": {
        "idle": ("Idle", 6, (0.0, 0.6), False),
        "move": ("Running", 8, (0.0, 1.0), True),
        "attack": ("Goalkeeper Overhand Throw", 8, (0.15, 0.85), True),
        "death": ("Mutant Dying", 8, (0.0, 0.8), False),
    },
    # Two-handed heavy weapons: a leaping overhead great sword blow.
    "heavy": {
        "idle": ("Standing Idle 04", 6, (0.0, 0.3), False),
        "move": ("Running", 8, (0.0, 1.0), True),
        "attack": ("Great Sword Jump Attack", 8, (0.15, 0.55), False),
        "death": HUMAN_DEATH,
    },
    # Clubs and maces: a stocky stance and a one-handed club blow.
    "club": {
        "idle": ("Dwarf Idle", 6, (0.0, 0.3), False),
        "move": ("Standing Walk Forward", 8, (0.0, 1.0), True),
        "attack": ("One Hand Club Combo", 8, (0.35, 0.7), False),
        "death": ("Mutant Dying", 8, (0.0, 0.8), False),
    },
    "brute": {
        "idle": ("Idle", 6, (0.0, 0.6), False),
        "move": ("Mutant Walking", 8, (0.0, 1.0), True),
        "attack": ("Mutant Punch", 8, (0.0, 1.0), False),
        "death": ("Mutant Dying", 8, (0.0, 0.8), False),
    },
}
# Live-only variants (the 3D battle plays them on every other figure, so a
# block does not stand and swing as one; the 2D sheets keep their rows):
# a second idle for every class and a plain overhead slash for the heavies,
# whose main attack is a leap. Whole clips, motion only (no meshes).
ALTS: dict[str, dict[str, tuple]] = {
    "sword_shield": {"idle_alt": ("Sword And Shield Idle 2", 6, (0.0, 1.0), False)},
    "spear": {"idle_alt": ("Standing Idle 02", 6, (0.0, 1.0), False)},
    "bow": {"idle_alt": ("Standing Idle 02", 6, (0.0, 1.0), False)},
    "thrower": {"idle_alt": ("Standing Idle 02", 6, (0.0, 1.0), False)},
    "caster": {"idle_alt": ("Standing Idle", 6, (0.0, 1.0), False)},
    "caster_2h": {"idle_alt": ("Standing Idle", 6, (0.0, 1.0), False)},
    "heavy": {"idle_alt": ("Great Sword Idle", 6, (0.0, 1.0), False),
              "attack_alt": ("Great Sword Slash", 8, (0.05, 0.8), False)},
    "club": {"idle_alt": ("Dwarf Idle 2", 6, (0.0, 1.0), False)},
    "brute": {"idle_alt": ("Orc Idle", 6, (0.0, 1.0), False)},
}
IMPACT = 4
# A thrown missile lands a little after the release, not at the swing.
IMPACT_BY_CLIP = {"Goalkeeper Overhand Throw": 6}
# A weapon held in a fist points forward in Mixamo's T-pose; a caster's staff
# stands up.
GRIP_DIR = [0.0, 0.0, 1.0]
GRIP_DIR_STAFF = [0.0, 1.0, 0.0]
# Retargeted units face Mixamo's +Z; this turns them to face screen right.
YAW = 45


def mesh_centre(path: Path) -> list[float]:
    """The hips' x and z in the rigged model (the body's vertical axis)."""
    from rigid_weapon import Glb, joint_index, skin_info
    names, heads = skin_info(Glb(path))
    hips = heads[joint_index(names, "mixamorig:Hips")]
    return [float(hips[0]), float(hips[2])]


def grips(unit: dict) -> list[dict]:
    """Weapon axes from rigid_weapon.py: the first capsule fixed to each hand,
    pointing away from the grip, and the outward face of each shield slab
    (bind/mesh space)."""
    out, seen = [], set()
    pole = unit.get("weapon")
    if pole and pole.get("kind") == "pole":
        # The stand-in pike from split_weapon.py stands upright in the fist.
        axis = [pole["end"][i] - pole["start"][i] for i in range(3)]
        out.append({"bone": pole["bone"], "axis": axis, "dir": GRIP_DIR_STAFF})
        seen.add(pole["bone"])
    for region in unit.get("rigid", []):
        if "slab" in region and region.get("bone"):
            points = region["slab"][0]
            (x0, z0), (x1, z1) = points[0], points[-1]
            normal = [z1 - z0, 0.0, -(x1 - x0)]
            # Outward: away from the body's vertical axis (the mesh centre).
            mid = [(x0 + x1) / 2, (z0 + z1) / 2]
            centre = unit.get("_centre", [0.0, 0.0])
            if normal[0] * (mid[0] - centre[0]) + normal[2] * (mid[1] - centre[1]) < 0:
                normal = [-v for v in normal]
            out.append({"bone": region["bone"], "axis": normal, "twist": True})
            continue
        bone = region.get("bone", "")
        if "axis" in region and bone not in seen:
            # An explicit weapon axis (a bow's limbs) and where it points.
            out.append({"bone": bone, "axis": region["axis"], **({"dir": region["dir"]} if "dir" in region else {})})
            seen.add(bone)
            continue
        if "Hand" not in bone or "capsule" not in region or bone in seen or region.get("part") == "guard":
            continue
        a, b, _ = region["capsule"]
        axis = [b[i] - a[i] for i in range(3)]
        out.append({"bone": bone, "axis": axis})
        seen.add(bone)
    return out


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("id")
    parser.add_argument("cls", nargs="?")
    parser.add_argument("--fbx-dir", type=Path)
    parser.add_argument("--keep-attack", action="store_true")
    parser.add_argument("--only", help="comma-separated actions to redo")
    parser.add_argument("--mirror", action="store_true",
                        help="mirror the clips left-right (weapon in the left hand)")
    parser.add_argument("--clip", action="append", default=[], metavar="ACTION=FBX[@START-END]",
                        help="use another Mixamo clip for one action (variation within a class), "
                             "e.g. attack='Sword And Shield Slash (1)@0.1-0.5'")
    parser.add_argument("--spec", type=Path, default=SPEC,
                        help="spec file (default assets/specs/creature_models.json)")
    args = parser.parse_args()
    spec_path = args.spec if args.spec.is_absolute() else ROOT / args.spec
    if args.id == "alts":
        add_alts(spec_path, args.cls.split(",") if args.cls else [], args.fbx_dir)
        return
    if args.id == "classes":
        for name, actions in CLASSES.items():
            print(name, {a: c[0] for a, c in actions.items()})
        return
    if args.cls not in CLASSES or args.fbx_dir is None:
        raise SystemExit(f"give a class ({', '.join(CLASSES)}) and --fbx-dir")
    spec = json.loads(spec_path.read_text())
    unit = next((u for u in spec["units"] if u["id"] == args.id), None)
    if unit is None:
        raise SystemExit(f"{args.id}: not in {spec_path}")
    rigged = ROOT / unit["model"]
    unit["_centre"] = mesh_centre(rigged)
    only = set(args.only.split(",")) if args.only else None
    actions = dict(CLASSES[args.cls])
    for override in args.clip:
        action, _, value = override.partition("=")
        if action not in actions:
            raise SystemExit(f"--clip {override}: {args.cls} has no action {action}")
        fbx, _, window = value.partition("@")
        _, frames, (start, end), in_place = actions[action]
        if window:
            start, end = (float(v) for v in window.split("-"))
        actions[action] = (fbx, frames, (start, end), in_place)
    for action, (fbx, frames, (start, end), in_place) in actions.items():
        if only and action not in only:
            continue
        if action == "attack" and args.keep_attack and unit.get("clips", {}).get("attack", {}).get("pose"):
            continue
        grip_dir = GRIP_DIR_STAFF if args.cls.startswith("caster") else GRIP_DIR
        src = args.fbx_dir / f"{fbx}.fbx"
        if not src.exists():
            raise SystemExit(f"missing {src}")
        out = rigged.parent / f"{args.id}_mx_{action}.glb"
        cmd = [os.environ.get("GODOT", "godot"), "--headless", "--path", str(ROOT), "--script",
               "res://tools/assets/retarget_mixamo.gd", "--", str(rigged), str(src), str(out), action]
        cmd += ["in_place"] if in_place else []
        cmd += ["mirror"] if args.mirror else []
        for grip in grips(unit):
            kind = "twist" if grip.get("twist") else "grip"
            to = grip.get("dir", grip_dir)
            cmd.append("%s=%s,%s" % (kind, grip["bone"], ",".join(str(v) for v in grip["axis"] + to)))
        done = subprocess.run(cmd, capture_output=True, text=True)
        if done.returncode != 0 or not out.exists():
            print(done.stdout[-2000:], done.stderr[-2000:])
            raise SystemExit(f"{args.id}/{action}: retarget failed")
        clip = {"model": str(out.relative_to(ROOT)), "clip": action, "frames": frames, "mixamo": fbx}
        if (start, end) != (0.0, 1.0):
            clip["start"], clip["end"] = start, end
        if args.mirror:
            clip["mirror"] = True
        if action == "attack":
            clip["impact_frame"] = IMPACT_BY_CLIP.get(fbx, IMPACT)
        unit.setdefault("clips", {})[action] = clip
        print(f"{args.id}/{action}: {fbx}")
    # A posed attack (pole_thrust, bow_draw, ...) starts from the new idle.
    attack = unit.get("clips", {}).get("attack", {})
    if attack.get("pose") and "idle" in unit["clips"] and attack.get("model") != unit["clips"]["idle"]["model"]:
        attack["model"], attack["clip"] = unit["clips"]["idle"]["model"], "idle"
    unit.setdefault("view", {})["yaw_degrees"] = YAW
    unit.pop("_centre", None)
    unit["class"] = args.cls
    hands = {g["bone"] for g in grips(unit) if not g.get("twist")}
    if not args.mirror and any("LeftHand" in b for b in hands) and not any("RightHand" in b for b in hands):
        print(f"{args.id}: the weapon is in the left hand; --mirror swings it with that arm")
    spec_path.write_text(json.dumps(spec, indent=2) + "\n")


def add_alts(spec_path: Path, ids: list[str], fbx_dir: Path | None) -> None:
    """Adds the class's live-only variants (ALTS) to every Mixamo unit (or
    `ids`), mirrored like its idle. restore_clips.py then retargets them."""
    spec = json.loads(spec_path.read_text())
    for unit in spec["units"]:
        cls = unit.get("class", "")
        if cls not in ALTS or (ids and unit["id"] not in ids):
            continue
        idle = unit.get("clips", {}).get("idle", {})
        if not idle.get("mixamo"):
            continue
        for action, (fbx, frames, (start, end), _) in ALTS[cls].items():
            clip = {"model": str(Path(unit["model"]).parent / f"{unit['id']}_mx_{action}.glb"), "clip": action,
                    "frames": frames, "mixamo": fbx, "live_only": True, "anim_only": True}
            if (start, end) != (0.0, 1.0):
                clip["start"], clip["end"] = start, end
            if idle.get("mirror"):
                clip["mirror"] = True
            unit["clips"][action] = clip
            print(f"{unit['id']}/{action}: {fbx}", flush=True)
    spec_path.write_text(json.dumps(spec, indent=2) + "\n")


if __name__ == "__main__":
    main()
