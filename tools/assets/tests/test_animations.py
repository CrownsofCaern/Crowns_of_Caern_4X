"""Actual pose frames, stable registration and complete animation manifests."""
import json
from pathlib import Path
import sys
import unittest
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from crowns_of_cinder_assets import animations, creatures_auto


class AnimationTests(unittest.TestCase):
    def test_plan_uses_every_actual_creature_once(self):
        spec = json.loads((ROOT / "assets/specs/creature_animations.json").read_text())
        ids = [u["id"] for g in spec["groups"] if not g.get("dlc") for u in g["units"]]
        self.assertEqual(len(ids), len(set(ids)))
        # Art-pack factions (assets/specs/dlc_factions.json) animate from their own pack.
        packs = set(json.loads((ROOT / "assets/specs/dlc_factions.json").read_text())["factions"])
        core = {cid for cid, c in creatures_auto.load_creatures(ROOT / "data").items() if c.get("faction") not in packs}
        self.assertEqual(set(ids), core)

    def test_ready_frames_are_nonempty_distinct_and_in_bounds(self):
        self.assertEqual(animations.validate(ROOT), [])
        manifest = json.loads((ROOT / "assets/animations.json").read_text())
        self.assertEqual(manifest["anchor"], [160, 207])
        for sid, unit in manifest["units"].items():
            if sid.startswith("creature_"):
                self.assertTrue({"move", "attack"} <= set(unit["actions"]) <= {"move", "attack", "idle", "death"})

    def test_horse_walk_registration_does_not_follow_the_support_foot(self):
        spec = json.loads((ROOT / "assets/specs/creature_animations.json").read_text())
        group = spec["hero_groups"][0]
        unit = group["units"][0]
        sheet = Image.open(ROOT / group["source"]).convert("RGBA")
        cells = [sheet.crop((round(i*sheet.width/4),0,round((i+1)*sheet.width/4),sheet.height)) for i in range(4)]
        frames, qc = animations.register(cells, Image.open(ROOT / unit["reference_source"]).convert("RGBA"))
        roots = [animations.body_root(frame) for frame in frames]
        self.assertLessEqual(max(roots)-min(roots), 2, "rider must stay level while legs articulate")
        self.assertEqual(qc["warnings"], [])

    def test_adaptive_gutters_preserve_a_projecting_weapon(self):
        sheet = Image.new("RGBA", (200, 100))
        draw = ImageDraw.Draw(sheet)
        draw.rectangle((20,20,60,80),fill="white")
        draw.rectangle((60,25,125,30),fill="white")
        draw.rectangle((130,20,170,80),fill="white")
        draw.rectangle((90,60,130,65),fill="white")
        cells, qc = animations.extract_cells(sheet, 0, 2, 1)
        self.assertEqual(qc["warnings"], [])
        counts = [sum(a > 0 for a in image.getchannel("A").getdata()) for image in cells]
        self.assertEqual(counts, [2891,2741], "a rigid grid would cut and misassign weapon tips")

    def test_matte_alpha_is_removed_without_quantizing_figure_colours(self):
        reference = Image.new("RGBA",(128,128))
        ImageDraw.Draw(reference).rectangle((45,15,80,125),fill=(111,82,49,255))
        cells=[]
        for i in range(4):
            cell=Image.new("RGBA",(128,128),(180,175,170,26))
            ImageDraw.Draw(cell).rectangle((45,15,80,125),fill=(111,82,49,255))
            cells.append(cell)
        frames,_=animations.register(cells,reference)
        self.assertFalse(any(0<a<64 for a in frames[0].getchannel("A").getdata()))
        self.assertIn((111,82,49,255),set(frames[0].getdata()))
