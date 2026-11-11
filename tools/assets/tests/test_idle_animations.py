"""Idle/walk/attack sheet plan: every animated creature has a group with an
A and a B sheet, prompts name the right units, pending groups leave the
manifest unchanged, and reviewed sheets become idle, move and attack clips."""
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from crowns_of_cinder_assets import animations, idle_animations
import generate_idle_sheets


def six_column(sheet: Image.Image) -> Image.Image:
    """A 6-column stand-in sheet made from the first six poses of each row."""
    rows, _ = animations.extract_rows(sheet, 4)
    out = Image.new("RGBA", (1536, 1024))
    for r in range(4):
        cells, _ = animations.extract_cells(sheet, r, 7, 4, rows)
        for c in range(6):
            fig = cells[c].crop(cells[c].getbbox())
            out.alpha_composite(fig, (c * 256 + (256 - fig.width) // 2, r * 256 + (256 - fig.height) // 2))
    return out


class IdleAnimationTests(unittest.TestCase):
    def test_plan_mirrors_the_move_attack_groups(self):
        spec = idle_animations.load_spec(ROOT)
        base = json.loads((ROOT / "assets/specs/creature_animations.json").read_text())
        self.assertEqual([g["id"] for g in spec["groups"]], [g["id"] for g in base["groups"]])
        for g, b in zip(spec["groups"], base["groups"]):
            self.assertEqual([u["id"] for u in g["units"]], [u["id"] for u in b["units"]])
            self.assertEqual(g["sheets"]["A"]["grid"], [7, len(g["units"])])
            self.assertEqual(g["sheets"]["B"]["grid"], [6, len(g["units"])])
            self.assertTrue((ROOT / g["reference"]).is_file(), g["reference"])

    def test_prompts_name_every_unit_in_row_order(self):
        g = idle_animations.load_spec(ROOT)["groups"][0]
        for key, words in [("A", "SEVEN COLUMNS"), ("B", "SIX COLUMNS")]:
            text = idle_animations.prompt(g, key)
            at = [text.index(f"Row{i + 1}: {u['id']} ") for i, u in enumerate(g["units"])]
            self.assertEqual(at, sorted(at))
            self.assertIn(words, text)
        self.assertIn("WALK", idle_animations.prompt(g, "A"))
        self.assertIn("MAIN HIT", idle_animations.prompt(g, "B"))

    def test_pending_groups_change_nothing(self):
        manifest = {"units": {}, "atlases": {}, "qc": {}}
        pending = idle_animations.plan(ROOT)
        with tempfile.TemporaryDirectory() as out, patch.object(idle_animations, "load_spec", return_value=pending):
            idle_animations.build(ROOT, Path(out), manifest)
            self.assertEqual(manifest, {"units": {}, "atlases": {}, "qc": {}})

    def test_sheets_are_told_apart_by_their_columns(self):
        base = json.loads((ROOT / "assets/specs/creature_animations.json").read_text())["groups"][0]
        seven = Image.open(ROOT / base["source"]).convert("RGBA")
        self.assertEqual(generate_idle_sheets.columns_of(seven), 7)
        self.assertEqual(generate_idle_sheets.columns_of(six_column(seven)), 6)

    def test_reviewed_sheets_add_idle_walk_and_attack_clips(self):
        # Move/attack sheets stand in for generated A and B sheets.
        base = json.loads((ROOT / "assets/specs/creature_animations.json").read_text())["groups"][0]
        group = json.loads(json.dumps(idle_animations.load_spec(ROOT)["groups"][0]))
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            (tmp / "assets/specs").mkdir(parents=True)
            for rel in [u["reference_source"] for u in group["units"]]:
                (tmp / rel).parent.mkdir(parents=True, exist_ok=True)
                (tmp / rel).write_bytes((ROOT / rel).read_bytes())
            seven = Image.open(ROOT / base["source"]).convert("RGBA")
            for key, image in [("A", seven), ("B", six_column(seven))]:
                path = tmp / group["sheets"][key]["source"]
                path.parent.mkdir(parents=True, exist_ok=True)
                image.save(path)
                group["sheets"][key]["source_sha256"] = animations.digest(path)
            (tmp / idle_animations.SPEC).write_text(json.dumps({"groups": [group]}))
            manifest = {"units": {"creature_" + u["id"]: {"atlas": "a", "actions": {"move": {}, "attack": {}}}
                                  for u in group["units"]}, "atlases": {}, "qc": {}}
            idle_animations.build(tmp, tmp, manifest)
            actions = manifest["units"]["creature_" + group["units"][0]["id"]]["actions"]
            self.assertEqual(len(actions["idle"]["frames"]), 4)
            self.assertEqual(len(actions["move"]["frames"]), 4)
            self.assertEqual(len(actions["attack"]["frames"]), 7)
            self.assertEqual(actions["attack"]["frame_atlases"][-1], "animation_idle_concord-01_a")
            self.assertEqual(actions["attack"]["events"], [{"time_ms": idle_animations.IMPACTS_MS[0], "name": "impact"}])
            self.assertEqual(Image.open(tmp / "assets/atlases/animation_idle_concord-01_a.png").size, (8 * 320, 4 * 256))
            self.assertEqual(Image.open(tmp / "assets/atlases/animation_idle_concord-01_b.png").size, (7 * 320, 4 * 256))


if __name__ == "__main__":
    unittest.main()
