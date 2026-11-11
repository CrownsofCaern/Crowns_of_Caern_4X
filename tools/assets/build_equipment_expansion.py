#!/usr/bin/env python3
"""Export and validate the artwork-only equipment-002 library (no gameplay changes)."""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw
from crowns_of_cinder_assets import postprocess
from crowns_of_cinder_assets.palette import Palette

ROOT = Path(__file__).resolve().parents[2]
SPEC = ROOT / 'assets/specs/batches/equipment-002.json'
SOURCE = ROOT / 'assets/source/equipment-002'
DEST = ROOT / 'assets/equipment/expansion_002'


def sheet(entries: list[dict], path: Path, size: int = 128, columns: int = 7) -> None:
    cell_w, cell_h = max(170, size + 20), size + 45
    canvas = Image.new('RGB', (columns * cell_w, ((len(entries)+columns-1)//columns)*cell_h), '#211c18')
    draw = ImageDraw.Draw(canvas)
    colors = {'minor':'#b9ae98','major':'#ccc8d8','relic':'#d5af6c','legendary':'#efce72'}
    for i, entry in enumerate(entries):
        x, y = (i % columns)*cell_w, (i//columns)*cell_h
        with Image.open(DEST / f'{size}' / entry['source']) as item:
            canvas.paste(item, (x+(cell_w-size)//2,y+4), item)
        title = entry['name']
        # Wrap names without sacrificing the item preview size.
        words, lines, line = title.split(), [], ''
        for word in words:
            candidate = (line+' '+word).strip()
            if draw.textbbox((0,0),candidate)[2] > cell_w-10 and line:
                lines.append(line)
                line = word
            else:
                line = candidate
        lines.append(line)
        for j, line in enumerate(lines[:2]):
            draw.text((x+6,y+size+5+j*12),line,fill=colors[entry['quality']])
        draw.text((x+6,y+size+31),f"{entry['quality']} / {entry['slot']}",fill='#928675')
    canvas.save(path, quality=92)


def build(allow_partial: bool = False) -> dict:
    spec = json.loads(SPEC.read_text())
    entries = spec['assets']
    assert len(entries) > 100
    old_ids = set(json.loads((ROOT/'data/artifacts.json').read_text())['artifacts'])
    assert len({a['id'] for a in entries}) == len(entries)
    assert not old_ids.intersection(a['id'] for a in entries)
    missing = [a['id'] for a in entries if not (SOURCE/a['source']).is_file()]
    if missing and not allow_partial:
        raise FileNotFoundError(f'{len(missing)} missing source paintings: {missing}')
    palette = Palette.load(ROOT/'assets/specs/palette.json')
    hashes = set()
    ready = []
    for entry in entries:
        source = SOURCE/entry['source']
        if not source.is_file():
            continue
        digest = hashlib.sha256(source.read_bytes()).hexdigest()
        assert digest not in hashes, f"Duplicate source: {entry['id']}"
        hashes.add(digest)
        with Image.open(source) as raw:
            assert raw.mode == 'RGBA', f'Expected transparent RGBA: {source}'
            alpha = raw.getchannel('A')
            assert alpha.getextrema()[0] == 0 and alpha.getextrema()[1] >= 128, f'Invalid transparency: {source}'
            entry['source_size'] = list(raw.size)
            for size in (64,128):
                export_spec = {**spec, 'size':[size,size]}
                image = postprocess.process_generated(raw, export_spec, palette)
                assert image.size == (size,size) and image.getbbox()
                assert image.getpixel((0,0))[3] == 0
                dest = DEST/f'{size}'/entry['source']
                dest.parent.mkdir(parents=True,exist_ok=True)
                image.save(dest,optimize=True)
        entry.update(status='generated_exported',sha256=digest,
                     exports={str(s):f'assets/equipment/expansion_002/{s}/{entry["source"]}' for s in (64,128)})
        ready.append(entry)
    SOURCE.mkdir(parents=True,exist_ok=True)
    if ready:
        sheet(ready,SOURCE/'contact-sheet.jpg')
        sheet(ready,SOURCE/'contact-sheet-64.jpg',64)
        for quality in ('minor','major','relic','legendary'):
            subset = [a for a in ready if a['quality']==quality]
            if subset:
                sheet(subset,SOURCE/f'{quality}-contact-sheet.jpg')
    report = {'expected':len(entries),'generated':len(ready),'missing':missing,
              'qualities':dict(Counter(a['quality'] for a in ready)),
              'slots':dict(Counter(a['slot'] for a in ready)),
              'unique_source_hashes':len(hashes),'transparent_sources_checked':len(ready),
              'exports_per_size':len(ready),'gameplay_integrated':False}
    manifest = {**spec,'assets':entries,'validation':report}
    (SOURCE/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    (SOURCE/'validation.json').write_text(json.dumps(report,indent=2)+'\n')
    return report


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--allow-partial',action='store_true')
    print(json.dumps(build(parser.parse_args().allow_partial),indent=2))
