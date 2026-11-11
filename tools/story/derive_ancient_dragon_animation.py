"""Interim animation sheet for the ancient dragon (Karzhaloth), derived from the
primordial wyrm's approved animation row (wilds-08) with the same hue remap as
tools/story/derive_ancient_dragon.py. Writes the one-unit group's source sheet
and reference into assets/source/batches/six-eyes-story-001/ and keeps the
group's hashes in assets/specs/creature_animations.json in step.

    python3 tools/story/derive_ancient_dragon_animation.py && python3 tools/assets/pipeline.py build
"""
import hashlib, json, os, sys
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools/assets"))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from crowns_of_cinder_assets.animations import extract_cells  # noqa: E402
from derive_ancient_dragon import remap  # noqa: E402

BATCH = "assets/source/batches/six-eyes-story-001"
WYRM_SHEET = os.path.join(ROOT, "assets/source/batches/creature-animation-001/wilds-08-source.png")
WYRM_REF = os.path.join(ROOT, "assets/source/batches/creature-animation-001/references/creature_primordial_wyrm.png")
SPEC = os.path.join(ROOT, "assets/specs/creature_animations.json")
GROUP = "six-eyes-story-01"


def recolor(img: Image.Image) -> Image.Image:
    img = img.convert("RGBA")
    out = Image.new("RGBA", img.size)
    px, po = img.load(), out.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = px[x, y]
            po[x, y] = (0, 0, 0, 0) if a == 0 else remap(r, g, b) + (a,)
    return out


def sha(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()


def main():
    spec = json.load(open(SPEC))
    wilds = [g for g in spec["groups"] if g["id"] == "wilds-08"][0]
    row = [u["id"] for u in wilds["units"]].index("primordial_wyrm")
    sheet = Image.open(WYRM_SHEET).convert("RGBA")
    cols, rows = wilds["grid"]
    cells, _ = extract_cells(sheet, row, cols, rows)
    cw = sheet.width // cols
    ch = max(c.height for c in cells)
    out = Image.new("RGBA", (cw * cols, ch))
    for i, cell in enumerate(cells):
        cell = recolor(cell)
        # keep each pose on its own cell, bottom-aligned, centred on the cell
        x = i * cw + (cw - cell.width) // 2
        out.paste(cell, (x, ch - cell.height), cell)
    os.makedirs(os.path.join(ROOT, BATCH), exist_ok=True)
    source = os.path.join(ROOT, BATCH, GROUP + "-source.png")
    reference = os.path.join(ROOT, BATCH, "creature_ancient_dragon.png")
    group_ref = os.path.join(ROOT, BATCH, GROUP + "-reference.png")
    out.save(source)
    recolor(Image.open(WYRM_REF)).save(reference)
    recolor(Image.open(WYRM_REF)).save(group_ref)
    group = {
        "id": GROUP, "faction": "wilds",
        "reference": BATCH + "/" + GROUP + "-reference.png", "source": BATCH + "/" + GROUP + "-source.png",
        "grid": [cols, 1],
        "units": [{
            "id": "ancient_dragon", "name": "Ancient Dragon",
            "description": "Karzhaloth, the eyeless dragon under the world, sealed behind the Nightgate. Interim: the primordial wyrm's poses recoloured to obsidian, ember and silver.",
            "role": "flyer", "tags": ["beast", "dragon", "boss"], "size": [128, 128], "anchor": [64, 127],
            "reference_sha256": sha(reference), "reference_source": BATCH + "/creature_ancient_dragon.png"}],
        "prompt_file": BATCH + "/creature_ancient_dragon.txt",
        "source_sha256": sha(source),
        "generation_status": "derived_interim", "quality_status": "animation_candidate",
        "derived_by": "tools/story/derive_ancient_dragon_animation.py", "derived_from": "wilds-08 / primordial_wyrm",
    }
    spec["groups"] = [g for g in spec["groups"] if g["id"] != GROUP] + [group]
    with open(SPEC, "w") as f:
        json.dump(spec, f, indent=2)
        f.write("\n")
    print("wrote", source, out.size)


if __name__ == "__main__":
    main()
