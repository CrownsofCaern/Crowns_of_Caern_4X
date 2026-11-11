"""Standalone DLC art coverage, provenance and isolation from campaign data."""
import hashlib
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from crowns_of_cinder_assets import dlc


class DlcTests(unittest.TestCase):
    def test_standalone_rosters_and_upgrade_links(self):
        self.assertEqual(dlc.validate(ROOT), [])
        pack = dlc.read(ROOT)
        self.assertEqual(set(pack['factions']), {'darkelf','fishmen'})
        self.assertEqual(len(pack['creatures']), 32)
        self.assertEqual(len(pack['hero_classes']), 6)
        self.assertEqual(len(pack['buildings']), 60)
        self.assertTrue(set(pack['factions']) <= set(json.loads((ROOT/'data/factions.json').read_text())['factions']))
        self.assertEqual(pack['story_links'], [])

    def test_every_asset_is_generated_and_provenance_is_intact(self):
        pack = dlc.read(ROOT)
        manifest = json.loads((ROOT/'assets/manifest.json').read_text())
        self.assertEqual(len(pack['assets']), 120)
        for asset in pack['assets']:
            sid = asset['id']
            self.assertEqual(manifest['sprites'][sid]['source'], 'generated', sid)
            raw = ROOT/'assets/source/generated'/f'{sid}.png'
            provenance = json.loads(raw.with_suffix('.json').read_text())
            self.assertEqual(hashlib.sha256(raw.read_bytes()).hexdigest(), provenance['source_sha256'])
            source = ROOT/provenance['source_sheet']
            self.assertEqual(hashlib.sha256(source.read_bytes()).hexdigest(), provenance['source_sheet_sha256'])

    def test_all_creatures_and_heroes_have_real_clips(self):
        pack = dlc.read(ROOT)
        animation = json.loads((ROOT/'assets/animations.json').read_text())
        # Pending base-game factions must not invalidate completed DLC clips.
        dlc_ids = {'creature_'+cid for cid in pack['creatures']} | {'hero_'+hid for hid in pack['hero_classes']}
        self.assertFalse(dlc_ids.intersection(animation['pending']))
        self.assertEqual(set(animation['optional_creatures']), set(pack['creatures']))
        for cid in pack['creatures']:
            # Every DLC creature moves and attacks; idle and death clips are added as they are made.
            actions = set(animation['units']['creature_'+cid]['actions'])
            self.assertLessEqual({'move','attack'}, actions, cid)
            self.assertLessEqual(actions, {'idle','move','attack','death'}, cid)
        for hid in pack['hero_classes']:
            self.assertEqual(set(animation['units']['hero_'+hid]['actions']), {'move'})

    def test_town_layers_cover_the_whole_declared_building_set(self):
        pack = dlc.read(ROOT)
        towns = json.loads((ROOT/'assets/towns/manifest.json').read_text())['factions']
        for fid, faction in pack['factions'].items():
            scene = towns[fid]
            buildings = set(json.loads((ROOT/'data/buildings.json').read_text())['towns'][fid]['buildings'])
            self.assertEqual(set(scene['assets']), buildings)
            self.assertEqual({bid for slot in scene['slots'] for bid in slot['variants']}, buildings)
            self.assertEqual(len(scene['slots']), 18)

    def test_pack_atlases_are_separate_and_gpu_bounded(self):
        pack = dlc.read(ROOT)
        manifest = json.loads((ROOT/'assets/manifest.json').read_text())
        for asset in pack['assets']:
            name = manifest['sprites'][asset['id']]['atlas']
            self.assertTrue(name.startswith('dlc_'+asset['faction']+'_'))
            self.assertLessEqual(max(manifest['atlases'][name]['size']), 2048)
