"""Bake rigged 3D models (GLB) into pixel-art battle clips.

  python3 tools/assets/bake_models.py clips MODEL.glb           # list a model's animation clips
  python3 tools/assets/bake_models.py import ID FILE.glb [...] [--map move=Walk,attack=Bite]
  python3 tools/assets/bake_models.py render ID [--review DIR]  # render + pixelate into the bake sheet
  python3 tools/assets/bake_models.py approve ID [...]          # record the sheet hash, then run pipeline build
  python3 tools/assets/bake_models.py status

`import` files models downloaded by hand (for example from the Tripo website:
one GLB with several clips, or one GLB per clip) under assets/source/models/ID/
and maps their clips to idle/move/attack/death by name (`--map` overrides).
Units live in assets/specs/creature_models.json (see crowns_of_cinder_assets/
model_animations.py). `render` runs Godot headless (GODOT, default `godot`;
under xvfb-run when there is no display) with tools/assets/render_model.gd,
then turns the frames into pixel art on the master palette: one scale for the
whole unit (the rest pose matches the drawn still's height, or `height_px`),
the rest pose's feet on the battle anchor, box downscale, hard alpha, palette
snap and the 1 px outline. It writes the bake sheet next to the model and a
review board + GIF (side by side with the drawn still) under --review. A new
render is pending until `approve`; only then does `pipeline.py build` use it.
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from crowns_of_cinder_assets import animations, model_animations  # noqa: E402
from crowns_of_cinder_assets.palette import Palette  # noqa: E402
from crowns_of_cinder_assets.postprocess import outline  # noqa: E402
from PIL import Image, ImageDraw  # noqa: E402

SPEC = ROOT / model_animations.SPEC
ALPHA_CUT = 110


def load() -> dict:
    return model_animations.load_spec(ROOT)


def save(spec: dict) -> None:
    SPEC.parent.mkdir(parents=True, exist_ok=True)
    SPEC.write_text(json.dumps(spec, indent=2) + "\n")


def unit_of(spec: dict, uid: str) -> dict:
    for unit in spec.get("units", []):
        if unit["id"] == uid:
            return unit
    raise SystemExit(f"{uid}: not in {SPEC.relative_to(ROOT)}")


def godot_command(args: list[str]) -> list[str]:
    godot = os.environ.get("GODOT", "godot")
    cmd = [godot, "--path", str(ROOT), "--rendering-driver", "opengl3", "--script", "res://tools/assets/render_model.gd", "--", *args]
    if sys.platform.startswith("linux") and not os.environ.get("DISPLAY") and shutil.which("xvfb-run"):
        cmd = ["xvfb-run", "-a", *cmd]
    return cmd


def job_for(unit: dict) -> dict:
    """The render job for one unit: actions in sheet order with absolute model paths."""
    view = unit.get("view", {})
    actions = {}
    for action, count in model_animations.layout(unit):
        clip = dict(unit["clips"][action])
        model = clip.get("model", unit.get("model"))
        if not model:
            raise SystemExit(f"{unit['id']}/{action}: no model")
        clip["model"] = str((ROOT / model).resolve())
        clip["frames"] = count
        clip.setdefault("loop", model_animations.LOOPS[action])
        actions[action] = clip
    if not actions:
        raise SystemExit(f"{unit['id']}: no clips listed")
    job = {"actions": actions, **{k: v for k, v in view.items()}}
    if unit.get("weapon"):
        job["weapon"] = unit["weapon"]
    if unit.get("hold"):
        job["hold"] = unit["hold"]
    if unit.get("wings"):
        job["wings"] = unit["wings"]
    if unit.get("throw"):
        job["throw"] = unit["throw"]
    if unit.get("lance"):
        job["lance"] = unit["lance"]
    return job


# --- pixel pass ------------------------------------------------------------

def visible_box(img: Image.Image) -> tuple[int, int, int, int] | None:
    return img.getchannel("A").point(lambda v: 255 if v > ALPHA_CUT else 0).getbbox()


def reference_height(unit: dict) -> int:
    if "height_px" in unit.get("view", {}):
        return int(unit["view"]["height_px"])
    still = ROOT / f"assets/build/creature/creature_{unit['id']}.png"
    if still.is_file():
        box = visible_box(Image.open(still).convert("RGBA"))
        if box:
            return box[3] - box[1]
    return 120


def placement(rest: Image.Image, height_px: int, shift_x: int = 0) -> tuple[float, int, int]:
    """Scale and offset that put the rest pose `height_px` tall with its feet
    on the battle anchor; shared by every frame of the unit."""
    box = visible_box(rest)
    if box is None:
        raise ValueError("rest pose renders empty; check the model, yaw and camera")
    scale = height_px / max(1, box[3] - box[1])
    cx = (box[0] + box[2]) / 2 * scale
    dx = round(animations.ANCHOR[0] + shift_x - cx)
    dy = round(animations.ANCHOR[1] - box[3] * scale)
    return scale, dx, dy


def pixelate(raw: Image.Image, scale: float, dx: int, dy: int, palette: Palette) -> Image.Image:
    """One rendered frame as a 320x256 battle cell on the master palette."""
    w, h = max(1, round(raw.width * scale)), max(1, round(raw.height * scale))
    small = raw.convert("RGBA").resize((w, h), Image.Resampling.BOX)
    cell = Image.new("RGBA", animations.SIZE)
    cell.paste(small, (dx, dy))
    alpha = cell.getchannel("A").point(lambda v: 255 if v > ALPHA_CUT else 0)
    # Un-premultiply the soft edge before snapping so rims do not go muddy.
    solid = Image.new("RGBA", animations.SIZE)
    solid.paste(cell.convert("RGB"), (0, 0), alpha)
    flat = palette.quantize(solid)
    return outline(flat, palette.outline)


def assemble(unit: dict, frames: dict[str, list[Image.Image]], palette: Palette) -> Image.Image:
    rows = model_animations.layout(unit)
    first = frames[rows[0][0]][0]
    scale, dx, dy = placement(first, reference_height(unit), int(unit.get("view", {}).get("shift_x", 0)))
    size = animations.SIZE
    sheet = Image.new("RGBA", (max(n for _, n in rows) * size[0], len(rows) * size[1]))
    for row, (action, count) in enumerate(rows):
        if len(frames.get(action, [])) != count:
            raise ValueError(f"{unit['id']}/{action}: rendered {len(frames.get(action, []))} frames, expected {count}")
        for col, raw in enumerate(frames[action]):
            sheet.paste(pixelate(raw, scale, dx, dy, palette), (col * size[0], row * size[1]))
    return sheet


def review(unit: dict, sheet: Image.Image, out: Path) -> None:
    """Review board (sheet at 2x beside the drawn still) and one GIF per action."""
    out.mkdir(parents=True, exist_ok=True)
    size = animations.SIZE
    rows = model_animations.layout(unit)
    still_path = ROOT / f"assets/build/creature/creature_{unit['id']}.png"
    bg = (30, 28, 34, 255)
    board = Image.new("RGBA", (size[0] + sheet.width, max(sheet.height, size[1]) + 24), bg)
    draw = ImageDraw.Draw(board)
    if still_path.is_file():
        still = Image.open(still_path).convert("RGBA")
        cell = Image.new("RGBA", size)
        cell.paste(still, (animations.ANCHOR[0] - 64, animations.ANCHOR[1] - 127))
        board.alpha_composite(cell, (0, 24))
        draw.text((6, 6), "drawn still", fill=(220, 200, 170))
    board.alpha_composite(sheet, (size[0], 24))
    for row, (action, _) in enumerate(rows):
        draw.text((size[0] + 6, 30 + row * size[1]), action, fill=(220, 200, 170))
    board.resize((board.width * 2, board.height * 2), Image.Resampling.NEAREST).save(out / f"{unit['id']}_board.png")
    for row, (action, count) in enumerate(rows):
        ms = int(unit["clips"][action].get("ms", model_animations.DEFAULT_MS[action]))
        cells = []
        for col in range(count):
            frame = Image.new("RGBA", size, bg)
            frame.alpha_composite(sheet.crop((col * size[0], row * size[1], (col + 1) * size[0], (row + 1) * size[1])))
            cells.append(frame.convert("RGB").resize((size[0] * 2, size[1] * 2), Image.Resampling.NEAREST))
        cells[0].save(out / f"{unit['id']}_{action}.gif", save_all=True, append_images=cells[1:], duration=ms, loop=0)


# --- commands --------------------------------------------------------------

def cmd_clips(model: str) -> None:
    print("\n".join(list_clips(Path(model))))


# Clip names that feed each battle action, tried in order (case-insensitive substrings).
CLIP_WORDS = {
    "idle": ("idle", "breath", "stand", "rest"),
    "move": ("walk", "run", "move", "trot", "gallop", "fly"),
    "attack": ("attack", "slash", "bite", "thrust", "strike", "stab", "swing", "punch", "claw", "shoot", "cast"),
    "death": ("death", "die", "dying", "dead", "fall", "collapse"),
}


def map_clips(available: dict[str, list[str]], overrides: dict[str, str]) -> dict[str, dict]:
    """Battle action -> {"model", "clip"} from {model path: [clip names]}."""
    found: dict[str, dict] = {}
    for action, words in CLIP_WORDS.items():
        if action in overrides:
            wanted = overrides[action].lower()
            matches = [(m, c) for m, clips in available.items() for c in clips if c.lower() == wanted]
            if not matches:
                raise SystemExit(f"--map {action}={overrides[action]}: no such clip")
            found[action] = {"model": matches[0][0], "clip": matches[0][1]}
            continue
        for word in words:
            matches = [(m, c) for m, clips in available.items() for c in clips if word in c.lower()]
            if matches:
                found[action] = {"model": matches[0][0], "clip": matches[0][1]}
                break
    return found


def list_clips(model: Path) -> list[str]:
    result = subprocess.run(godot_command(["--list", str(model.resolve())]), capture_output=True, text=True)
    lines = [line for line in result.stdout.splitlines() if line.startswith("{")]
    if result.returncode != 0 or not lines:
        raise SystemExit(f"{model}: Godot could not read it\n" + result.stderr[-2000:])
    return list(json.loads(lines[-1])["clips"])


def cmd_import(uid: str, files: list[str], mapping: str) -> None:
    spec = load()
    units = spec.setdefault("units", [])
    unit = next((u for u in units if u["id"] == uid), None)
    if unit is None:
        unit = {"id": uid}
        units.append(unit)
    folder = ROOT / "assets/source/models" / uid
    folder.mkdir(parents=True, exist_ok=True)
    available: dict[str, list[str]] = {}
    for f in files:
        src = Path(f)
        if src.suffix.lower() != ".glb":
            raise SystemExit(f"{src}: export GLB (binary glTF), not {src.suffix}")
        dest = folder / src.name
        if src.resolve() != dest.resolve():
            shutil.copyfile(src, dest)
        available[str(dest.relative_to(ROOT))] = list_clips(dest)
    overrides = dict(pair.split("=", 1) for pair in mapping.split(",") if "=" in pair)
    mapped = map_clips(available, overrides)
    unit["model"] = next(iter(available))
    clips = unit.setdefault("clips", {})
    for action, choice in mapped.items():
        clips[action] = {**clips.get(action, {"frames": {"idle": 6, "move": 8, "attack": 8, "death": 7}[action]}), **choice}
    unit.setdefault("bake", {}).pop("sheet_sha256", None)
    save(spec)
    for model, names in available.items():
        print(f"{model}: {', '.join(names) or 'no clips'}")
    for action in model_animations.ACTIONS:
        c = clips.get(action)
        print(f"  {action:7} {c['clip'] + ' (' + Path(c['model']).name + ')' if c else '- (keeps the drawn clip)'}")


def cmd_render(uid: str, review_dir: Path, keep: Path | None) -> None:
    spec = load()
    unit = unit_of(spec, uid)
    work = Path(keep or tempfile.mkdtemp(prefix=f"bake_{uid}_"))
    work.mkdir(parents=True, exist_ok=True)
    job_path = work / "job.json"
    job_path.write_text(json.dumps(job_for(unit), indent=2))
    result = subprocess.run(godot_command([str(job_path), str(work / "raw")]), capture_output=True, text=True)
    if result.returncode != 0 or not (work / "raw/render.json").is_file():
        raise SystemExit("render failed:\n" + (result.stderr or result.stdout)[-3000:])
    frames = {action: [Image.open(work / f"raw/{action}_{i}.png").convert("RGBA") for i in range(count)]
              for action, count in model_animations.layout(unit)}
    palette = Palette.load(ROOT / "assets/specs/palette.json")
    sheet = assemble(unit, frames, palette)
    destination = ROOT / model_animations.sheet_path(unit)
    destination.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(destination, optimize=True)
    unit.setdefault("bake", {})["sheet"] = model_animations.sheet_path(unit)
    if unit["bake"].get("sheet_sha256") != animations.digest(destination):
        unit["bake"].pop("sheet_sha256", None)   # a changed sheet needs a new review
    save(spec)
    review(unit, sheet, review_dir)
    print(f"{uid}: sheet {model_animations.sheet_path(unit)}, review in {review_dir}")
    if keep is None:
        shutil.rmtree(work, ignore_errors=True)


def cmd_approve(ids: list[str]) -> None:
    spec = load()
    for uid in ids:
        unit = unit_of(spec, uid)
        path = ROOT / model_animations.sheet_path(unit)
        if not path.is_file():
            raise SystemExit(f"{uid}: no bake sheet yet; run render first")
        unit.setdefault("bake", {})["sheet"] = model_animations.sheet_path(unit)
        unit["bake"]["sheet_sha256"] = animations.digest(path)
        print(f"{uid}: approved {unit['bake']['sheet_sha256'][:12]}")
    save(spec)


def cmd_status() -> None:
    for unit in load().get("units", []):
        sheet = ROOT / model_animations.sheet_path(unit)
        state = "approved" if model_animations.approved(unit) else ("rendered" if sheet.is_file() else "pending")
        actions = ", ".join(f"{a} {n}" for a, n in model_animations.layout(unit))
        print(f"{unit['id']:24} {state:9} {actions}")


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("clips").add_argument("model")
    imp = sub.add_parser("import")
    imp.add_argument("id")
    imp.add_argument("files", nargs="+")
    imp.add_argument("--map", default="", help="action=Clip pairs, comma separated")
    render = sub.add_parser("render")
    render.add_argument("id")
    render.add_argument("--review", type=Path, default=Path(tempfile.gettempdir()) / "model_bake_review")
    render.add_argument("--keep", type=Path, help="keep the raw renders in this folder")
    sub.add_parser("approve").add_argument("ids", nargs="+")
    sub.add_parser("status")
    args = parser.parse_args(argv)
    if args.cmd == "clips":
        cmd_clips(args.model)
    elif args.cmd == "import":
        cmd_import(args.id, args.files, args.map)
    elif args.cmd == "render":
        cmd_render(args.id, args.review, args.keep)
    elif args.cmd == "approve":
        cmd_approve(args.ids)
    else:
        cmd_status()


if __name__ == "__main__":
    main()
