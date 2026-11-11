"""All ultimate art recipes and town bindings cover the actual playable roster."""
from pathlib import Path
import json
import sys
import unittest

ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'tools/assets'))
from crowns_of_cinder_assets import ultimate_buildings


class UltimateArtTests(unittest.TestCase):
    def test_inventory_resolves_aliases_and_retains_all_ultimate_sources(self):
        from crowns_of_cinder_assets import production
        inventory=production.inventory(ROOT)
        sources=[a for a in inventory['assets'] if a['category']=='ultimate_building_source']
        self.assertEqual(len(sources),8)
        aliases=[a for a in inventory['assets'] if a['category']=='town_scene' and a.get('reuses')]
        self.assertTrue(aliases)
        for record in [*sources,*aliases]:
            self.assertTrue((ROOT/record['source']).is_file())
            self.assertTrue((ROOT/record['output']).is_file())

    def test_all_eight_buildings_are_reproducible_and_bound(self):
        self.assertEqual(ultimate_buildings.validate(ROOT),[])
        registry=json.loads((ROOT/'assets/specs/ultimate_buildings.json').read_text())
        self.assertEqual(len(registry['assets']),8)
        scenes=json.loads((ROOT/'assets/specs/town_scenes.json').read_text())['factions']
        for asset in registry['assets']:
            entry=scenes[asset['faction']]['assets'][asset['building_id']]
            self.assertNotIn('same_as',entry)
            self.assertEqual(ultimate_buildings.render(ROOT,asset),(ROOT/asset['output']).read_bytes())

    def test_dlc_regeneration_keeps_unique_ultimate_slots(self):
        from crowns_of_cinder_assets import dlc
        import tempfile
        import shutil
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            (root/'assets/specs').mkdir(parents=True)
            shutil.copyfile(ROOT/'assets/specs/town_scenes.json',root/'assets/specs/town_scenes.json')
            doc=dlc.read(ROOT)
            # Sync uses the real source paths and SHA guards. Point its root at
            # a copy containing only the pack sources and gameplay definitions.
            paths=[job['source'] for job in doc['batches'] if job['kind']=='foundation']
            paths += [f'assets/source/generated/building_{bid}.png' for f in doc['factions'].values() for bid in f['building_ids']]
            paths += ['data/buildings.json','assets/source/generated/town_darkelf_de_ultimate.png','assets/source/generated/town_fishmen_fm_ultimate.png']
            for relative in paths:
                path=root/relative;path.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(ROOT/relative,path)
            dlc._sync_towns(root,doc)
            scenes=json.loads((root/'assets/specs/town_scenes.json').read_text())['factions']
            for faction,bid in [('darkelf','de_ultimate'),('fishmen','fm_ultimate')]:
                self.assertNotIn('same_as',scenes[faction]['assets'][bid])
                own=[s for s in scenes[faction]['slots'] if bid in s['variants']]
                self.assertEqual(len(own),1)
                self.assertEqual(own[0]['variants'],[bid])
