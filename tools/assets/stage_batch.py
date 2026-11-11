"""Stage a planned image sheet through the existing Crowns of Caern asset pipeline.

Usage: python3 tools/assets/stage_batch.py BATCH SOURCE
Plans live in assets/source/batches/BATCH/plan.json. Sources are archival;
new assets remain pending visual review after this mechanical import.
"""
from __future__ import annotations

import json
import shutil
import sys
from pathlib import Path

from PIL import Image
from crowns_of_cinder_assets import production


def stage(root: Path, name: str, source: Path) -> None:
    batch = root / "assets/source/batches" / name
    plan = json.loads((batch / "plan.json").read_text())
    archive = batch / "source.png"
    if archive.exists():
        if archive.read_bytes() != source.read_bytes():
            raise FileExistsError("Refuse to replace archived source")
    else:
        shutil.copyfile(source, archive)
    image = Image.open(archive).convert("RGBA")
    cols, rows = plan["grid"]
    # A sheet may leave trailing cells empty (row-major), never more assets than cells.
    if not 0 < len(plan["assets"]) <= cols * rows:
        raise ValueError("Plan count does not fit the grid")
    generated = root / "assets/source/generated"
    generated.mkdir(parents=True, exist_ok=True)
    for asset in plan["assets"]:
        if (generated / (asset["id"] + ".png")).exists():
            raise FileExistsError("Refuse to replace generated asset: " + asset["id"])
    layout = {"schema_version": 1, "grid": plan["grid"], "source_dimensions": list(image.size),
              "review": "Mechanical grid extraction; design, silhouette and engine review pending", "assets": []}
    for index, asset in enumerate(plan["assets"]):
        col, row = index % cols, index // cols
        rect = [round(col * image.width / cols), round(row * image.height / rows),
                round((col + 1) * image.width / cols), round((row + 1) * image.height / rows)]
        layout["assets"].append(dict(asset, crop_xyxy=rect, keep_components=True))
    (batch / "layout.json").write_text(json.dumps(layout, indent=2) + "\n")
    # Keep complete groups and effects (flocks, rats, town buildings, smoke).
    # The normal build still crops alpha and applies native sizing/outlines.
    if plan["category"] == "ground":
        for asset in layout["assets"]:
            image.crop(asset["crop_xyxy"]).save(generated / (asset["id"] + ".png"))
    else:
        production.import_sheet(root, batch)
    for asset in layout["assets"]:
        dest = generated / (asset["id"] + ".png")
        dest.with_suffix(".json").write_text(json.dumps({
            "schema_version": 1, "provider": plan.get("provider", "ChatGPT image_gen"), "batch": name,
            "source_sheet": str(archive.relative_to(root)), "source_sheet_sha256": production.sha256(archive),
            "source_sha256": production.sha256(dest), "crop_xyxy": asset["crop_xyxy"],
            "prompt_file": str((batch / "prompt.txt").relative_to(root)),
            "conditioning": plan.get("conditioning", "Approved Reignem Concord sheet; neutral sheets also conditioned on approved Hollow sheet"),
            "native_size": asset["size"], "quality_status": "pending_visual_review",
            "isolation": "Full grid cell retained, including groups and disconnected effects"
        }, indent=2) + "\n")
    if plan.get("spec_file"):
        path = root / "assets/specs" / plan["spec_file"]
        doc = json.loads(path.read_text())
        by_id = {asset["id"]: asset for asset in doc["assets"]}
        for asset in plan["assets"]:
            spec = by_id[asset["id"]]
            old_size = spec.get("size", doc.get("defaults", {}).get("size"))
            if "flag" in spec:
                spec["flag"] = [round(spec["flag"][i] * asset["size"][i] / old_size[i]) for i in range(2)]
            spec.update(size=asset["size"], map_scale=asset["map_scale"], generated_palette="preserve")
        path.write_text(json.dumps(doc, indent=2) + "\n")
    print(f"Staged {len(plan['assets'])} assets from {name}; visual review pending")


if __name__ == "__main__":
    stage(Path(__file__).resolve().parents[2], sys.argv[1], Path(sys.argv[2]))
