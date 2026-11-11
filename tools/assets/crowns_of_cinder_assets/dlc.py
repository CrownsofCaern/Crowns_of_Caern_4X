"""Optional art packs use the existing sprite, animation and town pipelines.

This manifest records the art contract; gameplay data lives separately.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image

SPEC = 'dlc_factions.json'


def read(root: Path) -> dict:
    path = root / 'assets/specs' / SPEC
    return json.loads(path.read_text()) if path.is_file() else {}


def creature_definitions(root: Path) -> dict:
    return read(root).get('creatures', {})


def town_definitions(root: Path) -> dict:
    doc = read(root)
    return {fid: {'buildings': {bid: doc['buildings'][bid] for bid in f['building_ids']}}
            for fid, f in doc.get('factions', {}).items()}


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def stage(root: Path, batch_id: str | None = None) -> None:
    """Reproduce source isolation with the same adaptive gutters as animations.

    Hashes make originals immutable after staging. Only this unapproved DLC
    pack's generated crops are writable; established assets cannot be replaced.
    """
    from .animations import extract_rows, extract_cells
    from .postprocess import crop_to_content
    doc = read(root)
    specs = {s['id']: s for s in doc['assets']}
    for job in doc['batches']:
        if batch_id and job['id'] != batch_id:
            continue
        path = root / job['source']
        if not path.is_file():
            continue
        digest = sha(path)
        if job.get('source_sha256', digest) != digest:
            raise ValueError(job['id'] + ': archived source changed')
        job['source_sha256'] = digest
        with Image.open(path) as raw:
            image = raw.convert('RGBA')
        metadata = {'schema_version': 1, 'provider': 'ChatGPT image_gen', 'batch': 'dlc-factions-001',
                    'source_sheet': job['source'], 'source_sheet_sha256': digest,
                    'size': list(image.size), 'prompt_file': job['prompt_file'],
                    'prompt_sha256': sha(root/job['prompt_file']),
                    'conditioning': [job['reference'], f"assets/source/batches/dlc-factions-001/{job['faction']}-creatures.png"] if job['kind'] != 'creatures' else [job['reference']],
                    'quality_status': 'pending_visual_review'}
        metadata['reference_hashes'] = {p: sha(root/p) for p in metadata['conditioning']}
        if job['kind'] != 'foundation':
            cols, rows = job['grid']
            row_data, row_warnings = extract_rows(image, rows)
            extraction = []
            for row in range(rows):
                cells, qc = extract_cells(image,row,cols,rows,row_data)
                for col, cell in enumerate(cells):
                    sid = job['asset_ids'][row*cols+col]
                    destination = root/'assets/source/generated'/f'{sid}.png'
                    own = destination.with_suffix('.json')
                    if destination.is_file() and (not own.is_file() or json.loads(own.read_text()).get('batch') != 'dlc-factions-001'):
                        raise ValueError(sid + ': refusing to overwrite established art')
                    pixels = np.array(cell)
                    pixels[pixels[:,:,3] < 64] = 0
                    cell = crop_to_content(Image.fromarray(pixels),64)
                    destination.parent.mkdir(parents=True,exist_ok=True)
                    cell.save(destination)
                    record = {**metadata,'asset_id':sid,'row':row,'column':col,'extraction':qc,
                              'source_sha256':sha(destination),'native_size':specs[sid]['size'],
                              'processing':'Adaptive transparent gutters; alpha below 64 cleared; palette preserved'}
                    own.write_text(json.dumps(record,indent=2)+'\n')
                    extraction.append({'id':sid,'row':row,'column':col,'size':list(cell.size),
                                       'warnings':row_warnings+qc['warnings']})
            metadata['extraction'] = extraction
        path.with_suffix('.json').write_text(json.dumps(metadata,indent=2)+'\n')
    (root/'assets/specs'/SPEC).write_text(json.dumps(doc,indent=2)+'\n')
    _sync_towns(root, doc)
    _stage_animation_metadata(root)


def _sync_towns(root: Path, doc: dict) -> None:
    path = root/'assets/specs/town_scenes.json'
    scenes = json.loads(path.read_text())
    for fid, faction in doc['factions'].items():
        foundation = next(j for j in doc['batches'] if j['faction'] == fid and j['kind'] == 'foundation')
        background = root/foundation['source']
        sources = {bid: root/'assets/source/generated'/f'building_{bid}.png' for bid in faction['building_ids']}
        if not background.is_file() or not all(p.is_file() for p in sources.values()):
            continue
        slots = json.loads(json.dumps(faction['town_slots']))
        assets = {bid:{'source':str(p.relative_to(root)),'sha256':sha(p)} for bid,p in sources.items()}
        prefix = 'de' if fid == 'darkelf' else 'fm'
        ultimate = prefix + '_ultimate'
        gameplay = json.loads((root/'data/buildings.json').read_text())['towns'].get(fid, {})
        if ultimate in gameplay.get('buildings', {}):
            ultimate_path = root / f'assets/source/generated/town_{fid}_{ultimate}.png'
            if ultimate_path.is_file():
                slots.append({'id':ultimate,'variants':[ultimate],'at':[800,520],'size':[300,260]})
                assets[ultimate] = {'source':str(ultimate_path.relative_to(root)),'sha256':sha(ultimate_path)}
            else:
                next(slot for slot in slots if slot['id'] == 'civic')['variants'].append(ultimate)
                assets[ultimate] = {'same_as': prefix + '_exchequer'}
        with Image.open(background) as image:
            size = list(image.size)
        scenes['factions'][fid] = {
            'size': size,
            'background': {'source':foundation['source'],'sha256':sha(background)},
            'assets': assets,
            'slots': slots}
    path.write_text(json.dumps(scenes,indent=2)+'\n')


def _stage_animation_metadata(root: Path) -> None:
    path = root/'assets/specs/creature_animations.json'
    doc = json.loads(path.read_text())
    for group in doc['groups'] + doc.get('hero_groups', []):
        if not group.get('dlc'):
            continue
        source = root/group['source']
        if not source.is_file():
            continue
        digest = sha(source)
        if group.get('source_sha256', digest) != digest:
            raise ValueError(group['id'] + ': archived animation changed')
        group.update(source_sha256=digest,generation_status='generated',quality_status='animation_candidate')
        source.with_suffix('.json').write_text(json.dumps({
            'schema_version':1,'provider':'ChatGPT image_gen','batch':'dlc-animation-001',
            'source':group['source'],'source_sha256':digest,'size':list(Image.open(source).size),
            'prompt_file':group['prompt_file'],'prompt_sha256':sha(root/group['prompt_file']),
            'conditioning':[group['reference']], 'reference_sha256':sha(root/group['reference']),
            'units':[u['id'] for u in group['units']], 'grid':group['grid'],
            'processing':'Existing animation extraction and registration; native 128px reference; 320x256 action canvas',
            'quality_status':'animation_candidate'},indent=2)+'\n')
    path.write_text(json.dumps(doc,indent=2)+'\n')


def validate(root: Path) -> list[str]:
    doc = read(root)
    if not doc:
        return []
    errors = []
    ids = {s['id'] for s in doc['assets']}
    if doc.get('activation') != 'art_only_optional_pack' or doc.get('story_links'):
        errors.append('DLC: art pack must not implicitly activate campaigns or gameplay')
    for fid, faction in doc['factions'].items():
        if faction.get('campaigns'):
            errors.append(fid + ': standalone art pack must not attach a campaign')
        roster = [doc['creatures'][cid] for cid in faction['creature_ids']]
        if len(roster) != 16 or sorted(c['tier'] for c in roster) != [t for t in range(1,9) for _ in range(2)]:
            errors.append(fid + ': expected 8 base/upgrade pairs')
        for c in roster:
            other = doc['creatures'].get(c.get('upgrade',c.get('upgrade_of')), {})
            reverse = 'upgrade' if c.get('upgrade_of') else 'upgrade_of'
            if other.get(reverse) != c['id'] or other.get('tier') != c['tier'] or other.get('faction') != fid:
                errors.append(c['id'] + ': invalid upgrade relationship')
            if 'creature_'+c['id'] not in ids:
                errors.append(c['id'] + ': missing art spec')
    for job in doc['batches']:
        source = root/job['source']
        if not source.is_file() or sha(source) != job.get('source_sha256'):
            errors.append(job['id'] + ': missing/changed source')
        for sid in job['asset_ids']:
            if not (root/'assets/source/generated'/f'{sid}.png').is_file():
                errors.append(sid + ': crop missing')
    return errors
