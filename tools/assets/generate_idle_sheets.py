"""Generate, review and approve idle/attack sheets (assets/specs/creature_idle_animations.json).

  python3 tools/assets/generate_idle_sheets.py prompts               # write every group's prompt file
  python3 tools/assets/generate_idle_sheets.py generate GROUP [...]  # call the image API for sheets A and B (OPENAI_API_KEY)
  python3 tools/assets/generate_idle_sheets.py review GROUP [...]    # review sheet + GIF under /tmp/idle_review
  python3 tools/assets/generate_idle_sheets.py approve GROUP [...]   # record the source hash, then run pipeline build
  python3 tools/assets/generate_idle_sheets.py import FILE [...]     # file sheets made by hand (matched to groups)
  python3 tools/assets/generate_idle_sheets.py status

The image call is the same reference-conditioned ChatGPT image model that
made the move/attack sheets: the group's reference strip (its four stills,
left to right) goes in as the image, the prompt from idle_animations.prompt
asks for sheet A (idle + walk, 7x4) and sheet B (attack, 6x4) on transparency. OPENAI_IMAGE_MODEL picks the model
(default gpt-image-1). A sheet is only used by the game after `approve`.
"""
from __future__ import annotations

import base64
import hashlib
import json
import os
import sys
import urllib.request
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from crowns_of_cinder_assets import animations, idle_animations  # noqa: E402
from PIL import Image  # noqa: E402

BATCH = ROOT / "assets/source/batches/creature-idle-001"
SPEC = ROOT / idle_animations.SPEC


def load() -> dict:
    return json.loads(SPEC.read_text())


def save(spec: dict) -> None:
    SPEC.write_text(json.dumps(spec, indent=1) + "\n")


def group(spec: dict, gid: str) -> dict:
    for g in spec["groups"]:
        if g["id"] == gid:
            return g
    raise SystemExit(f"unknown group {gid}")


def write_prompts(spec: dict) -> None:
    BATCH.mkdir(parents=True, exist_ok=True)
    for g in spec["groups"]:
        for k in idle_animations.SHEETS:
            (BATCH / f"{g['id']}-{k.lower()}-prompt.txt").write_text(idle_animations.prompt(g, k) + "\n")
    print(f"wrote {len(spec['groups'])} prompts to {BATCH.relative_to(ROOT)}")


def _multipart(fields: dict, files: dict) -> tuple[bytes, str]:
    boundary = uuid.uuid4().hex
    out = bytearray()
    for k, v in fields.items():
        out += f"--{boundary}\r\nContent-Disposition: form-data; name=\"{k}\"\r\n\r\n{v}\r\n".encode()
    for k, (name, data) in files.items():
        out += (f"--{boundary}\r\nContent-Disposition: form-data; name=\"{k}\"; filename=\"{name}\"\r\n"
                "Content-Type: image/png\r\n\r\n").encode() + data + b"\r\n"
    out += f"--{boundary}--\r\n".encode()
    return bytes(out), boundary


def generate(spec: dict, gid: str, sheet_key: str) -> None:
    key = os.environ.get("OPENAI_API_KEY")
    if not key:
        raise SystemExit("OPENAI_API_KEY is not set")
    g = group(spec, gid)
    model = os.environ.get("OPENAI_IMAGE_MODEL", "gpt-image-1")
    prompt = idle_animations.prompt(g, sheet_key)
    info = g["sheets"][sheet_key]
    reference = ROOT / g["reference"]
    body, boundary = _multipart(
        {"model": model, "prompt": prompt, "size": "1536x1024", "background": "transparent",
         "quality": "high", "output_format": "png", "n": "1"},
        {"image": (reference.name, reference.read_bytes())})
    request = urllib.request.Request("https://api.openai.com/v1/images/edits", data=body, method="POST", headers={
        "Authorization": f"Bearer {key}", "Content-Type": f"multipart/form-data; boundary={boundary}"})
    with urllib.request.urlopen(request, timeout=600) as response:
        result = json.loads(response.read())
    png = base64.b64decode(result["data"][0]["b64_json"])
    BATCH.mkdir(parents=True, exist_ok=True)
    source = ROOT / info["source"]
    _archive(source, f"{gid}-{sheet_key.lower()}")
    source.write_bytes(png)
    _record(g, sheet_key, source, f"OpenAI Images API ({model}, images/edits)", {"usage": result.get("usage", {})})
    print(f"{gid} {sheet_key}: generated {source.relative_to(ROOT)}")


def _archive(source: Path, stem: str) -> None:
    """Keeps an earlier take for comparison before a new one replaces it."""
    if source.exists():
        # Keep earlier takes for comparison; the newest becomes the source.
        n = 1
        while (BATCH / "revisions" / f"{stem}-take{n}.png").exists():
            n += 1
        (BATCH / "revisions").mkdir(exist_ok=True)
        source.rename(BATCH / "revisions" / f"{stem}-take{n}.png")


def _record(g: dict, sheet_key: str, source: Path, provider: str, extra: dict) -> None:
    info = g["sheets"][sheet_key]
    (BATCH / f"{g['id']}-{sheet_key.lower()}-source.json").write_text(json.dumps({
        "provider": provider, "generation_status": "generated", "quality_status": "idle_candidate",
        "sheet": sheet_key, "source": info["source"], "source_sha256": animations.digest(source),
        "prompt_file": f"assets/source/batches/creature-idle-001/{g['id']}-{sheet_key.lower()}-prompt.txt",
        "conditioning": [g["reference"]], "grid": info["grid"], "units": [u["id"] for u in g["units"]], **extra},
        indent=2) + "\n")


def _poses(g: dict, key: str) -> list:
    """Registered poses per unit row of one sheet: [[still, pose1, ...], ...]."""
    info = g["sheets"][key]
    sheet = Image.open(ROOT / info["source"]).convert("RGBA")
    columns, rows = info["grid"]
    row_data, row_warnings = animations.extract_rows(sheet, rows)
    out, notes = [], [f"{key}: {w}" for w in row_warnings]
    for row, unit in enumerate(g["units"]):
        reference = Image.open(ROOT / unit["reference_source"]).convert("RGBA")
        cells, extraction = animations.extract_cells(sheet, row, columns, rows, row_data)
        frames, qc = animations.register(cells, reference)
        notes += [f"{key} {unit['id']}: {x}" for x in qc["warnings"] + extraction["warnings"]]
        rest = Image.new("RGBA", animations.SIZE)
        rest.paste(reference, (96, 80))
        out.append([rest, *frames])
    return out, notes


def review(spec: dict, gid: str, out: Path) -> None:
    """Frame boards per sheet and, per unit, idle / walk / attack GIFs."""
    from PIL import ImageDraw
    g = group(spec, gid)
    out.mkdir(parents=True, exist_ok=True)
    w, h = animations.SIZE
    poses, notes = {}, []
    for key in idle_animations.SHEETS:
        if not (ROOT / g["sheets"][key]["source"]).exists():
            notes.append(f"sheet {key} missing")
            continue
        poses[key], n = _poses(g, key)
        notes += n
        board = Image.new("RGBA", ((idle_animations.SHEETS[key] + 1) * w, len(g["units"]) * h), (52, 46, 38, 255))
        for row, unit in enumerate(g["units"]):
            for c, f in enumerate(poses[key][row]):
                board.alpha_composite(f, (c * w, row * h))
            ImageDraw.Draw(board).text((6, row * h + 4), unit["id"], fill=(240, 220, 160, 255))
        board.convert("RGB").save(out / f"{gid}_{key}_frames.png")
    for row, unit in enumerate(g["units"]):
        clips = []
        if "A" in poses:
            a = poses["A"][row]
            clips += [("idle", [a[i] for i in idle_animations.IDLE_COLUMNS], idle_animations.IDLE_MS),
                      ("walk", [a[i] for i in idle_animations.MOVE_COLUMNS], idle_animations.MOVE_MS)]
        if "B" in poses:
            b = poses["B"][row]
            rest = poses["A"][row][1] if "A" in poses else b[0]
            clips.append(("attack", [rest, *b[1:7], rest], [400, *idle_animations.ATTACK_MS]))
        for name, frames, ms in clips:
            seq = []
            for f in frames:
                bg = Image.new("RGBA", animations.SIZE, (52, 46, 38, 255))
                bg.alpha_composite(f)
                seq.append(bg.convert("RGB").resize((w * 2, h * 2), Image.NEAREST))
            seq[0].save(out / f"{unit['id']}_{name}.gif", save_all=True, append_images=seq[1:], duration=ms, loop=0)
    (out / f"{gid}_notes.txt").write_text("\n".join(notes) + "\n")
    print(f"{gid}: review in {out} ({len(notes)} notes)")


def _signature(image) -> "np.ndarray":
    """Coarse colour layout of a figure, for matching sheets to references."""
    import numpy as np
    box = image.getchannel("A").point(lambda a: 255 if a >= 96 else 0).getbbox()
    if box is None:
        return np.zeros(8 * 8 * 3)
    crop = image.crop(box).convert("RGBA")
    flat = Image.new("RGBA", crop.size, (0, 0, 0, 255))
    flat.alpha_composite(crop)
    return np.asarray(flat.convert("RGB").resize((8, 8), Image.BILINEAR), dtype=float).ravel()


def columns_of(sheet, rows: int = 4) -> int:
    """How many figure columns a sheet has (6 or 7). Cutting with the right
    count gives one whole figure per cell; the wrong count leaves cells with
    slices of two figures, whose ink spreads across the whole cell."""
    import numpy as np
    bands = animations.extract_rows(sheet, rows)[0]
    best, score = 7, None
    for cols in sorted(idle_animations.SHEETS.values(), reverse=True):
        spread = []
        for row in range(rows):
            cells, _ = animations.extract_cells(sheet, row, cols, rows, bands)
            for cell in cells:
                ink = (np.asarray(cell.getchannel("A")) >= 96).sum(axis=0)
                xs = np.nonzero(ink >= 2)[0]
                # Share of the cell width between the outer 10% of ink.
                if len(xs):
                    lo, hi = np.percentile(xs, [10, 90])
                    spread.append((hi - lo) / (sheet.width / cols))
        value = float(np.mean(spread)) if spread else 9.0
        if score is None or value < score:
            best, score = cols, value
    return best


def match(spec: dict, sheet_path: Path) -> tuple[str, str, float]:
    """(group, sheet letter, cost): the group whose stills best match the
    sheet's first column, and A or B from the number of columns."""
    import numpy as np
    sheet = Image.open(sheet_path).convert("RGBA")
    cols = columns_of(sheet)
    key = [k for k, n in idle_animations.SHEETS.items() if n == cols][0]
    best = ("", key, float("inf"))
    cache = {}
    for g in spec["groups"]:
        rows = len(g["units"])
        if rows not in cache:
            cache[rows] = animations.extract_rows(sheet, rows)[0]
        cost = 0.0
        for row, unit in enumerate(g["units"]):
            cells, _ = animations.extract_cells(sheet, row, cols, rows, cache[rows])
            ref = Image.open(ROOT / unit["reference_source"]).convert("RGBA")
            cost += float(np.abs(_signature(cells[0]) - _signature(ref)).mean())
        if cost < best[2]:
            best = (g["id"], key, cost)
    return best


def import_sheet(spec: dict, path: Path) -> None:
    gid, key, cost = match(spec, path)
    g = group(spec, gid)
    target = ROOT / g["sheets"][key]["source"]
    target.parent.mkdir(parents=True, exist_ok=True)
    _archive(target, f"{gid}-{key.lower()}")
    Image.open(path).convert("RGBA").save(target)
    _record(g, key, target, "ChatGPT image_gen (by hand, chatgpt_idle_task.md)", {"match_cost": round(cost, 2)})
    print(f"{path.name} -> {gid} {key} (match cost {cost:.1f})")


def approve(spec: dict, gid: str) -> None:
    g = group(spec, gid)
    for key, info in g["sheets"].items():
        info["source_sha256"] = animations.digest(ROOT / info["source"])
    save(spec)
    print(f"{gid}: approved; run python3 tools/assets/pipeline.py build")


def main() -> None:
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    spec = load()
    cmd, ids = sys.argv[1], sys.argv[2:]
    if cmd == "prompts":
        write_prompts(spec)
    elif cmd == "status":
        for g in spec["groups"]:
            states = []
            for key, info in g["sheets"].items():
                state = "approved" if "source_sha256" in info else ("generated" if (ROOT / info["source"]).exists() else "pending")
                states.append(f"{key}:{state}")
            print(f"{g['id']:18} {' '.join(states):30} {' '.join(u['id'] for u in g['units'])}")
    else:
        for gid in ids:
            if cmd == "generate":
                for key in idle_animations.SHEETS:
                    generate(spec, gid, key)
            elif cmd == "review":
                review(spec, gid, Path(os.environ.get("IDLE_REVIEW_DIR", "/tmp/idle_review")) / gid)
            elif cmd == "import":
                import_sheet(spec, Path(gid))
            elif cmd == "approve":
                approve(spec, gid)
                spec = load()
            else:
                raise SystemExit(__doc__)


if __name__ == "__main__":
    main()
