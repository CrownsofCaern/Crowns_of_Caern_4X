"""Inventory artwork exports retain separate, centered transparent sprites."""
import json
import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools/assets"))
from crowns_of_cinder_assets import artifacts  # noqa: E402


class ArtifactArtTests(unittest.TestCase):
    def test_build_covers_every_item_and_rejects_missing_source(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "data").mkdir()
            (root / "assets/specs").mkdir(parents=True)
            sources = root / "assets/source/artifacts-001"
            sources.mkdir(parents=True)
            (root / "assets/specs/palette.json").write_bytes((ROOT / "assets/specs/palette.json").read_bytes())
            (root / "data/artifacts.json").write_text(json.dumps({"artifacts": {"sword": {}, "shield": {}}}))
            (sources / "manifest.json").write_text(json.dumps({"assets": [{"id": "sword", "source": "sword.png"}, {"id": "shield", "source": "shield.png"}]}))
            for name in ("sword", "shield"):
                image = Image.new("RGBA", (100, 80), (0, 0, 0, 0))
                ImageDraw.Draw(image).rectangle((20, 10, 70, 65), fill=(100, 60, 30, 255))
                image.save(sources / (name + ".png"))
            artifacts.build(root)
            for name in ("sword", "shield"):
                image = Image.open(root / "assets/artifacts" / (name + ".png"))
                self.assertEqual(image.size, (64, 64))
                self.assertEqual(image.getpixel((0, 0))[3], 0)
                self.assertIsNotNone(image.getbbox())
            (sources / "shield.png").unlink()
            with self.assertRaises(FileNotFoundError):
                artifacts.build(root)
