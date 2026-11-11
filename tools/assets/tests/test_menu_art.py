"""Full-resolution menu exports must remain byte-for-byte reproducible."""
import json
from pathlib import Path
import tempfile
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from crowns_of_cinder_assets import menu_art

ROOT = Path(__file__).resolve().parents[3]


class MenuArtTests(unittest.TestCase):
    def test_archival_sources_export_without_downsampling(self):
        spec = json.loads((ROOT / "assets/specs/menu_art.json").read_text())
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            manifest = menu_art.build(ROOT, out)
            expected = json.loads((ROOT / "assets/menus/manifest.json").read_text())
            self.assertEqual(manifest, expected)
            self.assertEqual(len(manifest["assets"]), 6)
            for asset in spec["assets"]:
                self.assertEqual((ROOT / asset["source"]).read_bytes(),
                                 (out / asset["output"]).read_bytes())


if __name__ == "__main__":
    unittest.main()
