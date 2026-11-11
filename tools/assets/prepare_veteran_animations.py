"""Stage generated level-five clips separately from approved runtime animations.

Requires Pillow, NumPy, and the current asset pipeline (optionally --pipeline-root).
Original sheets and prompts stay immutable; QC warnings remain in the manifest.
"""
from pathlib import Path
import argparse
import hashlib
import importlib
import json
import sys

from PIL import Image, ImageDraw


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--pipeline-root', type=Path)
    args = parser.parse_args()
    root = args.root.resolve()
    sys.path.insert(0, str((args.pipeline_root or root) / 'tools/assets'))
    try:
        pipeline = importlib.import_module('crowns_of_cinder_assets.animations')
    except ModuleNotFoundError:
        pipeline = importlib.import_module('reignem_assets.animations')
    batch = root / 'assets/source/batches/veteran-animation-001'
    output = root / 'assets/build/veteran_animations'
    output.mkdir(parents=True, exist_ok=True)
    previews = output / 'previews'
    previews.mkdir(exist_ok=True)
    plan = json.loads((batch / 'plan.json').read_text())
    manifest = {'schema_version': 1, 'veteran_level': 5,
                'quality_status': 'runtime_enabled',
                'runtime_enabled': True, 'frame_size': list(pipeline.SIZE),
                'anchor': list(pipeline.ANCHOR), 'units': {}, 'warnings': []}
    faction_frames = {}
    reference_cache = {}
    for group in plan['groups']:
        source = batch / group['source']
        if hashlib.sha256(source.read_bytes()).hexdigest() != group['source_sha256']:
            raise ValueError(f'{source}: source hash differs from plan')
        sheet = Image.open(source).convert('RGBA')
        if sheet.getchannel('A').histogram()[0] == 0:
            raise ValueError(f'{source}: missing transparent background')
        rows, row_warnings = pipeline.extract_rows(sheet, 4)
        reference_path = root / group['reference']
        if reference_path not in reference_cache:
            ref_sheet = Image.open(reference_path).convert('RGBA')
            ref_rows, _ = pipeline.extract_rows(ref_sheet, 2)
            references = []
            for row in range(2):
                cells, _ = pipeline.extract_cells(ref_sheet, row, 4, 2, ref_rows)
                for cell in cells:
                    box = cell.getchannel('A').point(lambda a: 255 if a >= 96 else 0).getbbox()
                    cropped = cell.crop(box)
                    cropped.thumbnail((112, 112), Image.Resampling.LANCZOS)
                    native = Image.new('RGBA', (128, 128))
                    native.paste(cropped, ((128-cropped.width)//2, 127-cropped.height))
                    references.append(native)
            reference_cache[reference_path] = references
        for row, unit in enumerate(group['units']):
            cells, extraction = pipeline.extract_cells(sheet, row, 7, 4, rows)
            reference = reference_cache[reference_path][unit['tier']-1]
            frames, qc = pipeline.register(cells, reference)
            qc['warnings'] += extraction['warnings'] + row_warnings
            unit_dir = output / unit['id']
            unit_dir.mkdir(exist_ok=True)
            rest = Image.new('RGBA', pipeline.SIZE)
            rest.paste(reference, (96, 80))
            actions = {}
            for action, sequence, durations in [('move', frames[:4], [150]*4),
                                                ('attack', frames[4:]+[rest], [180,120,180,120])]:
                if len({hashlib.sha256(f.tobytes()).hexdigest() for f in sequence}) < 2:
                    raise ValueError(f'{unit["id"]}/{action}: repeated still only')
                if any(f.getchannel('A').getbbox() is None for f in sequence):
                    raise ValueError(f'{unit["id"]}/{action}: empty frame')
                strip = Image.new('RGBA', (pipeline.SIZE[0]*len(sequence), pipeline.SIZE[1]))
                for index, frame in enumerate(sequence):
                    strip.paste(frame, (index*pipeline.SIZE[0], 0))
                destination = unit_dir / (action+'.png')
                strip.save(destination)
                actions[action] = {'path': str(destination.relative_to(root)),
                                   'frame_count': len(sequence), 'durations_ms': durations,
                                   'loop': action == 'move'}
                if action == 'attack':
                    actions[action]['events'] = [{'time_ms': 180, 'name': 'impact'}]
            manifest['units'][unit['id']] = {**unit, 'faction': group['faction'],
                'source': str(source.relative_to(root)), 'source_sha256': group['source_sha256'],
                'actions': actions, 'qc': qc}
            manifest['warnings'] += [unit['id']+': '+w for w in qc['warnings']]
            faction_frames.setdefault(group['faction'], []).append((unit, frames+[rest]))
    for faction, units in faction_frames.items():
        sequence = []
        for index in range(8):
            canvas = Image.new('RGB', (1024, 448), '#191a20')
            draw = ImageDraw.Draw(canvas)
            for position, (unit, frames) in enumerate(units):
                x, y = position % 4 * 256, position // 4 * 224
                frame = frames[index].resize((256, 205), Image.Resampling.LANCZOS)
                canvas.paste(frame, (x,y+19), frame)
                draw.text((x+8,y+5), 'T%d %s' % (unit['tier'], unit['name']), fill='#e8dfc9')
            sequence.append(canvas)
        sequence[0].save(previews / (faction+'.gif'), save_all=True, append_images=sequence[1:],
                         duration=[150,150,150,150,180,120,180,400], loop=0)
        sequence[0].save(previews / (faction+'.png'))
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
    viewer = '''<!doctype html><meta charset="utf-8"><title>Veteran level 5 animation review</title>
<style>body{background:#17191f;color:#ece5d7;font:16px system-ui;margin:24px}select,button{font:inherit;margin:8px;padding:8px;background:#30333f;color:inherit}main{display:grid;grid-template-columns:repeat(4,minmax(200px,1fr));gap:12px}article{background:#22252e;padding:12px;border-radius:8px}canvas{width:100%;image-rendering:auto}h2{font-size:14px}p{color:#bab8b2}</style>
<h1>Veteran level 5 animations</h1><p>Candidate artwork · four movement poses · three attack poses plus rest. Review before gameplay activation.</p>
<select id="faction"></select><select id="action"><option>move</option><option>attack</option></select><button id="pause">Pause</button><main></main>
<script>const pack=PACK;let playing=true,time=0,last=performance.now();
const faction=document.querySelector('#faction'),action=document.querySelector('#action'),grid=document.querySelector('main');
for(const f of [...new Set(Object.values(pack.units).map(u=>u.faction))])faction.add(new Option(f,f));
let cards=[];function rebuild(){grid.replaceChildren();cards=[];for(const u of Object.values(pack.units).filter(u=>u.faction===faction.value)){const article=document.createElement('article'),heading=document.createElement('h2'),canvas=document.createElement('canvas');heading.textContent='T'+u.tier+' · '+u.name;canvas.width=320;canvas.height=256;article.append(heading,canvas);grid.append(article);const image=new Image();image.src=u.actions[action.value].path.split('veteran_animations/')[1];cards.push({u,canvas,image});}time=0;}
faction.onchange=action.onchange=rebuild;document.querySelector('#pause').onclick=e=>{playing=!playing;e.target.textContent=playing?'Pause':'Play';};
function tick(now){if(playing)time+=Math.min(now-last,100);last=now;for(const {u,canvas,image} of cards){const a=u.actions[action.value],durations=a.durations_ms,total=durations.reduce((a,b)=>a+b,0)+(action.value==='attack'?500:0);let t=time%total,index=3;for(let i=0;i<durations.length;i++){if(t<durations[i]){index=i;break;}t-=durations[i];}const ctx=canvas.getContext('2d');ctx.clearRect(0,0,320,256);if(image.complete&&image.naturalWidth)ctx.drawImage(image,index*320,0,320,256,0,0,320,256);}requestAnimationFrame(tick);}rebuild();requestAnimationFrame(tick);</script>'''
    (output / 'preview.html').write_text(viewer.replace('PACK', json.dumps(manifest)))
    print(f'Staged {len(manifest["units"])} creatures / 128 clips; {len(manifest["warnings"])} QC warnings')


if __name__ == '__main__':
    main()
