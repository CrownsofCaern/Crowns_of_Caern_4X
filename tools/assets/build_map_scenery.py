"""Build the additive map-editor art library using the existing sprite processor.

Run with Python + Pillow + numpy. Does not change the live game's atlases.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

try:
    from crowns_of_cinder_assets import postprocess
    from crowns_of_cinder_assets.palette import Palette
except ModuleNotFoundError as error:
    if error.name != "crowns_of_cinder_assets":
        raise
    # Older editor branches still use the package name before the rename.
    from reignem_assets import postprocess
    from reignem_assets.palette import Palette

ROOT = Path(__file__).resolve().parents[2]


def build(root: Path = ROOT) -> None:
    spec = json.loads((root / "assets/specs/map_scenery.json").read_text())
    palette = Palette.load(root / "assets/specs/palette.json")
    entries = {}
    preview = Image.new("RGB", (960, 5 * 236), "#242225")
    draw = ImageDraw.Draw(preview)
    seen = set()
    for index, asset in enumerate(spec["assets"]):
        sid = asset["id"]
        assert sid not in seen, sid
        seen.add(sid)
        source = root / asset["source"]
        with Image.open(source) as raw:
            if asset["category"] == "terrain":
                image = postprocess.connected_terrain_field(raw, tuple(asset["size"]))
                image = postprocess.shared_terrain_edges([image])[0]
            else:
                raw = raw.convert("RGBA")
                assert raw.getextrema()[3][0] == 0, f"{sid}: missing generated transparency"
                image = postprocess.process_generated(raw, dict(
                    asset, generated_palette="preserve", outline=True,
                    outline_weight=1, export_scale=1), palette)
        assert image.size == tuple(asset["size"]), sid
        pixels = np.array(image)
        assert set(np.unique(pixels[:, :, 3])) <= {0, 255}, sid
        if asset["category"] == "terrain":
            assert (pixels[0] == pixels[-1]).all(), sid
            assert (pixels[:, 0] == pixels[:, -1]).all(), sid
        else:
            assert image.getbbox() is not None, sid
        output = root / asset["output"]
        output.parent.mkdir(parents=True, exist_ok=True)
        image.save(output, optimize=True)
        entries[sid] = {
            "name": asset["name"], "category": asset["category"],
            "texture": "res://" + asset["output"], "size": asset["size"],
            "footprint": asset["footprint"], "biome": asset["biome"],
            "anchor": [0, 0] if asset["category"] == "terrain" else [image.width // 2, image.height - 1],
            "passable": asset["passable"],
            "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
            "quality_status": "native_size_reviewed_engine_review_pending",
        }
        x, y = (index % 4) * 240, (index // 4) * 236
        if asset["category"] == "terrain":
            # A 4x4 repeat reveals borders more clearly than an isolated tile.
            for ty in range(4):
                for tx in range(4):
                    preview.paste(image, (x + 40 + tx * 40, y + 8 + ty * 40), image)
        else:
            preview.paste(image, (x + (240 - image.width) // 2, y + 176 - image.height), image)
        draw.text((x + 10, y + 184), asset["name"], fill="#e3d6b5")
        draw.text((x + 10, y + 202), f'{image.width}x{image.height} px / {asset["footprint"][0]}x{asset["footprint"][1]} tiles', fill="#a9a3a0")
    manifest = {"schema_version": 1, "tile_size": spec["tile_size"],
                "placement_note": spec["placement_note"], "assets": entries}
    (root / "assets/map_scenery/manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    contact = root / "docs/art/production/map-expansion-001-contact.png"
    contact.parent.mkdir(parents=True, exist_ok=True)
    preview.save(contact)
    print(f"Built and validated {len(entries)} map assets; contact: {contact}")


if __name__ == "__main__":
    build()
