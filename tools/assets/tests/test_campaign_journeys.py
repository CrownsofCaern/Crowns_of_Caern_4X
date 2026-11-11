"""Journey paintings use the existing illustration pipeline, with real chapter bindings."""
import hashlib
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tools/assets'))
from crowns_of_cinder_assets import illustrations


class CampaignJourneyTests(unittest.TestCase):
    def test_runtime_paintings_preserve_source_pixels_and_provenance(self):
        catalog = json.loads((ROOT / 'assets/specs/campaign_journeys.json').read_text())
        hashes = set()
        for cid, asset in catalog['campaigns'].items():
            source = ROOT / asset['source']
            metadata = json.loads(source.with_suffix('.json').read_text())
            digest = hashlib.sha256(source.read_bytes()).hexdigest()
            self.assertEqual(metadata['source_sha256'], digest, cid)
            self.assertEqual(metadata['prompt_sha256'], hashlib.sha256((ROOT / metadata['prompt_file']).read_bytes()).hexdigest())
            self.assertEqual(metadata['conditioning'], [catalog['style_reference']])
            snapshot = ROOT / metadata['story_snapshot']
            self.assertTrue(snapshot.is_file(), cid)
            with Image.open(source) as original, Image.open(ROOT / asset['output']) as exported:
                self.assertEqual(original.size, exported.size)
                self.assertGreaterEqual(min(original.size), 768)
                self.assertIsNone(ImageChops.difference(original.convert('RGB'), exported.convert('RGB')).getbbox(), cid)
            hashes.add(digest)
        self.assertEqual(len(hashes), len(catalog['campaigns']), 'individual paintings, not copies of the atlas')
        self.assertTrue({'six_eyes', 'drowned_oath'}.issubset(catalog['campaigns']))

    def test_validation_rejects_chapter_order_drift(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for relative in ('assets/specs/campaign_illustrations.json', 'assets/specs/campaign_journeys.json', 'data/campaigns.json'):
                dest = root / relative
                dest.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / relative, dest)
            illustrations.build(root)
            self.assertEqual(illustrations.validate(root), [])
            path = root / 'assets/specs/campaign_journeys.json'
            doc = json.loads(path.read_text())
            doc['campaigns']['last_light']['nodes'][0]['chapter'] = 'not_a_real_chapter'
            path.write_text(json.dumps(doc))
            self.assertIn('last_light: journey stops must match actual chapter order', illustrations.validate(root))
