"""Production inventory and contact sheets, derived from the existing pipeline."""
from __future__ import annotations

from collections import Counter
from collections import deque
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw
import numpy as np

from . import build, creatures_auto, specs


def sha256(path: Path) -> str | None:
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None


def import_sheet(root: Path, batch: Path, force: bool = False) -> None:
    """Extract annotated bounds without grid clipping or neighboring islands.

    The unmodified sheet is the archival source. Each crop keeps its largest
    connected opaque silhouette, so disconnected fragments cannot alter fit.
    Explicit annotations are reviewed, not inferred from generation success.
    """
    layout = json.loads((batch / "layout.json").read_text())
    image = Image.open(batch / "source.png").convert("RGBA")
    out = root / "assets/source/generated"
    out.mkdir(parents=True, exist_ok=True)
    destinations = [out / (asset["id"] + ".png") for asset in layout["assets"]]
    if not force and any(p.exists() for p in destinations):
        raise FileExistsError("Batch would overwrite generated art; use --force only for your own unapproved batch")
    for asset, dest in zip(layout["assets"], destinations):
        cropped = image.crop(tuple(asset["crop_xyxy"]))
        if asset.get("keep_components"):
            alpha_floor = int(asset.get("alpha_floor", 0))
            if alpha_floor:
                pixels = np.array(cropped)
                pixels[pixels[:, :, 3] < alpha_floor] = 0
                cropped = Image.fromarray(pixels)
            cropped.save(dest)
            _import_metadata(root, batch, asset, dest,
                             f"all components retained; alpha below {alpha_floor} cleared")
            continue
        a = np.array(cropped)
        available = a[:, :, 3] >= 128
        height, width = available.shape
        largest = []
        for y, x in zip(*np.nonzero(available)):
            if not available[y, x]:
                continue
            available[y, x] = False
            q = deque([(y, x)])
            component = []
            while q:
                cy, cx = q.popleft()
                component.append((cy, cx))
                for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                    ny, nx = cy + dy, cx + dx
                    if 0 <= ny < height and 0 <= nx < width and available[ny, nx]:
                        available[ny, nx] = False
                        q.append((ny, nx))
            if len(component) > len(largest):
                largest = component
        if not largest:
            raise ValueError(f"{asset['id']}: crop has no opaque silhouette")
        mask = np.zeros((height, width), dtype=bool)
        ys, xs = zip(*largest)
        mask[ys, xs] = True
        a[~mask] = 0
        Image.fromarray(a).save(dest)
        _import_metadata(root, batch, asset, dest, "largest 4-connected alpha>=128 component")


def _import_metadata(root: Path, batch: Path, asset: dict, destination: Path, isolation: str) -> None:
    """Every import, including disconnected piles, retains its provenance."""
    path = destination.with_suffix(".json")
    metadata = json.loads(path.read_text()) if path.is_file() else {}
    metadata.update({"batch": batch.name, "source_sheet": str((batch / 'source.png').relative_to(root)),
                     "source_sheet_sha256": sha256(batch / "source.png"),
                     "crop_xyxy": asset["crop_xyxy"], "isolation": isolation,
                     "source_sha256": sha256(destination)})
    path.write_text(json.dumps(metadata, indent=2) + "\n")


def inventory(root: Path) -> dict:
    paths = build.Paths(root)
    explicit = specs.load_sprite_specs(paths.specs)
    all_specs = explicit + build.auto_creature_specs(explicit, paths)
    creatures = creatures_auto.load_creatures(paths.data)
    from .dlc import creature_definitions
    creatures.update(creature_definitions(root))
    man = json.loads(paths.manifest.read_text())
    reviews_path = root / "assets/source/reviews.json"
    reviews = json.loads(reviews_path.read_text()) if reviews_path.is_file() else {}
    records = []
    for s in sorted(all_specs, key=lambda x: x["id"]):
        sid = s["id"]
        c = creatures.get(s.get("data", {}).get("id"), {}) if s["category"] == "creature" else {}
        raw = paths.generated / f"{sid}.png"
        metadata = raw.with_suffix(".json")
        provenance = json.loads(metadata.read_text()) if metadata.is_file() else None
        label = man["sprites"].get(sid, {}).get("source", "missing")
        review = reviews.get(sid, {})
        records.append({"id": sid, "category": s["category"], "faction": c.get("faction", s.get("faction")),
                        "tier": c.get("tier"), "upgrade_of": c.get("upgrade_of"),
                        "size": s["size"], "source_kind": label,
                        "generation_status": "generated" if raw.is_file() else "not_generated",
                        "quality_status": review.get("status", "pending_visual_review" if raw.is_file() else "needs_regeneration"),
                        "review": review, "source": str(raw.relative_to(root)) if raw.is_file() else s.get("source"),
                        "source_sha256": sha256(raw), "provenance": provenance})
    # Terrain and decorations are generated by the same build outside sprite specs.
    terrain = json.loads((paths.specs / "terrain.json").read_text())
    records += [{"id": f"terrain_{tid}", "category": "terrain", "faction": None,
                 "generation_status": "generated" if (paths.generated / f"terrain_{tid}.png").is_file() else "hand_drawn",
                 "quality_status": "pending_visual_review" if (paths.generated / f"terrain_{tid}.png").is_file() else "needs_regeneration",
                 "source": f"assets/source/generated/terrain_{tid}.png" if (paths.generated / f"terrain_{tid}.png").is_file() else "assets/specs/terrain.json", "spec": spec}
                for tid, spec in sorted(terrain["terrains"].items())]
    for raw in sorted(paths.generated.glob("deco_*.png")):
        records.append({"id": raw.stem, "category": "decoration", "faction": None,
                        "generation_status": "generated", "quality_status": "pending_visual_review",
                        "source": str(raw.relative_to(root)), "source_sha256": sha256(raw),
                        "provenance": json.loads(raw.with_suffix(".json").read_text())})
    for raw in sorted(paths.generated.glob("terrain_*_[0-9].png")):
        records.append({"id": raw.stem, "category": "terrain_variant", "faction": None,
                        "generation_status": "generated", "quality_status": "pending_visual_review",
                        "source": str(raw.relative_to(root)), "source_sha256": sha256(raw),
                        "provenance": json.loads(raw.with_suffix(".json").read_text())})
    illustration_spec = paths.specs / "campaign_illustrations.json"
    if illustration_spec.is_file():
        campaign_defs = json.loads((root / "data/campaigns.json").read_text())["campaigns"]
        for asset in json.loads(illustration_spec.read_text())["assets"]:
            raw = root / asset["source"]
            metadata = json.loads(raw.with_suffix(".json").read_text()) if raw.with_suffix(".json").is_file() else {}
            record = {"id": asset["id"], "category": "campaign_illustration", "faction": campaign_defs[asset["campaign"]]["faction"],
                      "campaign": asset["campaign"], "chapter": asset["chapter"], "usage": asset["usage"],
                      "generation_status": "generated" if raw.is_file() else "pending_generation",
                      "quality_status": metadata.get("quality_status", "pending_visual_review"), "source": asset["source"],
                      "output": asset["output"], "story_source": asset["story_source"], "source_sha256": sha256(raw)}
            if asset["usage"] == "journey":
                record["provenance"] = metadata
                record["review"] = "docs/art/production/campaign-journeys/README.md"
            records.append(record)
    menu_spec = paths.specs / "menu_art.json"
    if menu_spec.is_file():
        for asset in json.loads(menu_spec.read_text())["assets"]:
            raw = root / asset["source"]
            records.append({"id": "menu_" + asset["id"],
                            "category": "logo" if asset["crop_alpha"] else "menu_background",
                            "faction": None, "size": asset["size"],
                            "generation_status": "generated" if raw.is_file() else "pending_generation",
                            "quality_status": "pending_godot_render",
                            "source": asset["source"], "output": asset["output"],
                            "source_sha256": sha256(raw),
                            "provenance": json.loads(raw.with_suffix(".json").read_text()) if raw.is_file() else None})
    town_spec = paths.specs / "town_scenes.json"
    if town_spec.is_file():
        from .town_scenes import _asset_source
        for faction, scene in json.loads(town_spec.read_text())["factions"].items():
            for bid, asset in [("background", scene["background"]), *scene["assets"].items()]:
                resolved = _asset_source(scene,bid) if bid != "background" else bid
                if resolved != bid:
                    asset = scene["assets"][resolved]
                raw = root / asset["source"]
                records.append({"id": f"town_scene_{faction}_{bid}", "category": "town_scene",
                                "faction": faction, "building_id": None if bid == "background" else bid,
                                "generation_status": "reused_source" if resolved != bid else "generated", "quality_status": "rendered_candidate",
                                "source": asset["source"], "source_sha256": sha256(raw),
                                "output": f"assets/towns/{faction}/{resolved}.png", "reuses": resolved if resolved != bid else None,
                                "review": "docs/art/production/living-world/"})
    for tid, field in terrain.get("connected_fields", {}).get("terrains", {}).items():
        records.append({"id": "connected_field_" + tid, "category": "connected_terrain",
                        "faction": None, "generation_status": "generated" if tid == "grass" else "reused_source",
                        "quality_status": "rendered_candidate", "source": field["source"],
                        "source_sha256": sha256(root / field["source"]), "cells": [8, 8]})
    animation_spec = paths.specs / "creature_animations.json"
    animation_manifest = root / "assets/animations.json"
    if animation_spec.is_file() and animation_manifest.is_file():
        planned = json.loads(animation_spec.read_text())
        animations = json.loads(animation_manifest.read_text())
        for group in planned["groups"] + planned.get("hero_groups", []):
            hero = group.get("category") == "hero"
            for unit in group["units"]:
                sid = ("hero_" if hero else "creature_") + unit["id"]
                ready = animations["units"].get(sid, {})
                for action in (["move"] if hero else ["move", "attack"]):
                    clip = ready.get("actions", {}).get(action, {})
                    records.append({"id": "animation_" + sid + "_" + action,
                                    "category": "hero_animation" if hero else "creature_animation",
                                    "faction": group.get("faction", "concord"), "unit_id": unit["id"],
                                    "action": action, "generation_status": "generated" if clip else "pending_generation",
                                    "quality_status": "animation_candidate" if clip else "pending_generation",
                                    "source": group["source"], "source_sha256": group.get("source_sha256"),
                                    "prompt_file": group["prompt_file"], "reference": unit["reference_source"],
                                    "reference_sha256": unit["reference_sha256"],
                                    "frame_count": len(clip.get("frames", [])),
                                    "duration_ms": sum(clip.get("durations_ms", [])),
                                    "loop": clip.get("loop", False), "events": clip.get("events", []),
                                    "review": "docs/art/production/animations/"})
    battlefield_spec = paths.specs / "battlefields.json"
    if battlefield_spec.is_file():
        for asset in json.loads(battlefield_spec.read_text())["assets"]:
            records.append({"id": "battlefield_" + asset["id"], "category": "battlefield_background",
                            "terrain": asset["terrain"], "faction": None,
                            "generation_status": "generated", "quality_status": "rendered_candidate",
                            "source": asset["source"], "source_sha256": asset["source_sha256"],
                            "output": asset["output"], "size": asset["size"],
                            "prompt_file": asset["prompt_file"], "reference": asset["reference"],
                            "review": "docs/art/production/battlefields/"})
    ultimate_spec = paths.specs / "ultimate_buildings.json"
    if ultimate_spec.is_file():
        for asset in json.loads(ultimate_spec.read_text())["assets"]:
            records.append({"id":"ultimate_source_"+asset["faction"],"category":"ultimate_building_source",
                            "faction":asset["faction"],"building_id":asset["building_id"],
                            "generation_status":"generated","quality_status":asset["quality_status"],
                            "source":asset["source"],"source_sha256":asset["source_sha256"],
                            "prepared_input":asset.get("prepared_input"),"prepared_input_sha256":asset.get("prepared_input_sha256"),
                            "output":"assets/towns/"+asset["faction"]+"/"+asset["building_id"]+".png",
                            "size":asset["size"],"prompt_file":asset.get("prompt_file"),
                            "review":"docs/art/production/ultimate-buildings/README.md"})
    return {"schema_version": 1, "baseline_commit": "6b775836bece412cd99a41af577a032cf2cd4317",
            "visual_standard": "User benchmark v0.2 and approved Concord preview, 2026-11-07",
            "target_creature_size": [128, 128],
            "quality_counts": dict(sorted(Counter(r["quality_status"] for r in records).items())),
            "assets": records,
            "scope_gaps": ["Human artistic approval remains pending for assets marked as candidates.",
                           "Dedicated hit/death/projectile artwork is not part of the current movement/attack clip set."]}


def contact_sheet(root: Path, faction: str, destination: Path) -> None:
    creatures = creatures_auto.load_creatures(root / "data")
    rows = sorted(((cid, c) for cid, c in creatures.items()
                   if c.get("faction") == faction and not c.get("upgrade_of")),
                  key=lambda item: (item[1].get("tier", 0), item[0]))
    # Native 128px review plus gameplay-size 64px rendering for every pair.
    sheet = Image.new("RGB", (660, 42 + len(rows) * 174), "#201e20")
    draw = ImageDraw.Draw(sheet)
    draw.text((12, 12), f"Reignem / {faction} / native 128px + gameplay 64px / base -> upgrade", fill="#e6ded2")
    for row, (cid, c) in enumerate(rows):
        y = 40 + row * 174
        for col, uid in enumerate([cid, c.get("upgrade")]):
            if not uid:
                continue
            path = root / "assets/build/creature" / f"creature_{uid}.png"
            if not path.is_file():
                continue
            image = Image.open(path).convert("RGBA")
            x = 12 + col * 326
            # Alternating review background exposes dark and light fringe pixels.
            for by in range(0, 128, 16):
                for bx in range(0, 128, 16):
                    draw.rectangle((x+bx, y+by, x+bx+15, y+by+15), fill="#343239" if (bx+by)//16 % 2 else "#49464b")
            native = image.copy()
            native.thumbnail((128, 128), Image.Resampling.NEAREST)
            sheet.paste(native, (x, y + 128 - native.height), native)
            small = image.resize((64, 64), Image.Resampling.NEAREST)
            sheet.paste(small, (x + 146, y + 64), small)
            draw.text((x, y + 134), f"T{c['tier']} {creatures[uid]['name']}", fill="#e6ded2")
    destination.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(destination)


def batch_contact(root: Path, name: str) -> Path:
    """Native-size review of sprites actually built for a planned batch."""
    from . import postprocess
    from .palette import Palette
    plan = json.loads((root / "assets/source/batches" / name / "plan.json").read_text())
    palette = Palette.load(root / "assets/specs/palette.json")
    columns = min(4, plan["grid"][0])
    rows = (len(plan["assets"]) + columns - 1) // columns
    cell_width = max(a["size"][0] for a in plan["assets"]) + 28
    cell_height = max(a["size"][1] for a in plan["assets"]) + 40
    sheet = Image.new("RGB", (columns * cell_width, rows * cell_height + 30), "#252327")
    draw = ImageDraw.Draw(sheet)
    draw.text((8, 8), name + " / native-size import candidates", fill="#e6ded2")
    for index, asset in enumerate(plan["assets"]):
        built = root / "assets/build" / plan["category"] / (asset["id"] + ".png")
        if built.is_file():
            image = Image.open(built).convert("RGBA")
        else:
            raw = Image.open(root / "assets/source/generated" / (asset["id"] + ".png"))
            image = raw.convert("RGBA").resize(tuple(asset["size"]), Image.Resampling.BOX) if plan["category"] == "ground" else postprocess.process_generated(
                raw, {"size": asset["size"], "outline": True, "outline_weight": 1,
                      "anchor": "bottom_center", "generated_palette": "preserve"}, palette)
        x, y = (index % columns) * cell_width + 8, (index // columns) * cell_height + 30
        sheet.paste(image, (x, y), image)
        draw.text((x, y + cell_height - 26), asset["id"], fill="#e6ded2")
    dest = root / "docs/art/production" / (name + "-contact.png")
    sheet.save(dest)
    return dest
