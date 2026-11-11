"""Full-resolution terrain battle scenes, exported by the existing asset build."""
from __future__ import annotations

import hashlib
import json
import shutil
from pathlib import Path

from PIL import Image


def build(root: Path, out_root: Path | None = None) -> dict:
    out = out_root or root
    spec_path = root / "assets/specs/battlefields.json"
    if not spec_path.is_file():
        return {}
    spec = json.loads(spec_path.read_text())
    known = json.loads((root / "data/terrains.json").read_text())["terrains"]
    manifest = {"schema_version": 1, "default_terrain": "grass", "terrains": {}, "assets": {}, "pending": []}
    for asset in spec["assets"]:
        if asset["terrain"] not in known:
            raise ValueError(f"{asset['id']}: unknown terrain")
        source = root / asset["source"]
        if not source.is_file() or "source_sha256" not in asset:
            manifest["pending"].append(asset["id"])
            continue
        digest = hashlib.sha256(source.read_bytes()).hexdigest()
        if digest != asset["source_sha256"]:
            raise ValueError(f"{asset['id']}: battlefield source changed")
        with Image.open(source) as image:
            size = list(image.size)
            if size != asset["size"] or size[0] < 1280 or size[1] < 768:
                raise ValueError(f"{asset['id']}: full-resolution source dimensions changed")
            if image.convert("RGBA").getchannel("A").getextrema() != (255,255):
                raise ValueError(f"{asset['id']}: battlefield must be opaque")
        destination = out / asset["output"]
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination)
        manifest["assets"][asset["id"]] = {
            "id": asset["id"], "terrain": asset["terrain"], "name": asset["name"],
            "path": "res://" + asset["output"], "size": size,
            "horizon_ratio": asset["horizon_ratio"], "source_sha256": digest}
        manifest["terrains"].setdefault(asset["terrain"], []).append(asset["id"])
    destination = out / "assets/battlefields/manifest.json"
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest


def validate(root: Path, out_root: Path | None = None) -> list[str]:
    out = out_root or root
    spec_path = root / "assets/specs/battlefields.json"
    if not spec_path.is_file():
        return []
    path = out / "assets/battlefields/manifest.json"
    if not path.is_file():
        return ["battlefields: manifest missing"]
    manifest = json.loads(path.read_text())
    spec = json.loads(spec_path.read_text())
    errors = []
    if manifest["pending"]:
        errors.append("battlefields: unfinished sources: " + ", ".join(manifest["pending"]))
    if set(manifest["assets"]) != {asset["id"] for asset in spec["assets"]}:
        errors.append("battlefields: asset IDs differ from specification")
    terrains = json.loads((root / "data/terrains.json").read_text())["terrains"]
    if set(manifest["terrains"]) != set(terrains):
        errors.append("battlefields: terrain coverage is incomplete")
    for asset in manifest["assets"].values():
        image = out / asset["path"].removeprefix("res://")
        if not image.is_file() or hashlib.sha256(image.read_bytes()).hexdigest() != asset["source_sha256"]:
            errors.append(asset["id"] + ": export is not the byte-preserved source")
    return errors


def contact_sheet(root: Path) -> Path:
    from PIL import ImageDraw
    manifest = json.loads((root / "assets/battlefields/manifest.json").read_text())
    records = list(manifest["assets"].values())
    width, height, columns = 512, 366, 3
    sheet = Image.new("RGB", (width*columns, ((len(records)+columns-1)//columns)*height), "#202127")
    draw = ImageDraw.Draw(sheet)
    for i, record in enumerate(records):
        x, y = i%columns*width, i//columns*height
        image = Image.open(root / record["path"].removeprefix("res://")).convert("RGB")
        image.thumbnail((width-16,height-36),Image.Resampling.LANCZOS)
        sheet.paste(image,(x+8,y+8))
        draw.text((x+8,y+height-23),record["terrain"]+" / "+record["name"],fill="#dfd0ac")
    target = root / "docs/art/production/battlefields/contact.jpg"
    target.parent.mkdir(parents=True,exist_ok=True)
    sheet.save(target,quality=95)
    return target
