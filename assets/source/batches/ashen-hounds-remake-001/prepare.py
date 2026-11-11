"""Compose new hound poses with unchanged Cinderling rows; preserve raw sources."""
from pathlib import Path
import hashlib
import json
import sys

from PIL import Image

ROOT = Path(__file__).resolve().parents[4]
BATCH = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / 'tools/assets'))
from crowns_of_cinder_assets import animations


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def cells(path, columns, rows=2):
    image = Image.open(path).convert('RGBA')
    bands, warnings = animations.extract_rows(image, rows)
    if warnings:
        raise ValueError(warnings)
    result = []
    for row in range(rows):
        figures, extraction = animations.extract_cells(image, row, columns, rows, bands)
        if extraction['warnings']:
            raise ValueError(extraction['warnings'])
        result.append(figures)
    return result


def compose(original, poses, columns, destination):
    sheet = Image.open(original).convert('RGBA')
    # Preserve the complete original top two rows without resampling.
    sheet.paste(Image.new('RGBA', (sheet.width, sheet.height // 2)), (0, sheet.height // 2))
    cw, ch = sheet.width / columns, sheet.height / 4
    for row, figures in enumerate(poses):
        cropped = [im.crop(im.getchannel('A').point(lambda a: 255 if a >= 32 else 0).getbbox()) for im in figures]
        scale = min((cw - 18) / max(im.width for im in cropped), (ch - 40) / max(im.height for im in cropped))
        for col, im in enumerate(cropped):
            im = im.resize((max(1, round(im.width * scale)), max(1, round(im.height * scale))), Image.Resampling.LANCZOS)
            sheet.paste(im, (round(col * cw + (cw - im.width) / 2), round((row + 3) * ch - 20 - im.height)))
    sheet.save(destination)


def main():
    poses = {key: cells(BATCH / f'hounds-{key}-source.png', n) for key, n in [('A', 7), ('B', 6)]}
    for key, n in [('A', 7), ('B', 6)]:
        compose(ROOT / f'assets/source/batches/ashen-idle-review-001/ashen-01-{key}-draft.png', poses[key], n, BATCH / f'ashen-01-{key}.png')
    fallback = [poses['A'][i][3:] + [poses['B'][i][j] for j in (1, 2, 5)] for i in range(2)]
    compose(ROOT / 'assets/source/batches/creature-animation-001/ashen-01-source.png', fallback, 7, BATCH / 'move-attack-fallback.png')
    strip = Image.open(ROOT / 'assets/source/batches/creature-animation-001/ashen-01-reference.png').convert('RGBA')
    for i, cid in enumerate(['scorchhound', 'hellmaw_hound']):
        strip.paste(Image.open(BATCH / f'references/creature_{cid}.png'), ((i + 2) * 128, 0))
    strip.save(BATCH / 'ashen-01-reference.png')
    for filename in ['creature_animations.json', 'creature_idle_animations.json']:
        path = ROOT / 'assets/specs' / filename
        spec = json.loads(path.read_text())
        group = next(g for g in spec['groups'] if g['id'] == 'ashen-01')
        group['reference'] = str((BATCH / 'ashen-01-reference.png').relative_to(ROOT))
        for unit in group['units'][2:]:
            ref = BATCH / f"references/creature_{unit['id']}.png"
            unit['reference_source'] = str(ref.relative_to(ROOT))
            unit['reference_sha256'] = digest(ref)
        if filename == 'creature_idle_animations.json':
            for key in ('A', 'B'):
                source = BATCH / f'ashen-01-{key}.png'
                group['sheets'][key]['source'] = str(source.relative_to(ROOT))
                group['sheets'][key]['source_sha256'] = digest(source)
        else:
            source = BATCH / 'move-attack-fallback.png'
            group['source'] = str(source.relative_to(ROOT))
            group['source_sha256'] = digest(source)
            group['prompt_file'] = str((BATCH / 'README.md').relative_to(ROOT))
        path.write_text(json.dumps(spec, indent=1 if 'idle' in filename else 2) + '\n')


if __name__ == '__main__':
    main()
