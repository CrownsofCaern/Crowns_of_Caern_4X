"""Town roster coverage and continuity of multi-cell terrain fields."""
import json
from pathlib import Path
import sys
import unittest
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from crowns_of_cinder_assets import postprocess, town_scenes, town_sheets


class LivingVisualTests(unittest.TestCase):
    def test_concord_layers_cover_real_building_ids_once(self):
        spec = json.loads((ROOT / "assets/specs/town_scenes.json").read_text())["factions"]["concord"]
        buildings = json.loads((ROOT / "data/buildings.json").read_text())["towns"]["concord"]["buildings"]
        ids = [bid for slot in spec["slots"] for bid in slot["variants"]]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertEqual(set(ids), set(buildings))
        self.assertEqual(town_scenes.validate(ROOT), [])

    def test_every_faction_scene_covers_its_roster_and_art_names_real_ids(self):
        spec = json.loads((ROOT / "assets/specs/town_scenes.json").read_text())["factions"]
        towns = json.loads((ROOT / "data/buildings.json").read_text())["towns"]
        self.assertEqual(set(spec), set(towns))
        for faction, scene in spec.items():
            ids = [bid for slot in scene["slots"] for bid in slot["variants"]]
            self.assertEqual(len(ids), len(set(ids)), faction)
            self.assertEqual(set(ids), set(towns[faction]["buildings"]), faction)
            self.assertLessEqual(set(scene["assets"]), set(ids), faction)
            for slot in scene["slots"]:
                x, y = slot["at"]
                self.assertTrue(0 <= x <= scene["size"][0] and 0 <= y <= scene["size"][1], slot["id"])

    def test_town_layers_reproduce_from_the_concept_sheets(self):
        for layout in sorted((ROOT / "assets/source/batches").glob("*-town-001/layout.json")):
            batch = json.loads(layout.read_text())
            if not isinstance(batch, dict):
                continue  # concord-town-001 uses the older crop list
            for sheet in batch["sheets"]:
                cells = town_sheets.extract_cells(ROOT / sheet["source"])
                for index, bid in enumerate(sheet["cells"]):
                    path = ROOT / f"assets/source/generated/town_{batch['faction']}_{bid}.png"
                    staged = np.array(Image.open(path).convert("RGBA"))
                    self.assertTrue(np.array_equal(staged, cells[index]), bid)

    def test_sheet_cleanup_drops_red_halo_but_keeps_opaque_red_paint(self):
        rgba = np.zeros((12, 12, 4), dtype=np.uint8)
        rgba[3:9, 3:9] = (90, 70, 40, 251)          # paint
        rgba[5, 5] = (200, 20, 20, 251)            # opaque red paint (a banner)
        rgba[2, 3:9] = (220, 10, 10, 120)          # red halo with partial alpha
        rgba[0, 0] = (60, 60, 60, 20)              # near-transparent noise
        out = town_sheets._clean_edges(rgba)
        self.assertEqual(tuple(out[5, 5]), (200, 20, 20, 255))
        self.assertEqual(out[4, 4, 3], 255)
        self.assertEqual(out[0, 0, 3], 0)
        halo = out[2, 4]
        self.assertTrue(halo[3] == 0 or halo[0] - max(halo[1], halo[2]) <= town_sheets.EDGE_RED_MARGIN)

    def test_connected_field_wraps_without_blurred_edge_strips(self):
        spec = json.loads((ROOT / "assets/specs/terrain.json").read_text())
        for tid, entry in spec["connected_fields"]["terrains"].items():
            with self.subTest(terrain=tid):
                source = Image.open(ROOT / entry["source"])
                rgb = np.array(postprocess.connected_terrain_field(source, (480, 480)))[:, :, :3].astype(float)
                vertical_join = np.abs(rgb[0] - rgb[-1]).mean()
                horizontal_join = np.abs(rgb[:, 0] - rgb[:, -1]).mean()
                vertical_interior = np.abs(rgb[1:] - rgb[:-1]).mean()
                horizontal_interior = np.abs(rgb[:, 1:] - rgb[:, :-1]).mean()
                self.assertLess(vertical_join, 2 * vertical_interior)
                self.assertLess(horizontal_join, 2 * horizontal_interior)
                self.assertGreater(np.abs(rgb[1:10] - rgb[:9]).mean(), vertical_interior * 0.4)

    def test_atlas_reassembles_the_continuous_source(self):
        terrain = json.loads((ROOT / "assets/manifest.json").read_text())["terrain"]
        atlas = Image.open(ROOT / "assets/atlases/terrain.png").convert("RGBA")
        t = terrain["tile_size"]
        row = terrain["terrains"]["grass"]["row"]
        field = terrain["terrains"]["grass"]["field"]
        w, h = field["cells"]
        self.assertGreaterEqual(w, 12)
        self.assertGreaterEqual(h, 12)
        self.assertLessEqual(atlas.width, 16384)
        assembled = Image.new("RGBA", (w*t, h*t))
        for y in range(h):
            for x in range(w):
                col = field["column"] + y*w + x
                assembled.paste(atlas.crop((col*t, row*t, (col+1)*t, (row+1)*t)), (x*t, y*t))
        spec = json.loads((ROOT / "assets/specs/terrain.json").read_text())
        source = ROOT / spec["connected_fields"]["terrains"]["grass"]["source"]
        expected = postprocess.connected_terrain_field(Image.open(source), (w*t, h*t))
        self.assertEqual(assembled.tobytes(), expected.tobytes())
