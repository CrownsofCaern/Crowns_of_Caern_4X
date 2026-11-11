"""Fix a welded weapon, shield or lantern rigidly to one bone.

  python3 tools/assets/rigid_weapon.py show ID [--out board.png]
  python3 tools/assets/rigid_weapon.py apply ID

Image-to-3D models come as one welded mesh, so the auto-rigger spreads a
sword over the hand, the forearm, the spine and even the legs, and every
animation bends it. This keeps the weapon's own geometry but re-skins it
100% to one bone (the hand for a sword or staff, the forearm for a shield),
so it moves as one rigid piece in every clip.

The regions come from unit["rigid"] in assets/specs/creature_models.json,
in the model's bind space (the rigged GLB's mesh coordinates, metres):

  "rigid": [
    {"bone": "mixamorig:RightHand", "auto": true},
    {"bone": "mixamorig:RightHand", "capsule": [[x, y, z], [x, y, z], radius]},
    {"bone": "mixamorig:LeftForeArm", "box": [[x0, y0, z0], [x1, y1, z1]]},
    {"bone": "mixamorig:LeftForeArm", "slab": [[[x, z], [x, z], ...], half_thickness, [y0, y1]]},
    {"drop": true, "box": [[...], [...]]}
  ]

- "auto" finds the longest thin straight piece running out of the bone
  (blade, staff, banner pole) and fixes it plus the grip around the bone.
  The first run records what it found as a "capsule" (plus a wider "guard"
  capsule round the grip) in the spec, so later runs and edits use those.
- "capsule", "box" and "slab" (an upright shield, a line seen from above)
  select vertices by hand; "show" draws the model from
  three sides on a coordinate grid, coloured by bone, to read them off.
- "drop" removes stray geometry (zero-area triangles) instead.

Re-skinning is idempotent, so "apply" can be re-run after editing regions;
every GLB the unit uses (model and clips) is rewritten in place.
"""
from __future__ import annotations

import argparse
import colorsys
import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from split_weapon import Glb  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SPEC = ROOT / "assets/specs/creature_models.json"


def skin_info(glb: Glb) -> tuple[list[str], np.ndarray]:
    """Joint names and bind-pose joint positions of the first skin."""
    skin = glb.json["skins"][0]
    names = [glb.json["nodes"][n].get("name", f"bone_{n}") for n in skin["joints"]]
    ibm = glb.view(skin["inverseBindMatrices"]).astype(np.float64).reshape(-1, 4, 4).transpose(0, 2, 1)
    heads = np.array([np.linalg.inv(m)[:3, 3] for m in ibm])
    return names, heads


def joint_index(names: list[str], bone: str) -> int:
    want = bone.replace(":", "_")
    for i, n in enumerate(names):
        if n == bone or n.replace(":", "_") == want:
            return i
    raise SystemExit(f"bone {bone!r} not in skin: {', '.join(names)}")


def in_capsule(pos: np.ndarray, a, b, radius: float) -> np.ndarray:
    a, b = np.asarray(a, float), np.asarray(b, float)
    ab = b - a
    t = np.clip((pos - a) @ ab / max(ab @ ab, 1e-12), 0, 1)
    return np.linalg.norm(pos - (a + np.outer(t, ab)), axis=1) <= radius


def in_box(pos: np.ndarray, lo, hi) -> np.ndarray:
    lo, hi = np.minimum(lo, hi), np.maximum(lo, hi)
    return ((pos >= lo) & (pos <= hi)).all(axis=1)


def sphere_dirs(n: int) -> np.ndarray:
    i = np.arange(n) + 0.5
    phi = np.arccos(1 - 2 * i / n)
    theta = np.pi * (1 + 5 ** 0.5) * i
    return np.stack([np.cos(theta) * np.sin(phi), np.cos(phi), np.sin(theta) * np.sin(phi)], axis=1)


def longest_run(good: np.ndarray, latest_start: int) -> int:
    """Length in bins of the longest run of good bins (gaps of up to two
    bins bridged) that starts no later than latest_start: the grip and the
    fist crowd the first bins, the blade runs on from there."""
    best, i, n = 0, 0, len(good)
    while i <= min(latest_start, n - 1):
        if not good[i]:
            i += 1
            continue
        j, gap, end = i, 0, i
        while j < n and gap <= 2:
            if good[j]:
                end, gap = j, 0
            else:
                gap += 1
            j += 1
        best = max(best, end - i + 1)
        i = end + 1
    return best


def auto_capsule(pos: np.ndarray, head: np.ndarray, back: np.ndarray | None) -> tuple:
    """The longest thin, straight, filled run of geometry through `head`.

    Scores every direction by how far a thin core cylinder stays filled
    (short gaps bridged) while a wide ring around it stays mostly empty,
    which a blade or staff does and an arm, leg or torso does not. A staff
    runs both ways out of the fist, so both ends count."""
    height = float(np.ptp(pos[:, 1]))
    rng = np.random.default_rng(0)
    sample = pos[rng.choice(len(pos), min(len(pos), 20000), replace=False)]
    rel = sample - head
    core, shell, outer = 0.012 * height, 0.06 * height, 0.12 * height
    step = 0.015 * height
    start = 0.06 * height
    nbins = int(2.0 * height / step)
    latest = int(0.25 * height / step)
    best = (0.0, None, 0.0, 0.0)
    dirs = sphere_dirs(3000)

    def run_along(t: np.ndarray, perp: np.ndarray) -> float:
        b = ((t - start) / step).astype(int)
        v = (b >= 0) & (b < nbins)
        bk, pk = b[v], perp[v]
        core_n = np.bincount(bk[pk <= core], minlength=nbins)
        inner_n = np.bincount(bk[pk <= shell], minlength=nbins)
        outer_n = np.bincount(bk[(pk > shell) & (pk <= outer)], minlength=nbins)
        return longest_run((core_n >= 1) & (outer_n <= inner_n * 0.25), latest) * step

    for chunk in np.array_split(dirs, 30):
        t = rel @ chunk.T  # (n, d)
        perp = np.sqrt(np.maximum((rel ** 2).sum(1)[:, None] - t ** 2, 0))
        for k in range(len(chunk)):
            d = chunk[k]
            fwd = run_along(t[:, k], perp[:, k]) if back is None or d @ back < 0.3 else 0.0
            bwd = run_along(-t[:, k], perp[:, k]) if back is None or -d @ back < 0.3 else 0.0
            if fwd < bwd:
                continue  # the same line is scored from the other side
            if fwd + bwd > best[0]:
                best = (fwd + bwd, d, fwd, bwd)
    total, axis, fwd, bwd = best
    if axis is None or total < 0.12 * height:
        raise SystemExit("auto: no long straight weapon found at this bone; give a capsule or box instead")
    end = head + axis * (start + fwd)
    a = head - axis * ((start + bwd) if bwd > 0 else 0.05 * height)
    # Refit the axis on the found core, then size the radius from it.
    rel_all = pos - head
    t = rel_all @ axis
    perp = np.linalg.norm(rel_all - np.outer(t, axis), axis=1)
    lo, hi = float((a - head) @ axis), float((end - head) @ axis)
    sel = (t > lo) & (t < hi) & (np.abs(t) > start) & (perp <= core * 1.5)
    radius = core * 2
    if sel.sum() > 10:
        pts = pos[sel]
        c = pts.mean(axis=0)
        fit = np.linalg.svd(pts - c, full_matrices=False)[2][0]
        axis = fit if fit @ axis > 0 else -fit
        rel_all = pos - c
        t = rel_all @ axis
        perp = np.linalg.norm(rel_all - np.outer(t, axis), axis=1)
        lo, hi = float((a - c) @ axis), float((end - c) @ axis)
        h = float((head - c) @ axis)
        band = (t > lo) & (t < hi) & (np.abs(t - h) > start)
        radius = float(np.percentile(perp[band & (perp <= shell)], 92)) * 1.25
        a, end = c + axis * lo, c + axis * (hi + 0.02 * height)
    radius = min(radius, shell)
    # Run on to the tips: blades taper below the core, so follow any
    # geometry inside the radius until a gap (both ends for a staff).
    rel_all = pos - a
    t = rel_all @ axis
    perp = np.linalg.norm(rel_all - np.outer(t, axis), axis=1)
    inside = t[perp <= radius * 1.5]
    fine = 0.005 * height
    reach = float((end - a) @ axis)
    while ((inside > reach) & (inside <= reach + 4 * fine)).any():
        reach += fine
    # Backwards (a staff's lower half) only while the ring around the line
    # stays clear, so the grip end never runs on into the arm or body.
    ring = (perp > shell) & (perp <= outer)
    low = 0.0
    while ((inside < low) & (inside >= low - 4 * fine)).any():
        near = (t < low) & (t >= low - 4 * fine)
        if (ring & near).sum() > 0.25 * max(1, (near & (perp <= shell)).sum()):
            break
        low -= fine
    end, a = a + axis * reach, a + axis * low
    blade = (a.round(4).tolist(), end.round(4).tolist(), round(radius, 4))
    # The guard and pommel are wider than the blade: a fatter, short capsule
    # around the grip.
    guard = ((head - axis * 0.06 * height).round(4).tolist(), (head + axis * 0.12 * height).round(4).tolist(),
             round(radius * 2.2, 4))
    return blade, guard


def grow(mask: np.ndarray, limit: np.ndarray, pos: np.ndarray, idx: np.ndarray, rings: int = 4) -> np.ndarray:
    """Spread a selection over connected triangles, but only inside limit:
    blade edges that bulge a little past the capsule join the blade."""
    _, weld = np.unique(np.round(pos, 5), axis=0, return_inverse=True)
    weld = weld.ravel()
    tri = weld[idx]
    for _ in range(rings):
        on = np.zeros(int(weld.max()) + 1, bool)
        on[weld[mask]] = True
        touched = np.zeros_like(on)
        touched[tri[on[tri].any(axis=1)].ravel()] = True
        new = mask | (touched[weld] & limit)
        if (new == mask).all():
            break
        mask = new
    return mask


def select(pos: np.ndarray, region: dict, heads: np.ndarray, names: list[str], idx: np.ndarray | None = None) -> np.ndarray:
    if "capsule" in region:
        a, b, r = region["capsule"]
        mask = in_capsule(pos, a, b, r)
        if idx is not None and region.get("part") != "guard":
            # Away from the grip only the blade itself is connected, so let
            # it spread wider there (curved or broad blades) than near the fist.
            a_, b_ = np.asarray(a, float), np.asarray(b, float)
            far_a, far_b = a_ + (b_ - a_) * 0.3, b_ + (b_ - a_) * 0.05
            mask |= in_capsule(pos, far_a, far_b, r * 2)  # loose slivers too
            limit = in_capsule(pos, a_, b_, r * 1.5) | in_capsule(pos, far_a, far_b, r * 3)
            mask = grow(mask, limit, pos, idx, rings=8)
        return mask
    if "box" in region:
        return in_box(pos, *region["box"])
    if "slab" in region:
        # An upright slab (a shield seen from above is a thin line, or a
        # curve): [[[x, z], [x, z], ...], half_thickness, [y0, y1]]. A rough
        # line is enough: the selection then spreads over the connected
        # sheet within three times the thickness.
        points, half, (y0, y1) = region["slab"]
        flat = pos[:, [0, 2]]
        dist = np.full(len(pos), np.inf)
        for a, b in zip(points[:-1], points[1:]):
            a, b = np.asarray(a, float), np.asarray(b, float)
            ab = b - a
            t = np.clip((flat - a) @ ab / (ab @ ab), 0, 1)
            dist = np.minimum(dist, np.linalg.norm(flat - (a + np.outer(t, ab)), axis=1))
        height = (pos[:, 1] >= y0) & (pos[:, 1] <= y1)
        mask = (dist <= half) & height
        if idx is not None:
            mask = grow(mask, (dist <= half * 3) & height, pos, idx, rings=24)
        return mask
    raise SystemExit(f"region needs capsule, box, slab or auto: {region}")


def resolve(unit: dict, pos: np.ndarray, names: list[str], heads: np.ndarray) -> list[dict]:
    """Regions with every "auto" turned into a concrete capsule (written back)."""
    out = []
    for region in unit.get("rigid", []):
        if region.get("auto") and "capsule" not in region:
            j = joint_index(names, region["bone"])
            parent = None
            for i, n in enumerate(names):  # forearm direction, to skip it
                if n.replace(":", "_").endswith(names[j].replace(":", "_").replace("Hand", "ForeArm")) and i != j:
                    parent = heads[i]
            back = None if parent is None else (parent - heads[j]) / np.linalg.norm(parent - heads[j])
            blade, guard = auto_capsule(pos, heads[j], back)
            out.append({**region, "capsule": list(blade)})
            out.append({"bone": region["bone"], "capsule": list(guard), "part": "guard"})
            continue
        out.append(region)
    return out


def apply(glb: Glb, regions: list[dict]) -> dict:
    names, heads = skin_info(glb)
    counts = {}
    for mesh in glb.json["meshes"]:
        for prim in mesh["primitives"]:
            attrs = prim["attributes"]
            pos = glb.view(attrs["POSITION"]).astype(np.float64)
            joints, weights = glb.view(attrs["JOINTS_0"]), glb.view(attrs["WEIGHTS_0"])
            idx = glb.view(prim["indices"]).reshape(-1, 3)
            for region in regions:
                mask = select(pos, region, heads, names, idx)
                if region.get("drop"):
                    hit = mask[idx].any(axis=1)
                    idx[hit] = idx[hit][:, :1]
                    counts["drop"] = counts.get("drop", 0) + int(hit.sum())
                    continue
                j = joint_index(names, region["bone"])
                joints[mask] = 0
                joints[mask, 0] = j
                weights[mask] = 0
                weights[mask, 0] = 1
                counts[region["bone"]] = counts.get(region["bone"], 0) + int(mask.sum())
    glb.save()
    return counts


def show(glb: Glb, regions: list[dict], out: Path) -> None:
    from PIL import Image, ImageDraw
    names, heads = skin_info(glb)
    prim = glb.json["meshes"][0]["primitives"][0]
    pos = glb.view(prim["attributes"]["POSITION"]).astype(float)
    jo, w = glb.view(prim["attributes"]["JOINTS_0"]), glb.view(prim["attributes"]["WEIGHTS_0"])
    dom = jo[np.arange(len(jo)), w.argmax(1)]
    marked = np.zeros(len(pos), bool)
    idx = glb.view(prim["indices"]).reshape(-1, 3)
    for region in regions:
        marked |= select(pos, region, heads, names, idx)
    size = 900
    lo, hi = pos.min(0), pos.max(0)
    span = float((hi - lo).max()) * 1.05
    cols = [tuple(int(c * 255) for c in colorsys.hsv_to_rgb((i * 0.618) % 1, 0.8, 0.85)) for i in range(len(names))]
    img = Image.new("RGB", (size * 3, size + 30 + 18 * ((len(names) + 5) // 6)), "white")
    draw = ImageDraw.Draw(img)
    for vi, (title, a, b, depth) in enumerate([("front x/y", 0, 1, 2), ("side z/y", 2, 1, 0), ("top x/z", 0, 2, 1)]):
        ox = vi * size

        def tx(v, ax):
            return (v - (lo[ax] + hi[ax]) / 2) / span * size + size / 2

        for t in np.arange(np.floor(lo.min() * 10) / 10, hi.max() + 0.1, 0.1):
            x, y = ox + tx(t, a), size - tx(t, b)
            if ox <= x < ox + size:
                draw.line([(x, 0), (x, size)], fill=(215, 215, 215))
                draw.text((x + 2, 2), f"{t:.1f}", fill="black")
            if 0 <= y < size:
                draw.line([(ox, y), (ox + size, y)], fill=(215, 215, 215))
                draw.text((ox + 2, y), f"{t:.1f}", fill="black")
        order = np.argsort(pos[:, depth])
        for i in order[:: max(1, len(order) // 60000)]:
            draw.point((ox + tx(pos[i, a], a), size - tx(pos[i, b], b)), fill=(0, 0, 0) if marked[i] else cols[dom[i]])
        for h in heads:
            x, y = ox + tx(h[a], a), size - tx(h[b], b)
            draw.ellipse([x - 3, y - 3, x + 3, y + 3], outline="black")
        draw.text((ox + 10, size - 20), title + "  (black = rigid regions)", fill="black")
    for i, n in enumerate(names):
        draw.text((10 + (i % 6) * 440, size + 10 + (i // 6) * 18), n, fill=cols[i])
    img.save(out)


def unit_files(unit: dict) -> list[Path]:
    files = {unit["model"]} | {c["model"] for c in unit.get("clips", {}).values() if c.get("model")}
    return [ROOT / f for f in sorted(files)]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=["show", "apply"])
    parser.add_argument("id")
    parser.add_argument("--out", type=Path, help="show: board path (default /tmp/rigid_<id>.png)")
    parser.add_argument("--spec", type=Path, default=SPEC,
                        help="spec file (default assets/specs/creature_models.json)")
    args = parser.parse_args()
    spec_path = args.spec if args.spec.is_absolute() else ROOT / args.spec
    spec = json.loads(spec_path.read_text())
    unit = next((u for u in spec["units"] if u["id"] == args.id), None)
    if unit is None:
        raise SystemExit(f"{args.id}: not in {spec_path}")
    rigged = Glb(ROOT / unit["model"])
    names, heads = skin_info(rigged)
    pos = rigged.view(rigged.json["meshes"][0]["primitives"][0]["attributes"]["POSITION"]).astype(np.float64)
    regions = resolve(unit, pos, names, heads)
    if regions != unit.get("rigid", []):
        unit["rigid"] = regions
        spec_path.write_text(json.dumps(spec, indent=2) + "\n")
        print("auto regions recorded:", json.dumps([r for r in regions if r.get("auto")]))
    if args.command == "show":
        out = args.out or Path(f"/tmp/rigid_{args.id}.png")
        show(rigged, regions, out)
        print(out)
        return
    for f in unit_files(unit):
        print(f.relative_to(ROOT), apply(Glb(f), regions))


if __name__ == "__main__":
    main()
