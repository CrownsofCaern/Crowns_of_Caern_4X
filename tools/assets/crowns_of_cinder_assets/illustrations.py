"""Full-resolution campaign artwork export alongside the existing sprite build."""
from __future__ import annotations

import hashlib
import json
import shutil
from pathlib import Path

from PIL import Image, ImageDraw


def stage(root: Path, asset_id: str, source: Path, replace_unapproved: bool = False,
          prompt_path: Path | None = None) -> None:
    specs = json.loads((root / "assets/specs/campaign_illustrations.json").read_text())["assets"]
    asset = next(a for a in specs if a["id"] == asset_id)
    destination = root / asset["source"]
    previous = None
    if destination.exists():
        if not replace_unapproved:
            raise FileExistsError("Refuse to replace existing illustration source: " + asset_id)
        metadata = json.loads(destination.with_suffix(".json").read_text())
        reviews_path = root / "assets/source/reviews.json"
        reviews = json.loads(reviews_path.read_text()) if reviews_path.is_file() else {}
        if "approved" in metadata.get("quality_status", "") or "approved" in reviews.get(asset_id, {}).get("status", ""):
            raise ValueError("Refuse to replace user-approved illustration: " + asset_id)
        archive = root / "assets/source/batches/last-light-story-001/revisions"
        archive.mkdir(parents=True, exist_ok=True)
        version = 1
        while (archive / f"{asset_id}-v{version}.png").exists():
            version += 1
        previous = archive / f"{asset_id}-v{version}.png"
        shutil.copyfile(destination, previous)
        shutil.copyfile(destination.with_suffix(".json"), previous.with_suffix(".json"))
    with Image.open(source) as raw:
        size = list(raw.size)
    if min(size) < 768:
        raise ValueError("Illustration source is below the required full-resolution size")
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, destination)
    prompt = prompt_path or root / "assets/source/batches/last-light-story-001" / (asset_id + ".txt")
    destination.with_suffix(".json").write_text(json.dumps({
        "schema_version": 1, "provider": "ChatGPT image_gen", "id": asset_id,
        "campaign": asset["campaign"], "chapter": asset["chapter"], "usage": asset["usage"],
        "story_source": asset["story_source"], "story_snapshot": str((prompt.parent.parent / "story-snapshot.json").relative_to(root)) if (prompt.parent.parent / "story-snapshot.json").is_file() else "assets/source/batches/last-light-story-001/story-snapshot.json",
        "prompt_file": str(prompt.relative_to(root)), "prompt_sha256": hashlib.sha256(prompt.read_bytes()).hexdigest(),
        "conditioning": [str(previous.relative_to(root))] if previous else asset.get("conditioning", ["assets/source/batches/heroes-001/source.png", "assets/source/batches/towns-001/source.png"]),
        "previous_source": str(previous.relative_to(root)) if previous else None,
        "source_sha256": hashlib.sha256(destination.read_bytes()).hexdigest(), "source_size": size,
        "quality_status": "pending_visual_review", "processing": "Preserve full source resolution; no quantization or atlas downsampling"
    }, indent=2) + "\n")
    print(f"Staged {asset_id}: {size[0]}x{size[1]}")


def build(root: Path, out_root: Path | None = None) -> dict:
    out = out_root or root
    spec_path = root / "assets/specs/campaign_illustrations.json"
    assets = json.loads(spec_path.read_text())["assets"] if spec_path.is_file() else []
    records = []
    for asset in assets:
        source = root / asset["source"]
        record = {k: asset[k] for k in ("id", "campaign", "chapter", "chapter_number", "chapter_name", "usage", "story_source")}
        record["generated"] = source.is_file()
        if source.is_file():
            with Image.open(source) as raw:
                image = raw.convert("RGB")
            if min(image.size) < 768:
                raise ValueError(f"{asset['id']}: campaign source must remain high resolution")
            destination = out / asset["output"]
            destination.parent.mkdir(parents=True, exist_ok=True)
            image.save(destination, optimize=True)
            record.update(path="res://" + asset["output"], size=list(image.size),
                          source=asset["source"], source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                          quality_status="pending_visual_review")
        records.append(record)
    manifest = {"schema_version": 1, "_doc": "Generated from assets/specs/campaign_illustrations.json; full-resolution images are not sprite-atlased or palette-quantized.",
                "illustrations": records}
    destination = out / "assets/campaign_art.json"
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest


def contact_sheet(root: Path, usage: str = "briefing") -> Path:
    manifest = json.loads((root / "assets/campaign_art.json").read_text())
    records = [r for r in manifest["illustrations"] if r["usage"] == usage]
    columns, cw, ch = 2, 500, 365
    sheet = Image.new("RGB", (columns * cw, ((len(records) + 1) // 2) * ch), "#252327")
    draw = ImageDraw.Draw(sheet)
    for i, record in enumerate(records):
        x, y = (i % columns) * cw, (i // columns) * ch
        if record.get("generated"):
            image = Image.open(root / record["path"].removeprefix("res://")).convert("RGB")
            image.thumbnail((cw - 16, ch - 40), Image.Resampling.LANCZOS)
            sheet.paste(image, (x + 8, y + 8))
        draw.text((x + 8, y + ch - 25), f"{record['chapter_number']:02d} {record['chapter_name']}", fill="#e6ded2")
    dest = root / ("docs/art/production/campaign-journeys/contact.jpg" if usage == "journey" else "docs/art/production/last-light-illustrations-contact.jpg")
    dest.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(dest, quality=94)
    return dest


def validate(root: Path, out_root: Path | None = None) -> list[str]:
    spec = root / "assets/specs/campaign_illustrations.json"
    if not spec.is_file():
        return []
    out = out_root or root
    path = out / "assets/campaign_art.json"
    if not path.is_file():
        return ["assets/campaign_art.json missing: rebuild campaign art"]
    errors = []
    assets = json.loads(spec.read_text())["assets"]
    records = json.loads(path.read_text())["illustrations"]
    by_id = {a["id"]: a for a in records}
    if len(by_id) != len(records) or set(by_id) != {a["id"] for a in assets}:
        errors.append("campaign art: illustration IDs differ from structured specification")
    for asset in assets:
        source = root / asset["source"]
        record = by_id.get(asset["id"], {})
        if bool(record.get("generated")) != source.is_file():
            errors.append(f"{asset['id']}: stale generation status")
        if not source.is_file():
            continue
        exported = out / asset["output"]
        if not exported.is_file():
            errors.append(f"{asset['id']}: full-resolution export missing")
            continue
        with Image.open(source) as raw, Image.open(exported) as image:
            if raw.size != image.size or list(image.size) != record.get("size"):
                errors.append(f"{asset['id']}: export must preserve source dimensions")
            if min(raw.size) < 768:
                errors.append(f"{asset['id']}: source resolution too low")
    journey_path = root / "assets/specs/campaign_journeys.json"
    if journey_path.is_file():
        journeys = json.loads(journey_path.read_text())["campaigns"]
        campaigns = json.loads((root / "data/campaigns.json").read_text())["campaigns"]
        # The short scenario campaign deliberately uses the screen's fallback
        # stops; the ten-chapter story campaigns require painted journeys.
        required = {cid for cid, campaign in campaigns.items() if len(campaign.get("chapters", [])) == 10}
        if set(journeys) != required:
            errors.append("journeys: missing or unexpected campaign")
        for cid, journey in journeys.items():
            expected = [c["id"] for c in campaigns.get(cid, {}).get("chapters", [])]
            nodes = journey.get("nodes", [])
            if [n["chapter"] for n in nodes] != expected:
                errors.append(f"{cid}: journey stops must match actual chapter order")
            for node in nodes:
                if len(node["at"]) != 2 or any(not 0.04 <= v <= .96 for v in node["at"]):
                    errors.append(f"{cid}: journey stop outside safe painting area")
            if not any(a["campaign"] == cid and a["usage"] == "journey" for a in assets):
                errors.append(f"{cid}: journey painting absent from illustration pipeline")
    return errors
