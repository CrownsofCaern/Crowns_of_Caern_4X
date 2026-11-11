"""Resource coverage and provenance for piles with disconnected pieces."""
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from crowns_of_cinder_assets import production


class ResourceArtTests(unittest.TestCase):
    def test_every_actual_resource_has_generated_pickup_and_ui_art(self):
        resources = json.loads((ROOT/'data/resources.json').read_text())['resources']
        manifest = json.loads((ROOT/'assets/manifest.json').read_text())
        for rid in resources:
            for sid in ['resource_'+rid, 'ui_resource_'+rid]:
                self.assertEqual(manifest['sprites'][sid]['source'], 'generated')
                source = ROOT/'assets/source/generated'/f'{sid}.png'
                metadata = json.loads(source.with_suffix('.json').read_text())
                self.assertEqual(hashlib.sha256(source.read_bytes()).hexdigest(),metadata['source_sha256'])
                sheet = ROOT/metadata['source_sheet']
                self.assertEqual(hashlib.sha256(sheet.read_bytes()).hexdigest(),metadata['source_sheet_sha256'])

    def test_import_keeps_detached_pieces_and_records_metadata(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            batch = root/'assets/source/batches/resource-test'
            batch.mkdir(parents=True)
            image = Image.new('RGBA',(64,32),(210,180,50,12))
            draw = ImageDraw.Draw(image)
            draw.rectangle((3,6,15,20),fill=(118,93,41,255))
            draw.rectangle((40,8,53,22),fill=(172,138,63,255))
            image.save(batch/'source.png')
            (batch/'layout.json').write_text(json.dumps({'assets':[{
                'id':'resource_gold','crop_xyxy':[0,0,64,32],
                'keep_components':True,'alpha_floor':64}]}))
            production.import_sheet(root,batch)
            result = Image.open(root/'assets/source/generated/resource_gold.png')
            self.assertEqual(result.getpixel((5,10)),(118,93,41,255))
            self.assertEqual(result.getpixel((45,10)),(172,138,63,255))
            self.assertEqual(result.getpixel((30,10)),(0,0,0,0))
            metadata = json.loads((root/'assets/source/generated/resource_gold.json').read_text())
            self.assertEqual(metadata['source_sheet_sha256'],hashlib.sha256((batch/'source.png').read_bytes()).hexdigest())
            with self.assertRaises(FileExistsError):
                production.import_sheet(root,batch)
