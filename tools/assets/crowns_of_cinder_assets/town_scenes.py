"""Layered town scenes exported by the existing asset build, at source resolution."""
from __future__ import annotations

import hashlib
import json
import shutil
from pathlib import Path


def stage(root: Path, batch: Path) -> None:
    """Reproduce the reviewed crops from archived sheets and explicit bounds."""
    from PIL import Image
    for asset in json.loads((batch / "layout.json").read_text()):
        source = root / asset["source_sheet"]
        if hashlib.sha256(source.read_bytes()).hexdigest() != asset["source_sheet_sha256"]:
            raise ValueError("Town source sheet changed")
        crop = Image.open(source).convert("RGBA").crop(asset["crop_xyxy"])
        crop = crop.crop(asset["alpha_trim_xyxy"])
        destination = root / "assets/source/generated" / ("town_concord_" + asset["id"] + ".png")
        # Refuse to replace reviewed output with a crop from different metadata.
        if destination.is_file() and hashlib.sha256(destination.read_bytes()).hexdigest() != asset["source_sha256"]:
            raise ValueError(f"{asset['id']}: refusing to overwrite a changed source")
        import io
        encoded = io.BytesIO()
        crop.save(encoded, format="PNG")
        if hashlib.sha256(encoded.getvalue()).hexdigest() != asset["source_sha256"]:
            raise ValueError(f"{asset['id']}: crop does not reproduce the reviewed source")
        destination.write_bytes(encoded.getvalue())


def _asset_source(scene: dict, key: str) -> str:
    """Follow `same_as` aliases (an upgraded building reusing its base art) to the real entry."""
    seen = set()
    asset = scene["assets"][key]
    while "same_as" in asset:
        if key in seen:
            raise ValueError(f"{key}: same_as cycle")
        seen.add(key)
        key = asset["same_as"]
        asset = scene["assets"][key]
    return key


def build(root: Path, out_root: Path | None = None) -> dict:
    out = out_root or root
    spec = json.loads((root / "assets/specs/town_scenes.json").read_text())
    buildings = json.loads((root / "data/buildings.json").read_text())["towns"]
    from .dlc import town_definitions
    for faction, town in town_definitions(root).items():
        buildings.setdefault(faction, town)
    manifest = {"schema_version": 1, "factions": {}}
    for faction, scene in spec["factions"].items():
        slot_ids = [bid for slot in scene["slots"] for bid in slot["variants"]]
        ids = set(slot_ids)
        if len(slot_ids) != len(ids) or ids != set(buildings[faction]["buildings"]):
            raise ValueError(f"{faction}: town slots must cover the actual building roster exactly once")
        # Buildings may still lack art (the scene then shows a marker); art never names unknown ids.
        if not set(scene["assets"]) <= ids:
            raise ValueError(f"{faction}: town art for unknown building ids")
        record = {"size": scene["size"], "slots": scene["slots"], "assets": {}}
        files = {"background": scene["background"]}
        for key in scene["assets"]:
            files.setdefault(_asset_source(scene, key), scene["assets"][_asset_source(scene, key)])
        for key, asset in files.items():
            source = root / asset["source"]
            if hashlib.sha256(source.read_bytes()).hexdigest() != asset["sha256"]:
                raise ValueError(f"{faction}/{key}: source hash changed")
            relative = f"assets/towns/{faction}/{key}.png"
            destination = out / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, destination)
            if key == "background":
                record["background"] = "res://" + relative
        for key in scene["assets"]:
            record["assets"][key] = f"res://assets/towns/{faction}/{_asset_source(scene, key)}.png"
        manifest["factions"][faction] = record
    target = out / "assets/towns/manifest.json"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest


def validate(root: Path, out_root: Path | None = None) -> list[str]:
    from PIL import Image
    spec = root / "assets/specs/town_scenes.json"
    if not spec.is_file():
        return []
    out = out_root or root
    errors = []
    for faction, scene in json.loads(spec.read_text())["factions"].items():
        for bid in scene["assets"]:
            if "same_as" in scene["assets"][bid]:
                continue
            path = out / f"assets/towns/{faction}/{bid}.png"
            if not path.is_file():
                errors.append(f"town {faction}/{bid}: missing export")
                continue
            image = Image.open(path).convert("RGBA")
            alpha = image.getchannel("A")
            if alpha.getbbox() is None or alpha.getextrema()[0] != 0:
                errors.append(f"town {faction}/{bid}: empty sprite or missing transparency")
    return errors
