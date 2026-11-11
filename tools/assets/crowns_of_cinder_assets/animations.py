"""Reference-conditioned movement/attack sheets in the existing asset pipeline."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image

SIZE = (320, 256)
ANCHOR = (160, 207)


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def support(image: Image.Image) -> tuple[float, float, int]:
    """Register around the lower body, excluding the weapon's forward reach."""
    alpha = np.array(image.getchannel("A"))
    ys, xs = np.nonzero(alpha >= 96)
    if len(xs) < 20:
        raise ValueError("animation frame has no opaque figure")
    bottom, height = int(ys.max()) + 1, int(ys.max() - ys.min() + 1)
    band = ys >= bottom - max(4, int(height * .22))
    root = float(np.median(xs[band]))
    return root, float(bottom - 1), height


def body_root(image: Image.Image) -> float:
    alpha = np.array(image.getchannel("A"))
    ys, xs = np.nonzero(alpha >= 128)
    top, height = ys.min(), ys.max() - ys.min() + 1
    band = (ys >= top + height * .12) & (ys <= top + height * .44)
    return float(np.median(xs[band]))


def register(cells: list[Image.Image], reference: Image.Image, alpha_floor: int = 64) -> tuple[list[Image.Image], dict]:
    """One scale per unit, generous weapon space, and a stable reference anchor."""
    ref_root, ref_bottom, ref_height = support(reference)
    ref_body_root = body_root(reference)
    measures = [support(cell) for cell in cells]
    walk_height = float(np.median([m[2] for m in measures[:4]]))
    scale = ref_height / walk_height
    baseline = float(np.median([m[1] for m in measures[:4]]))
    # Reserve extra room for weapons without changing scale between poses.
    extents = []
    for cell, (root, _, _) in zip(cells, measures):
        box = cell.getchannel("A").point(lambda a: 255 if a >= 16 else 0).getbbox()
        extents += [root - box[0], box[2] - root]
    # Keep the approved figure scale; action canvases provide weapon space.
    registered, offsets, warnings = [], [], []
    for index, (cell, (root, _, _)) in enumerate(zip(cells, measures)):
        raw_box = cell.getchannel("A").point(lambda a: 255 if a >= 96 else 0).getbbox()
        if raw_box[1] == 0:
            warnings.append(f"frame {index}: inspect source-row boundary")
        resized = cell.resize((max(1, round(cell.width * scale)), max(1, round(cell.height * scale))), Image.Resampling.LANCZOS)
        if index < 4:
            # Register the torso, not the changing support feet of a gait.
            root = body_root(cell)
            target_root = ref_body_root
        else:
            target_root = ref_root
        x = round(ANCHOR[0] + target_root - 64 - root * scale)
        y = round(ANCHOR[1] + ref_bottom - 127 - baseline * scale)
        frame = Image.new("RGBA", SIZE)
        frame.paste(resized, (x, y))
        # Transparent RGB is retained; it cannot affect the game silhouette.
        pixels = np.array(frame)
        pixels[pixels[:,:,3] < alpha_floor] = 0
        frame = Image.fromarray(pixels)
        alpha = frame.getchannel("A")
        box = alpha.point(lambda a: 255 if a >= 32 else 0).getbbox()
        if not box or box[0] == 0 or box[1] == 0 or box[2] == SIZE[0]:
            warnings.append(f"frame {index}: inspect canvas clipping")
        if box and box[3] == SIZE[1] and measures[index][1] > baseline + 3:
            warnings.append(f"frame {index}: inspect lower edge")
        registered.append(frame)
        offsets.append([x, y])
    return registered, {"scale": scale, "baseline": baseline, "offsets": offsets, "warnings": warnings}



def gutter_seam(alpha: np.ndarray, nominal: int, radius: int) -> tuple[np.ndarray, bool]:
    """Find a transparent path between interleaved weapons and neighbouring bodies."""
    height, width = alpha.shape
    lo, hi = max(1, nominal-radius), min(width-1, nominal+radius)
    xs = np.arange(lo, hi)
    cost = (alpha[:,lo:hi] >= 64).astype(float)*1_000_000 + np.abs(xs-nominal)[None,:]*.01
    previous = cost[0].copy()
    back = np.zeros(cost.shape, dtype=np.int16)
    for y in range(1,height):
        choices = []
        for shift in [-2,-1,0,1,2]:
            values = np.roll(previous, shift) + abs(shift)*.1
            if shift > 0: values[:shift] = np.inf
            if shift < 0: values[shift:] = np.inf
            choices.append(values)
        choices = np.stack(choices)
        chosen = choices.argmin(axis=0)
        previous = choices.min(axis=0) + cost[y]
        back[y] = np.arange(hi-lo) - (chosen-2)
    at = int(previous.argmin())
    seam = np.zeros(height,dtype=int)
    for y in range(height-1,-1,-1):
        seam[y] = at+lo
        if y: at = int(back[y,at])
    return seam, bool((alpha[np.arange(height),seam] >= 64).any())


def encode_seam(seam):
    if np.all(seam == seam[0]):
        return int(seam[0])
    runs=[]
    start=0
    for index in range(1,len(seam)+1):
        if index == len(seam) or seam[index] != seam[start]:
            runs.append([start,index,int(seam[start])])
            start=index
    return {"runs":runs}


def extract_rows(sheet: Image.Image, rows: int):
    pixels = np.array(sheet)
    alpha = pixels[:,:,3]
    ink = (alpha >= 64).sum(axis=1)
    height = sheet.height/rows
    seams=[np.zeros(sheet.width,dtype=int)]
    warnings=[]
    for boundary in range(1,rows):
        nominal=round(boundary*height)
        candidates=range(max(1,round(nominal-height*.3)),min(sheet.height-1,round(nominal+height*.3)))
        cut=min(candidates,key=lambda y:(int(ink[y]),abs(y-nominal)))
        if ink[cut]:
            seam,touching=gutter_seam(alpha.T,nominal,round(height*.3))
            if touching: warnings.append(f"row boundary {boundary}: touching figures require manual review")
        else: seam=np.full(sheet.width,cut,dtype=int)
        seams.append(seam)
    seams.append(np.full(sheet.width,sheet.height,dtype=int))
    bands=[]
    for i in range(rows):
        top,bottom=seams[i],seams[i+1]
        lo,hi=int(top.min()),int(bottom.max())
        image=pixels[lo:hi].copy()
        y=np.arange(lo,hi)[:,None]
        image[(y<top[None,:]) | (y>=bottom[None,:])]=0
        bands.append((Image.fromarray(image),{"bounds":[lo,hi],"top_seam":encode_seam(top),"bottom_seam":encode_seam(bottom)}))
    return bands,warnings


def extract_cells(sheet: Image.Image, row: int, columns: int, rows: int, row_data=None) -> tuple[list[Image.Image], dict]:
    """Follow transparent gutters, including bent seams around projecting weapons."""
    if row_data is None:
        row_data, _ = extract_rows(sheet, rows)
    row_image, row_info = row_data[row]
    top, bottom = row_info["bounds"]
    band = np.array(row_image)
    alpha = band[:,:,3]
    ink = (alpha >= 64).sum(axis=0)
    seams = [np.zeros(band.shape[0],dtype=int)]
    cuts, warnings, bent = [0], [], {}
    width = sheet.width/columns
    for boundary in range(1,columns):
        nominal = round(boundary*width)
        candidates = range(max(1,round(nominal-width*.34)),min(sheet.width-1,round(nominal+width*.34)))
        cut = min(candidates,key=lambda x:(int(ink[x]),abs(x-nominal)))
        if ink[cut]:
            seam, crosses_figure = gutter_seam(alpha,nominal,round(width*.34))
            bent[str(boundary)] = encode_seam(seam)
            if crosses_figure:
                warnings.append(f"boundary {boundary}: touching silhouettes require manual review")
        else:
            seam = np.full(band.shape[0],cut,dtype=int)
        seams.append(seam)
        cuts.append(cut)
    seams.append(np.full(band.shape[0],sheet.width,dtype=int));cuts.append(sheet.width)
    cells=[]
    for i in range(columns):
        left,right=seams[i],seams[i+1]
        lo,hi=int(left.min()),int(right.max())
        pixels=band[:,lo:hi].copy()
        x=np.arange(lo,hi)[None,:]
        pixels[(x<left[:,None]) | (x>=right[:,None])] = 0
        cells.append(Image.fromarray(pixels))
    return cells,{"row_bounds":[top,bottom],"column_cuts":cuts,"bent_seams":bent,"warnings":warnings, "row_extraction":row_info}


def build(root: Path, out_root: Path | None = None) -> dict:
    out = out_root or root
    spec_path = root / "assets/specs/creature_animations.json"
    if not spec_path.is_file():
        return {}
    from .creatures_auto import load_creatures
    creatures = load_creatures(root / "data")
    from .dlc import creature_definitions
    optional_creatures = creature_definitions(root)
    creatures.update(optional_creatures)
    spec = json.loads(spec_path.read_text())
    manifest = {"schema_version": 1, "frame_size": list(SIZE), "anchor": list(ANCHOR), "units": {}, "pending": [], "atlases": {}, "qc": {}}
    if optional_creatures:
        manifest["optional_creatures"] = sorted(optional_creatures)
    groups = spec["groups"] + spec.get("hero_groups", [])
    for group in groups:
        source = root / group["source"]
        prefix = "hero_" if group.get("category") == "hero" else "creature_"
        if not source.is_file() or "source_sha256" not in group:
            manifest["pending"] += [prefix + u["id"] for u in group["units"]]
            continue
        if digest(source) != group["source_sha256"]:
            raise ValueError(f"{group['id']}: unreviewed animation source change")
        sheet = Image.open(source).convert("RGBA")
        columns, rows = group["grid"]
        row_data, row_warnings = extract_rows(sheet, rows)
        atlas = Image.new("RGBA", (8 * SIZE[0], len(group["units"]) * SIZE[1]))
        atlas_name = "animation_" + group["id"]
        relative = f"assets/atlases/{atlas_name}.png"
        for row, unit in enumerate(group["units"]):
            cid = unit["id"]
            if prefix == "creature_" and cid not in creatures:
                raise ValueError(f"unknown creature {cid}")
            sid = prefix + cid
            ref_path = root / unit["reference_source"]
            if digest(ref_path) != unit["reference_sha256"]:
                raise ValueError(f"{sid}: approved reference changed; review animation continuity")
            reference = Image.open(ref_path).convert("RGBA")
            cells, extraction = extract_cells(sheet, row, columns, rows, row_data)
            frames, qc = register(cells, reference, int(spec.get("alpha_floor", 64)))
            qc["extraction"] = extraction
            qc["warnings"] += extraction["warnings"] + row_warnings
            manifest["qc"][sid] = qc
            rest = Image.new("RGBA", SIZE)
            rest.paste(reference, (96, 80))
            for c, frame in enumerate([rest, *frames]):
                atlas.paste(frame, (c*SIZE[0], row*SIZE[1]))
            def rect(c):
                return [c*SIZE[0], row*SIZE[1], *SIZE]
            actions = {"move": {"frames": [rect(c) for c in range(1, 5)], "durations_ms": ([80]*4 if prefix == "hero_" else [150]*4), "loop": True}}
            if columns == 7:
                actions["attack"] = {"frames": [rect(c) for c in [5, 6, 7, 0]], "durations_ms": [180, 120, 180, 120], "loop": False, "events": [{"time_ms": 180, "name": "impact"}]}
            manifest["units"][sid] = {"atlas": atlas_name, "actions": actions, "quality_status": "animation_candidate", "source": group["source"], "source_sha256": group["source_sha256"]}
        destination = out / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        atlas.save(destination, optimize=True)
        manifest["atlases"][atlas_name] = {"path": "res://" + relative, "size": list(atlas.size)}
    from . import idle_animations
    idle_animations.build(root, out, manifest)
    from . import model_animations
    model_animations.build(root, out, manifest)
    destination = out / "assets/animations.json"
    destination.write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest


_ATLAS_CACHE: dict = {}


def _atlas(out: Path, manifest: dict, name: str) -> Image.Image:
    path = out / manifest["atlases"][name]["path"].removeprefix("res://")
    key = (str(path), path.stat().st_mtime)
    if key not in _ATLAS_CACHE:
        _ATLAS_CACHE[key] = Image.open(path).convert("RGBA")
    return _ATLAS_CACHE[key]


def validate(root: Path, out_root: Path | None = None) -> list[str]:
    out = out_root or root
    path = out / "assets/animations.json"
    if not path.is_file():
        return ["animation manifest missing"] if (root / "assets/specs/creature_animations.json").is_file() else []
    manifest = json.loads(path.read_text())
    errors = []
    for sid, qc in manifest.get("qc", {}).items():
        errors.extend(f"{sid}: {warning}" for warning in qc["warnings"])
    for sid, unit in manifest["units"].items():
        for action, clip in unit["actions"].items():
            hashes = []
            for index, (x, y, w, h) in enumerate(clip["frames"]):
                per_frame = clip.get("frame_atlases", [])
                atlas_name = per_frame[index] if index < len(per_frame) else clip.get("atlas", unit["atlas"])
                image = _atlas(out, manifest, atlas_name)
                if x < 0 or y < 0 or x+w > image.width or y+h > image.height:
                    errors.append(f"{sid}/{action}: frame outside atlas")
                    continue
                frame = image.crop((x,y,x+w,y+h))
                if frame.getchannel("A").getbbox() is None:
                    errors.append(f"{sid}/{action}: empty frame")
                hashes.append(hashlib.sha256(frame.tobytes()).hexdigest())
            if len(set(hashes)) < 2:
                errors.append(f"{sid}/{action}: no distinct animation poses")
    return errors
