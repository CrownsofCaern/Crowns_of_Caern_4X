"""Cut a fused pole weapon (pike, spear, halberd) out of an image-to-3D model.

  python3 tools/assets/split_weapon.py ID [--bone mixamorig:RightHand]

Image-to-3D models come as one welded mesh, so the auto-rigger spreads the
weapon over the arm, the spine and the legs and every animation bends it.
This finds the shaft as the straight line through the part of the model that
rises above the head (a pole held upright towers over the helmet), refits it
along the whole pole, removes the shaft and blade triangles from every GLB the
unit's clips use (rewritten in place: keep the downloads to start over), and
records the pole in assets/specs/creature_models.json as unit["weapon"]. The
renderer then puts a clean rigid pole of the same size in the hand bone, so it
stays straight in every pose (and the same attachment serves a real-time game).
"""
from __future__ import annotations

import argparse
import json
import struct
from pathlib import Path

import numpy as np

COMPONENT = {5121: np.uint8, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
WIDTH = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


class Glb:
    def __init__(self, path: Path):
        data = path.read_bytes()
        magic, _, _ = struct.unpack_from("<III", data, 0)
        if magic != 0x46546C67:
            raise SystemExit(f"{path}: not a GLB")
        n = struct.unpack_from("<I", data, 12)[0]
        self.json = json.loads(data[20:20 + n])
        m = struct.unpack_from("<I", data, 20 + n)[0]
        self.bin = bytearray(data[28 + n:28 + n + m])
        self.path = path

    def view(self, accessor_index: int) -> np.ndarray:
        """A writable numpy view of an accessor (tightly packed only)."""
        acc = self.json["accessors"][accessor_index]
        bv = self.json["bufferViews"][acc["bufferView"]]
        dtype = COMPONENT[acc["componentType"]]
        width = WIDTH[acc["type"]]
        if bv.get("byteStride", 0) not in (0, np.dtype(dtype).itemsize * width):
            raise SystemExit(f"{self.path}: interleaved buffers are not supported")
        start = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
        return np.frombuffer(self.bin, dtype=dtype, count=acc["count"] * width, offset=start).reshape(acc["count"], width)

    def save(self) -> None:
        text = json.dumps(self.json, separators=(",", ":")).encode()
        text += b" " * (-len(text) % 4)
        body = bytes(self.bin) + b"\0" * (-len(self.bin) % 4)
        total = 12 + 8 + len(text) + 8 + len(body)
        out = struct.pack("<III", 0x46546C67, 2, total) + struct.pack("<II", len(text), 0x4E4F534A) + text
        out += struct.pack("<II", len(body), 0x004E4942) + body
        self.path.write_bytes(out)



def pole(pos: np.ndarray) -> dict:
    """The pole's axis, radius and the vertices it covers (bind space)."""
    y = pos[:, 1]
    lo, hi = float(y.min()), float(y.max())
    h = hi - lo
    # 77-84% of the height is pole only on a pikeman: the helmet ends below,
    # the blade starts above. Fit there, then refit along the whole shaft.
    band = (y > lo + 0.77 * h) & (y < lo + 0.84 * h)
    if band.sum() < 20:
        raise SystemExit("no pole above the head: is this a pole-weapon unit?")

    def fit(mask: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
        pts = pos[mask]
        centre = pts.mean(axis=0)
        axis = np.linalg.svd(pts - centre, full_matrices=False)[2][0]
        return centre, axis / np.linalg.norm(axis) * (1 if axis[1] >= 0 else -1)

    def distance(centre, axis) -> np.ndarray:
        rel = pos - centre
        return np.linalg.norm(rel - np.outer(rel @ axis, axis), axis=1)

    centre, axis = fit(band)
    radius = float(np.percentile(distance(centre, axis)[band], 90))
    # Refit on the upper shaft only: generated shafts bend towards the butt.
    for _ in range(4):
        centre, axis = fit((distance(centre, axis) <= radius * 1.25) & (y > lo + 0.4 * h) & (y < lo + 0.84 * h))
    d = distance(centre, axis)
    # Generated shafts are rarely dead straight: allow more slack far from
    # the fitted band (towards the butt end on the ground).
    slack = radius * 1.4 + 0.08 * np.clip((lo + 0.77 * h - y) / h, 0, None) * h
    shaft = (d <= slack) & (y < lo + 0.84 * h)
    blade = (y >= lo + 0.84 * h) & (d <= radius * 5)
    chosen = shaft | blade
    along = (pos[chosen] - centre) @ axis
    bottom, top = centre + axis * along.min(), centre + axis * along.max()
    blade_start = float(((pos[blade] - centre) @ axis).min()) if blade.any() else float(along.max())
    return {"mask": chosen, "start": bottom.round(4).tolist(), "end": top.round(4).tolist(),
            "radius": round(radius * 0.8, 4), "blade_length": round(float(along.max()) - blade_start, 4),
            "blade_width": round(float(np.percentile(d[blade], 95)) * 2, 4) if blade.any() else round(radius * 4, 4)}


def components(vertex_count: int, tri: np.ndarray) -> np.ndarray:
    """Connected-component label per vertex (min-label propagation)."""
    label = np.arange(vertex_count)
    a, b = np.r_[tri[:, 0], tri[:, 1], tri[:, 2]], np.r_[tri[:, 1], tri[:, 2], tri[:, 0]]
    while True:
        low = np.minimum(label[a], label[b])
        new = label.copy()
        np.minimum.at(new, a, low)
        np.minimum.at(new, b, low)
        new = new[new][new]
        if (new == label).all():
            return label
        label = new


def remnants(pos: np.ndarray, idx: np.ndarray, found: dict) -> np.ndarray:
    """Vertices of shaft pieces the straight-line cut missed: a bent shaft
    leaves loose slivers that run along the pole once the rest is gone."""
    mask = found["mask"]
    axis = np.subtract(found["end"], found["start"])
    axis /= np.linalg.norm(axis)
    _, weld = np.unique(np.round(pos, 5), axis=0, return_inverse=True)
    weld = weld.ravel()
    left = weld[idx[~mask[idx].any(axis=1)]]
    label = components(int(weld.max()) + 1, left)
    tri_label = label[left[:, 0]]
    ids, counts = np.unique(tri_label, return_counts=True)
    extra = np.zeros(int(weld.max()) + 1, dtype=bool)
    for comp, count in zip(ids, counts):
        if count > 0.05 * len(left):
            continue
        pts = pos[np.isin(weld, np.unique(left[tri_label == comp]))]
        spread = np.linalg.svd(pts - pts.mean(axis=0), compute_uv=False) if len(pts) > 2 else np.zeros(3)
        main = np.linalg.svd(pts - pts.mean(axis=0), full_matrices=False)[2][0] if len(pts) > 2 else axis
        if count < 60 or (spread[0] > 4 * spread[1] and abs(main @ axis) > 0.8):
            extra[np.unique(left[tri_label == comp])] = True
    return extra[weld]


def cut(path: Path, mask_of: dict) -> int:
    """Turns the weapon's triangles into zero-area ones (indices kept)."""
    glb = Glb(path)
    removed = 0
    for mesh in glb.json["meshes"]:
        for prim in mesh["primitives"]:
            pos = glb.view(prim["attributes"]["POSITION"]).astype(np.float64)
            key = (len(pos), round(float(pos[:, 1].max()), 5))
            if key not in mask_of:
                found = pole(pos)
                found["mask"] = found["mask"] | remnants(pos, glb.view(prim["indices"]).reshape(-1, 3), found)
                mask_of[key] = found
            mask = mask_of[key]["mask"]
            idx = glb.view(prim["indices"]).reshape(-1, 3)
            hit = mask[idx].any(axis=1)
            idx[hit] = idx[hit][:, :1]
            removed += int(hit.sum())
    glb.save()
    return removed


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("id")
    parser.add_argument("--bone", default="mixamorig:RightHand")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    spec_path = root / "assets/specs/creature_models.json"
    spec = json.loads(spec_path.read_text())
    unit = next(u for u in spec["units"] if u["id"] == args.id)
    if "weapon" in unit:
        raise SystemExit(f"{args.id}: weapon already cut; restore the downloaded GLBs and remove unit['weapon'] to redo")
    files = sorted({c["model"] for c in unit.get("clips", {}).values() if c.get("model")})
    masks: dict = {}
    for f in files:
        print(f, "triangles removed:", cut(root / f, masks))
    info = next(iter(masks.values()))
    unit["weapon"] = {"kind": "pole", "bone": args.bone, **{k: v for k, v in info.items() if k != "mask"}}
    spec_path.write_text(json.dumps(spec, indent=2) + "\n")
    print(json.dumps(unit["weapon"]))


if __name__ == "__main__":
    main()
