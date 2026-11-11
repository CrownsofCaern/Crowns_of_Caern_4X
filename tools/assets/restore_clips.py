"""Rebuild a unit's clip GLBs from what the spec records, without new paid tasks.

  python3 tools/assets/restore_clips.py [--from DIR] [--fbx-dir DIR] [ID ...]

The clip GLBs under assets/source/models/<id>/ are git-ignored and large, so
most checkouts only have the baked sheets. This puts them back so the unit can
be re-baked or exported for live 3D (export_live_units.gd):
1. the rigged model (and Tripo's own clip GLBs) are copied from --from
   (default: $CROWNS_MODEL_FILES/<id>/), or else downloaded again
   from the recorded Tripo task (free, needs the Tripo network secret);
2. the spec's "rigid" regions are applied (rigid_weapon.py, idempotent);
3. every clip with a "mixamo" name is retargeted again with
   retarget_mixamo.gd from --fbx-dir (default: <--from>/_mixamo/),
   with the same mirror and in-place settings mixamo_set.py used.
The spec is not changed. Without IDs it restores every unit missing a clip GLB.
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

ROOT = Path(__file__).resolve().parents[2]
SPEC = ROOT / "assets/specs/creature_models.json"
# Folder holding the large model files (<id>/ and _mixamo/); no default, set it or pass --from.
PROJECT = Path(os.environ["CROWNS_MODEL_FILES"]) if os.environ.get("CROWNS_MODEL_FILES") else None


def missing(unit: dict) -> list[str]:
    files = {unit["model"]} | {c["model"] for c in unit.get("clips", {}).values() if c.get("model")}
    return sorted(f for f in files if not (ROOT / f).exists())


def fetch(unit: dict, rel: str, source: Path) -> bool:
    """Copy one GLB from the project files, or download it from its Tripo task."""
    dest = ROOT / rel
    dest.parent.mkdir(parents=True, exist_ok=True)
    local = source / unit["id"] / dest.name
    if local.exists():
        shutil.copyfile(local, dest)
        return True
    tripo = unit.get("tripo", {})
    task = None
    if rel == tripo.get("rigged") or rel == unit["model"]:
        task = tripo.get("rig_task")
    elif rel == tripo.get("model"):
        task = tripo.get("model_task")
    else:
        for action, clip in unit.get("clips", {}).items():
            if clip.get("model") == rel and not clip.get("mixamo"):
                task = tripo.get(f"anim_{action}_task")
    if not task:
        return False
    import tripo as api
    client = api.Client(os.environ.get("TRIPO_API_KEY", ""))
    api.download(api.model_url(client.wait(task)), dest)
    return dest.exists()


def retarget(unit: dict, action: str, clip: dict, fbx_dir: Path, lean: bool = False) -> None:
    import mixamo_set as ms
    rigged = ROOT / unit["model"]
    out = ROOT / clip["model"]
    src = fbx_dir / f"{clip['mixamo']}.fbx"
    if not src.exists():
        raise SystemExit(f"{unit['id']}/{action}: missing {src}")
    cls = unit.get("class", "")
    table = {**ms.CLASSES.get(cls, {}), **ms.ALTS.get(cls, {})}
    in_place = table[action][3] if action in table else action == "move"
    unit["_centre"] = ms.mesh_centre(rigged)
    cmd = [os.environ.get("GODOT", "godot"), "--headless", "--path", str(ROOT), "--script",
           "res://tools/assets/retarget_mixamo.gd", "--", str(rigged), str(src), str(out), action]
    cmd += ["in_place"] if in_place else []
    cmd += ["mirror"] if clip.get("mirror") else []
    # Lean: only the clip the live export takes the mesh from keeps it.
    mesh_action = "idle" if "idle" in unit.get("clips", {}) else "move"
    cmd += ["anim_only"] if clip.get("anim_only") or (lean and action != mesh_action) else []
    grip_dir = ms.GRIP_DIR_STAFF if cls.startswith("caster") else ms.GRIP_DIR
    for grip in ms.grips(unit):
        kind = "twist" if grip.get("twist") else "grip"
        to = grip.get("dir", grip_dir)
        cmd.append("%s=%s,%s" % (kind, grip["bone"], ",".join(str(v) for v in grip["axis"] + to)))
    unit.pop("_centre", None)
    done = subprocess.run(cmd, capture_output=True, text=True)
    if done.returncode != 0 or not out.exists():
        print(done.stdout[-1500:], done.stderr[-1500:])
        raise SystemExit(f"{unit['id']}/{action}: retarget failed")


def restore(unit: dict, source: Path, fbx_dir: Path, lean: bool = False) -> str:
    from rigid_weapon import Glb, apply, resolve, skin_info
    import numpy as np
    todo = missing(unit)
    if not todo:
        return "complete"
    mixamo = {c["model"] for c in unit.get("clips", {}).values() if c.get("mixamo")}
    for rel in todo:
        if rel in mixamo:
            continue
        if not fetch(unit, rel, source):
            return f"cannot get {rel}"
    if unit.get("rigid"):
        rigged = Glb(ROOT / unit["model"])
        names, heads = skin_info(rigged)
        pos = rigged.view(rigged.json["meshes"][0]["primitives"][0]["attributes"]["POSITION"]).astype(np.float64)
        regions = resolve(unit, pos, names, heads)
        for rel in todo:
            if rel not in mixamo:
                apply(Glb(ROOT / rel), regions)
    for action, clip in unit.get("clips", {}).items():
        if clip.get("mixamo") and clip["model"] in todo and not (ROOT / clip["model"]).exists():
            retarget(unit, action, clip, fbx_dir, lean)
    left = missing(unit)
    return "restored" if not left else f"still missing {left}"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("ids", nargs="*")
    parser.add_argument("--from", dest="source", type=Path, default=PROJECT)
    parser.add_argument("--fbx-dir", type=Path, default=None)
    parser.add_argument("--lean", action="store_true",
                        help="retarget Mixamo clips as motion only (no meshes) except the one the live "
                             "export takes the mesh from: a fraction of the disk, but not for 2D bakes")
    args = parser.parse_args()
    if args.source is None:
        parser.error("pass --from DIR or set CROWNS_MODEL_FILES")
    if args.fbx_dir is None:
        args.fbx_dir = args.source / "_mixamo"
    spec = json.loads(SPEC.read_text())
    for unit in spec["units"]:
        if args.ids and unit["id"] not in args.ids:
            continue
        if not args.ids and not missing(unit):
            continue
        print(f"{unit['id']}: {restore(unit, args.source, args.fbx_dir, args.lean)}", flush=True)


if __name__ == "__main__":
    main()
