"""Prepare immutable native references and prompts for the DLC hero gaits."""
from pathlib import Path
import hashlib
import json

from PIL import Image
from crowns_of_cinder_assets import build, specs
from crowns_of_cinder_assets.palette import Palette


def main():
    root = Path(__file__).resolve().parents[2]
    doc = json.loads((root / 'assets/specs/dlc_factions.json').read_text())
    path = root / 'assets/specs/creature_animations.json'
    animation = json.loads(path.read_text())
    paths = build.Paths(root)
    palette = Palette.load(paths.specs / 'palette.json')
    by_id = {s['id']: s for s in specs.load_sprite_specs(paths.specs)}
    batch = root / 'assets/source/batches/dlc-animation-001'
    for fid, faction in doc['factions'].items():
        gid = 'dlc-' + fid + '-heroes'
        if any(g['id'] == gid for g in animation.get('hero_groups', [])):
            continue
        units = []
        strip = Image.new('RGBA', (384, 128))
        for index, hid in enumerate(faction['hero_ids']):
            sid = 'hero_' + hid
            if not (paths.generated / (sid + '.png')).is_file():
                raise ValueError(sid + ': stage hero artwork first')
            image, _ = build.render_sprite(by_id[sid], palette, paths)
            reference = batch / (sid + '.png')
            image.save(reference)
            strip.paste(image, (index * 128, 0))
            units.append({**doc['hero_classes'][hid], 'size': [128,128], 'anchor': [64,127],
                          'reference_source': str(reference.relative_to(root)),
                          'reference_sha256': hashlib.sha256(reference.read_bytes()).hexdigest()})
        reference = batch / (gid + '-reference.png')
        strip.save(reference)
        description = ' '.join(f"Row {i+1}: {u['name']}, {u['desc']}." for i, u in enumerate(units))
        locomotion = ('Lizards walk with grounded coordinated six-legged reptile footfalls; bent knees, alternating contact and passing poses, low stable reptilian body and tail.'
                      if fid == 'darkelf' else
                      'Crabs use coordinated alternating leg groups; rigid level carapace, legs bend at joints and remain attached, stable front claws, no horse gait.')
        prompt = ('Production dark fantasy painted pixel-art movement sprite sheet. Preserve EXACT three mounted heroes in reference strip, their faces, weapons, mount anatomy, proportions, silhouette and palette. '
                  'Reference left to right becomes rows top to bottom. EXACT FOUR equal columns by THREE equal rows, twelve isolated full-body sprites on TRUE TRANSPARENT background. '
                  'No labels, text, grid, shadows or scenery. Each row is the SAME hero facing RIGHT, with four authentic walk-in-place poses: contact, passing, opposite contact, opposite passing. '
                  'Rider remains seated with stable pelvis, torso and weapon. Mount legs articulate; no whole-image stretching, bobbing or scaling. ' + locomotion + ' ' + description +
                  ' Large transparent gutters, whole weapons, tails, legs and claws stay inside cell. Crisp painted pixel detail matching reference, upper-left lighting. Consistent figure scale and foot baseline.')
        prompt_path = batch / (gid + '-prompt.txt')
        prompt_path.write_text(prompt + '\n')
        animation.setdefault('hero_groups', []).append({
            'id': gid, 'faction': fid, 'category': 'hero', 'dlc': True,
            'reference': str(reference.relative_to(root)),
            'source': str((batch / (gid + '-source.png')).relative_to(root)),
            'grid': [4,3], 'units': units,
            'prompt_file': str(prompt_path.relative_to(root)),
            'generation_status': 'pending', 'quality_status': 'pending_generation'})
    path.write_text(json.dumps(animation, indent=2) + '\n')


if __name__ == '__main__':
    main()
