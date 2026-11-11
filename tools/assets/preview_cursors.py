"""Native and enlarged review of the actual atlas-backed action cursors."""
import json
from pathlib import Path
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parents[2]
manifest = json.loads((root / "assets/manifest.json").read_text())
atlas = Image.open(root / manifest["atlases"]["ui"]["path"].removeprefix("res://")).convert("RGBA")
actions = ["default", "move", "town", "attack", "pickup", "encounter", "select", "blocked", "wait"]
output = Image.new("RGB", (750, 510), "#1a1c20")
draw = ImageDraw.Draw(output)
for i, action in enumerate(actions):
    x, y, w, h = manifest["sprites"]["cursor_" + action]["rect"]
    image = atlas.crop((x, y, x + w, y + h))
    cx, cy = (i % 3) * 250 + 14, (i // 3) * 170 + 12
    output.paste(image, (cx, cy + 70), image)
    large = image.resize((120, 120), Image.Resampling.NEAREST)
    output.paste(large, (cx + 65, cy), large)
    draw.text((cx, cy + 132), action + " / hotspot 2,2", fill="#e6ded2")
destination = root / "docs/art/production/ui/action-cursors.png"
output.save(destination)
print(destination.relative_to(root))
