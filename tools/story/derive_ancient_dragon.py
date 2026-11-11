"""Interim sprite for the ancient dragon (Karzhaloth), derived from the primordial wyrm's
generated source until a generated Karzhaloth exists (prompt in
assets/source/batches/six-eyes-story-001/creature_ancient_dragon.txt).

    python3 tools/story/derive_ancient_dragon.py && python3 tools/assets/pipeline.py build

Hue remap: bone and tan scales become cold obsidian, warm mid-tones become ember seams,
highlights become tarnished silver; the eye is sealed with a silver plate; drawn 1.2x.
"""
import colorsys, hashlib, json, os
from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "assets/source/generated/creature_primordial_wyrm.png")
OUT = os.path.join(ROOT, "assets/source/generated/creature_ancient_dragon.png")
SCALE = 1.2
EYE = (264, 62, 282, 76)   # the wyrm's eye in source pixels


def remap(r, g, b):
    h, l, s = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
    if l > 0.72:
        n = colorsys.hls_to_rgb(0.58, min(0.9, l), 0.08)
    elif 0.05 < h < 0.16 and s > 0.25 and 0.35 < l < 0.72:
        n = colorsys.hls_to_rgb(0.04, l * 0.95, min(1.0, s + 0.35))
    else:
        n = colorsys.hls_to_rgb(0.75, l * 0.62, min(0.35, s * 0.6 + 0.08))
    return tuple(int(c * 255) for c in n)


def main():
    src = Image.open(SRC).convert("RGBA")
    out = Image.new("RGBA", src.size)
    px, po = src.load(), out.load()
    for y in range(src.height):
        for x in range(src.width):
            r, g, b, a = px[x, y]
            po[x, y] = (0, 0, 0, 0) if a == 0 else remap(r, g, b) + (a,)
    d = ImageDraw.Draw(out)
    d.ellipse(EYE, fill=(196, 200, 214, 255), outline=(60, 56, 70, 255))
    cy = (EYE[1] + EYE[3]) // 2
    d.line((EYE[0] + 4, cy, EYE[2] - 4, cy), fill=(90, 88, 100, 255), width=2)
    big = out.resize((int(src.width * SCALE), int(src.height * SCALE)), Image.LANCZOS)
    big.save(OUT)
    meta = {
        "schema_version": 1, "provider": "derived", "batch": "six-eyes-story-001",
        "derived_from": os.path.relpath(SRC, ROOT),
        "derived_from_sha256": hashlib.sha256(open(SRC, "rb").read()).hexdigest(),
        "method": "tools/story/derive_ancient_dragon.py (hue remap, sealed eye, 1.2x)",
        "prompt_file": "assets/source/batches/six-eyes-story-001/creature_ancient_dragon.txt",
        "native_size": [128, 128], "quality_status": "interim_derived_pending_generation",
        "note": "Interim art until a generated Karzhaloth exists. Replace this file with the generated sprite; the spec entry stays."}
    with open(OUT[:-4] + ".json", "w") as f:
        json.dump(meta, f, indent=2)
        f.write("\n")
    print("wrote", OUT, big.size)


if __name__ == "__main__":
    main()
