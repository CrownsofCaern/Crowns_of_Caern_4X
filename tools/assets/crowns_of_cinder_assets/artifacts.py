"""Build individual inventory sprites from the artifact source artwork."""
from __future__ import annotations

import json
from pathlib import Path

from PIL import Image

from . import postprocess
from .palette import Palette


def build(root: Path, out_root: Path | None = None) -> None:
    out = out_root or root
    definitions = json.loads((root / "data/artifacts.json").read_text())["artifacts"]
    source_dir = root / "assets/source/artifacts-001"
    manifest = json.loads((source_dir / "manifest.json").read_text())
    sources = {entry["id"]: source_dir / entry["source"] for entry in manifest["assets"]}
    # The equipment artwork library (equipment-002) supplies the later artifacts.
    library = root / "assets/source/equipment-002"
    if (library / "manifest.json").is_file():
        for entry in json.loads((library / "manifest.json").read_text())["assets"]:
            sources.setdefault(entry["id"], library / entry["source"])
    palette = Palette.load(root / "assets/specs/palette.json")
    destination = out / "assets/artifacts"
    destination.mkdir(parents=True, exist_ok=True)
    spec = {"size": [64, 64], "anchor": "center", "outline": True,
            "outline_weight": 1, "generated_palette": "preserve"}
    for artifact_id in definitions:
        source = sources.get(artifact_id, source_dir / (artifact_id + ".png"))
        if not source.is_file():
            raise FileNotFoundError(f"Missing artifact source: {artifact_id}")
        with Image.open(source) as raw:
            image = postprocess.prepare_generated(raw, spec, palette)
        image = postprocess.finish(image, spec, palette)
        image.save(destination / (artifact_id + ".png"), optimize=True)
