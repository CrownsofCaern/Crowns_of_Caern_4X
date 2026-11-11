"""Preserve full-resolution menu artwork in the existing asset build."""
from __future__ import annotations
import hashlib
import json
import shutil
from pathlib import Path
from PIL import Image


def build(root: Path, out_root: Path | None = None) -> dict:
    out = out_root or root
    spec_path = root / "assets/specs/menu_art.json"
    if not spec_path.is_file():
        return {}
    spec = json.loads(spec_path.read_text())
    manifest = {"schema_version": 1, "title": spec["title"], "assets": {}}
    for asset in spec["assets"]:
        source = root / asset["source"]
        with Image.open(source) as image:
            size = list(image.size)
        digest = hashlib.sha256(source.read_bytes()).hexdigest()
        if size != asset["size"] or digest != asset["source_sha256"]:
            raise ValueError(f"{asset['id']}: menu source dimensions/hash differ from specification")
        destination = out / asset["output"]
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination)
        manifest["assets"][asset["id"]] = {
            "path": "res://" + asset["output"], "size": size,
            "crop_alpha": bool(asset.get("crop_alpha", False)), "source_sha256": digest}
    destination = out / "assets/menus/manifest.json"
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest
