"""Interim source art for the expansion artifacts (The Six Eyes, The Drowned Oath).

The six Gate-Eyes are drawn here (a lidded stone eye in each people's colour);
the three Forgewarm Harness pieces are hue-shifted copies of existing Forge-style
pieces with ember seams. They stand in until the image generator produces real
paintings from the prompts in assets/source/batches/six-eyes-story-001/.

    python3 tools/story/derive_dlc_artifacts.py       # writes assets/source/artifacts-001/<id>.png
                                                       # and updates its manifest.json
"""
import colorsys, json, math, os, sys
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "assets/source/artifacts-001")
MANIFEST = os.path.join(SRC, "manifest.json")
PROMPTS = os.path.join(ROOT, "assets/source/batches/six-eyes-story-001")

# id -> (iris colour, stone colour, people, flaw line)
EYES = {
    "eye_of_the_anvil": ((214, 88, 40), (70, 52, 48), "the Forge's keystone", "a dull red stone that weighs more than it should"),
    "eye_of_the_saint": ((236, 196, 92), (88, 78, 60), "the Concord's reliquary jewel", "the colour of a dawn that never comes"),
    "eye_of_the_root": ((96, 170, 72), (52, 64, 40), "the Thornwood's seed-stone", "green, with something moving inside"),
    "eye_of_the_regent": ((150, 150, 168), (48, 46, 56), "the Hollow Regent's pendant", "grey; the hand that holds it feels watched"),
    "eye_of_embers": ((255, 120, 32), (60, 36, 30), "the Red Sky King's trophy", "hot to hold"),
    "eye_of_winter": ((130, 200, 236), (44, 56, 72), "the clans' cairn-stone", "frozen into the winter wyrm's cairn"),
}
# id -> (base artifact to shift, slot)
HARNESS = {
    "emberglass_visor": ("gravewatch_visor", "helm"),
    "furnace_mail": ("emberforged_cuirass", "armor"),
    "hearthstride_greaves": ("rimetread_boots", "boots"),
}


def draw_eye(iris, stone, size=1024):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx, cy = size // 2, size // 2
    # the stone: a rounded lozenge with a bevel
    w, h = int(size * 0.42), int(size * 0.26)
    pts = [(cx - w, cy), (cx - w * 0.5, cy - h), (cx + w * 0.5, cy - h), (cx + w, cy), (cx + w * 0.5, cy + h), (cx - w * 0.5, cy + h)]
    d.polygon(pts, fill=stone + (255,), outline=(20, 14, 16, 255), width=14)
    light = tuple(min(255, c + 40) for c in stone)
    d.line([pts[0], pts[1], pts[2]], fill=light + (255,), width=18)
    dark = tuple(max(0, c - 30) for c in stone)
    d.line([pts[3], pts[4], pts[5]], fill=dark + (255,), width=18)
    # the eye: an almond opening, iris, pupil, a lid shadow and a catch-light
    ew, eh = int(size * 0.30), int(size * 0.14)
    d.ellipse([cx - ew, cy - eh, cx + ew, cy + eh], fill=(236, 226, 206, 255), outline=(20, 14, 16, 255), width=12)
    r = int(size * 0.11)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=iris + (255,), outline=(20, 14, 16, 255), width=10)
    rim = tuple(max(0, c - 60) for c in iris)
    d.ellipse([cx - r + 14, cy - r + 14, cx + r - 14, cy + r - 14], outline=rim + (255,), width=12)
    pr = int(size * 0.045)
    d.ellipse([cx - pr, cy - pr * 1.6, cx + pr, cy + pr * 1.6], fill=(16, 10, 12, 255))
    d.ellipse([cx - r * 0.55, cy - r * 0.75, cx - r * 0.2, cy - r * 0.4], fill=(255, 250, 240, 230))
    # upper lid shadow
    shade = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shade)
    sd.ellipse([cx - ew, cy - eh, cx + ew, cy + eh], fill=(0, 0, 0, 110))
    sd.ellipse([cx - ew, cy - eh + int(eh * 0.7), cx + ew, cy + eh + int(eh * 0.7)], fill=(0, 0, 0, 0))
    img = Image.alpha_composite(img, shade)
    # a faint glow of the iris colour around the stone
    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(glow).polygon(pts, fill=iris + (120,))
    glow = glow.filter(ImageFilter.GaussianBlur(size * 0.03))
    return Image.alpha_composite(glow, img)


def ember_shift(base: Image.Image) -> Image.Image:
    """Shift a cold or neutral piece toward dark iron with ember-orange seams."""
    base = base.convert("RGBA")
    px = base.load()
    w, h = base.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            hh, l, s = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
            # bright, saturated parts become ember; the rest darkens to iron
            if l > 0.55 and s > 0.15:
                hh, s, l = 0.06, min(1.0, s + 0.5), min(0.75, l + 0.1)
            else:
                hh, s, l = 0.03, s * 0.5, l * 0.78
            rr, gg, bb = colorsys.hls_to_rgb(hh, l, s)
            px[x, y] = (int(rr * 255), int(gg * 255), int(bb * 255), a)
    return base


def main():
    manifest = json.load(open(MANIFEST))
    have = {e["id"] for e in manifest["assets"]}
    os.makedirs(PROMPTS, exist_ok=True)
    for aid, (iris, stone, people, flaw) in EYES.items():
        img = draw_eye(iris, stone)
        img.save(os.path.join(SRC, aid + ".png"))
        name = aid.replace("_", " ").title().replace("Of The", "of the").replace("Of ", "of ")
        prompt = ("Use case: stylized-concept. Asset type: a single inventory item sprite for original Crowns of Caern dark medieval fantasy game. "
                  "Subject: %s, a charm artifact and relic: one of the six Gate-Eyes, %s, %s. A lidded stone eye set in old dark silver, "
                  "the iris glowing faintly. Depict this specific named item as one clearly recognizable isolated object. Centered complete silhouette "
                  "with ample transparent padding, three-quarter view, gritty detailed hand-painted slightly pixelated art, subdued earthy palette, "
                  "warm upper-left light, readable at 40 pixels. No frame, text, letters, UI, or extra objects. Transparent background." % (name, people, flaw))
        open(os.path.join(PROMPTS, aid + ".txt"), "w").write(prompt + "\n")
        if aid not in have:
            manifest["assets"].append({"id": aid, "slot": "charm", "rarity": "relic", "prompt": prompt, "source": aid + ".png",
                                       "status": "interim_derived_art", "derived_by": "tools/story/derive_dlc_artifacts.py"})
    for aid, (base_id, slot) in HARNESS.items():
        base = Image.open(os.path.join(SRC, base_id + ".png"))
        ember_shift(base).save(os.path.join(SRC, aid + ".png"))
        name = aid.replace("_", " ").title()
        prompt = ("Use case: stylized-concept. Asset type: a single inventory item sprite for original Crowns of Caern dark medieval fantasy game. "
                  "Subject: %s, a %s artifact of the Forgewarm Harness: dark Forge iron run through with emberglass seams that glow orange, "
                  "made to keep a fish-man warm on a glacier. Depict this specific named item as one clearly recognizable isolated object. Centered complete "
                  "silhouette with ample transparent padding, three-quarter view, gritty detailed hand-painted slightly pixelated art, subdued earthy palette, "
                  "warm upper-left light, readable at 40 pixels. No frame, text, letters, UI, or extra objects. Transparent background." % (name, slot))
        open(os.path.join(PROMPTS, aid + ".txt"), "w").write(prompt + "\n")
        if aid not in have:
            manifest["assets"].append({"id": aid, "slot": slot, "rarity": "major", "prompt": prompt, "source": aid + ".png",
                                       "status": "interim_derived_art", "derived_by": "tools/story/derive_dlc_artifacts.py", "derived_from": base_id})
    with open(MANIFEST, "w") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")
    print("wrote", len(EYES) + len(HARNESS), "artifact sources")


if __name__ == "__main__":
    main()
