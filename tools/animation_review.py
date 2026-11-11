"""Contact sheets and native-scale loop previews from the committed animation atlases."""
from pathlib import Path
import json

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "docs/art/production/animations"


def review():
    OUT.mkdir(parents=True, exist_ok=True)
    spec = json.loads((ROOT / "assets/specs/creature_animations.json").read_text())
    manifest = json.loads((ROOT / "assets/animations.json").read_text())
    atlases = {key: Image.open(ROOT / info["path"].removeprefix("res://")).convert("RGBA") for key, info in manifest["atlases"].items()}
    pages = {}
    for group in spec["groups"]:
        pages.setdefault(group["faction"], []).extend("creature_" + unit["id"] for unit in group["units"])
    pages["hero-knight"] = ["hero_knight"]
    for faction, units in pages.items():
        for start in range(0, len(units), 16):
            ids = units[start:start+16]
            rows = (len(ids)+3)//4
            cell_w, cell_h = manifest["frame_size"]
            row_height = cell_h + 20
            for action in ["move", "attack"]:
                if not any(action in manifest["units"].get(sid, {}).get("actions", {}) for sid in ids):
                    continue
                frames = []
                for index in range(4):
                    page = Image.new("RGBA", (min(4,len(ids))*cell_w, rows*row_height+28), "#202027")
                    draw = ImageDraw.Draw(page)
                    draw.text((8,8), faction + " / " + action + " / native artwork / candidate review", fill="#e5d8b4")
                    for n, sid in enumerate(ids):
                        unit = manifest["units"].get(sid, {})
                        clip = unit.get("actions", {}).get(action)
                        if clip is None:
                            continue
                        x,y,w,h = clip["frames"][index]
                        pose = atlases[unit["atlas"]].crop((x,y,x+w,y+h))
                        cell = (n%4*cell_w, n//4*row_height+28)
                        page.alpha_composite(pose, cell)
                        draw.text((cell[0]+4,cell[1]+cell_h+2), sid.removeprefix("creature_").removeprefix("hero_"), fill="#d6ccb4")
                    frames.append(page.convert("RGB"))
                durations = manifest["units"][ids[0]]["actions"][action]["durations_ms"].copy()
                if action == "attack": durations[-1] += 400
                name = f"{faction}-{start//16+1:02d}-{action}"
                frames[0].save(OUT / (name+".gif"), save_all=True, append_images=frames[1:], duration=durations, loop=0, optimize=False)
                frames[1].save(OUT / (name+"-contact.png"))
    # Throwaway first-registration previews are replaced by the reviewed pages.
    for path in OUT.glob("*-first-review.gif"):
        path.unlink()


if __name__ == "__main__":
    review()
