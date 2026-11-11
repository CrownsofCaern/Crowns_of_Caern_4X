"""Render a reproducible native-size river/lake review from the built atlas."""
import json
from pathlib import Path

from PIL import Image
from crowns_of_cinder_assets import procedural

root = Path(__file__).resolve().parents[2]
terrain = json.loads((root / "assets/manifest.json").read_text())["terrain"]
atlas = Image.open(root / terrain["atlas"].removeprefix("res://")).convert("RGBA")
edges = terrain.get("edges", {})
edge_atlas = Image.open(root / edges["atlas"].removeprefix("res://")).convert("RGBA") if edges else None
cell = terrain["tile_size"]
width, height = 24, 14
grid = {}
for y in range(height):
    for x in range(width):
        river = 7 + y // 3
        lake = ((x - 18) / 6) ** 2 + ((y - 11) / 4) ** 2 < 1
        grid[x, y] = "water" if lake else "river" if river <= x <= river + 2 else "grass"
        if x < 4 and y < 8:
            grid[x, y] = "forest"
        if 13 <= x <= 17 and y < 4:
            grid[x, y] = "rough"
        if x == river + 3 and 6 < y < 11:
            grid[x, y] = "swamp"
        if x >= 21 and 8 <= y <= 12:
            grid[x, y] = "desert"

output = Image.new("RGBA", (width * cell, height * cell))
directions = [(0, -1, procedural.N), (1, -1, procedural.NE), (1, 0, procedural.E),
              (1, 1, procedural.SE), (0, 1, procedural.S), (-1, 1, procedural.SW),
              (-1, 0, procedural.W), (-1, -1, procedural.NW)]

def tile(col, row):
    return atlas.crop((col * cell, row * cell, (col + 1) * cell, (row + 1) * cell))

def cell_hash(x, y, n, salt=0):
    h = (x * 374761393 + y * 668265263 + salt * 1442695041) & 0x7fffffff
    h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
    return (h ^ (h >> 16)) % max(n, 1)

for (x, y), tid in grid.items():
    info = terrain["terrains"][tid]
    field = info.get("field")
    if field:
        fw, fh = field["cells"]
        col = field["column"] + (y % fh) * fw + (x % fw)
    else:
        col = cell_hash(x, y, terrain["variants"])
    output.alpha_composite(tile(col, info["row"]), (x * cell, y * cell))
    count = terrain.get("detail_variants", 0)
    if count and cell_hash(x, y, 100, 29) < 60:
        detail = terrain["detail_column"] + cell_hash(x, y, count, 31)
        output.alpha_composite(tile(detail, info["row"]), (x * cell, y * cell))
    for other in terrain["order"]:
        neighbor = terrain["terrains"][other]
        specific = any((e["base"] == tid and other in e["neighbors"]) or
                       (e["base"] == other and tid in e["neighbors"]) for e in edges.get("types", {}).values())
        if other == tid or specific:
            continue
        mask = 0
        for dx, dy, bit in directions:
            if grid.get((x + dx, y + dy)) == other:
                mask |= bit
        mask = procedural.reduce_mask(mask)
        if mask:
            index = terrain["transition_masks"].index(mask)
            variant = cell_hash(x, y, terrain.get("transition_variants", 1), 23)
            output.alpha_composite(tile(terrain["transition_column"] + variant * len(terrain["transition_masks"]) + index, neighbor["row"]), (x * cell, y * cell))
    if edge_atlas:
        for entry in edges["types"].values():
            if entry["base"] != tid:
                continue
            bits = sum(bit for dx, dy, bit in directions if grid.get((x + dx, y + dy)) in entry["neighbors"])
            if bits:
                period = edges["period"]
                px, py = (x + y // 6) % period, (y + x // 6) % period
                col = entry["column"] + py * period + px
                edge_tile = edge_atlas.crop((col * cell, bits * cell, (col + 1) * cell, (bits + 1) * cell))
                output.alpha_composite(edge_tile, (x * cell, y * cell))
    if y == 5:
        road = terrain["roads"]
        column = road["bridge_column"] if tid in road["bridge_over"] else road["road_column"]
        output.alpha_composite(tile(column + 10, road["row"]), (x * cell, y * cell))

destination = root / "docs/art/production/water-river-native-review.png"
output.convert("RGB").save(destination)
print(destination.relative_to(root))
