"""Ultimate town artwork, using the existing town-layer export pipeline."""
from pathlib import Path
import hashlib
import json

import numpy as np
from PIL import Image


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def render(root: Path, asset: dict) -> bytes:
    """Existing reviewed exports are frozen inputs; new art keeps its recipe."""
    import io
    source = root/asset['source']
    if digest(source) != asset['source_sha256']:
        raise ValueError(asset['id'] + ': original source changed')
    if asset.get('prepared_input'):
        prepared = root/asset['prepared_input']
        if digest(prepared) != asset['prepared_input_sha256']:
            raise ValueError(asset['id'] + ': reviewed native source changed')
        return prepared.read_bytes()
    with Image.open(source) as original:
        image = original.convert('RGBA')
    pixels = np.array(image)
    pixels[pixels[:,:,3] < int(asset.get('alpha_floor',64))] = 0
    image = Image.fromarray(pixels)
    bounds = image.getchannel('A').getbbox()
    if bounds is None:
        raise ValueError(asset['id'] + ': empty building')
    image = image.crop(bounds)
    image.thumbnail((350,350),Image.Resampling.LANCZOS)
    output = io.BytesIO()
    image.save(output,format='PNG')
    return output.getvalue()


def stage(root: Path) -> None:
    path = root/'assets/specs/ultimate_buildings.json'
    spec = json.loads(path.read_text())
    towns_path = root/'assets/specs/town_scenes.json'
    towns = json.loads(towns_path.read_text())
    for asset in spec['assets']:
        encoded = render(root,asset)
        destination = root/asset['output']
        expected = hashlib.sha256(encoded).hexdigest()
        if destination.is_file() and digest(destination) not in [expected,asset.get('output_sha256')]:
            raise ValueError(asset['id'] + ': refusing to overwrite changed prepared artwork')
        destination.parent.mkdir(parents=True,exist_ok=True)
        destination.write_bytes(encoded)
        with Image.open(destination) as image:
            asset.update(output_sha256=expected,size=list(image.size))
        scene = towns['factions'][asset['faction']]
        scene['assets'][asset['building_id']] = {'source':asset['output'],'sha256':expected}
    path.write_text(json.dumps(spec,indent=2)+'\n')
    towns_path.write_text(json.dumps(towns,indent=2)+'\n')


def validate(root: Path, out_root: Path | None = None) -> list[str]:
    spec_path = root/'assets/specs/ultimate_buildings.json'
    if not spec_path.is_file():
        return []
    spec = json.loads(spec_path.read_text())
    definitions = json.loads((root/'data/buildings.json').read_text())['towns']
    wanted = {(fid,bid) for fid,town in definitions.items() for bid,b in town['buildings'].items() if b['category']=='ultimate'}
    actual = {(a['faction'],a['building_id']) for a in spec['assets']}
    errors=[]
    if wanted != actual or len(actual) != len(spec['assets']):
        errors.append('ultimate artwork must cover every actual ultimate exactly once')
    for asset in spec['assets']:
        try:
            encoded=render(root,asset)
        except (OSError,ValueError) as error:
            errors.append(str(error))
            continue
        source=root/asset['output']
        if not source.is_file() or encoded != source.read_bytes():
            errors.append(asset['id']+': stale prepared export')
            continue
        with Image.open(source) as original:
            image=original.convert('RGBA')
        if max(image.size)!=350 or image.getchannel('A').getextrema()[0]!=0 or image.getchannel('A').getbbox() is None:
            errors.append(asset['id']+': expected nonempty transparent 350px building')
        runtime=(out_root or root)/'assets/towns'/asset['faction']/(asset['building_id']+'.png')
        if not runtime.is_file() or runtime.read_bytes()!=encoded:
            errors.append(asset['id']+': town layer is missing or differs from prepared art')
    return errors
