"""Terrain scene coverage, native resolution and byte-preserving exports."""
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from crowns_of_cinder_assets import battlefields


class BattlefieldTests(unittest.TestCase):
    def test_all_ten_terrains_have_individual_art(self):
        manifest = json.loads((ROOT / "assets/battlefields/manifest.json").read_text())
        known = json.loads((ROOT / "data/terrains.json").read_text())["terrains"]
        self.assertEqual(set(manifest["terrains"]),set(known))
        self.assertEqual(len(manifest["assets"]),17)
        self.assertEqual(manifest["pending"],[])
        self.assertEqual(battlefields.validate(ROOT),[])

    def test_exports_preserve_original_png_bytes_and_manifest(self):
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory)
            result = battlefields.build(ROOT,out)
            expected = json.loads((ROOT / "assets/battlefields/manifest.json").read_text())
            self.assertEqual(result,expected)
            for asset in json.loads((ROOT / "assets/specs/battlefields.json").read_text())["assets"]:
                self.assertEqual((ROOT / asset["source"]).read_bytes(),(out / asset["output"]).read_bytes())
