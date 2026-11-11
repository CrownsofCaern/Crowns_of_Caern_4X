#!/usr/bin/env python3
"""Crowns of Caern asset pipeline CLI. Run from anywhere:

  python3 tools/assets/pipeline.py build      # specs -> assets/build, assets/atlases, assets/manifest.json
  python3 tools/assets/pipeline.py validate   # sizes, transparency, palette, naming, coverage of game data
  python3 tools/assets/pipeline.py check      # rebuild in a temp dir and compare with the committed output
  python3 tools/assets/pipeline.py prompts    # write assets/source/prompts.md (full generation prompts)
  python3 tools/assets/pipeline.py generate --provider openai [--only id,id] [--force]

See tools/assets/README.md.
"""
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
sys.path.insert(0, str(HERE))

from crowns_of_cinder_assets import build, generate, production, specs, validate  # noqa: E402


def cmd_build(a) -> int:
    build.build_all(ROOT, use_generated=not a.no_generated)
    errs = validate.validate(ROOT)
    for e in errs:
        print("INVALID:", e)
    if errs:
        return 1
    if not a.no_import and shutil.which("godot"):
        subprocess.run(["godot", "--headless", "--path", str(ROOT), "--import"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        print("godot import done")
    return 0


def cmd_validate(a) -> int:
    errs = validate.validate(ROOT)
    for e in errs:
        print("INVALID:", e)
    ph = validate.placeholders(ROOT)
    if ph:
        print(f"note: {len(ph)} creatures still use placeholder silhouettes: {', '.join(ph[:12])}{' ...' if len(ph) > 12 else ''}")
    print("assets valid" if not errs else f"{len(errs)} problems")
    return 1 if errs else 0


def cmd_check(a) -> int:
    """Committed atlases/manifest must equal a fresh build (sources are the truth)."""
    from PIL import Image, ImageChops
    with tempfile.TemporaryDirectory() as tmp:
        build.build_all(ROOT, Path(tmp), use_generated=not a.no_generated, log=lambda *_: None)
        bad = []
        fresh_root = Path(tmp) / "assets"
        for p in sorted((fresh_root / "atlases").glob("*.png")):
            mine = ROOT / "assets" / "atlases" / p.name
            if not mine.is_file():
                bad.append(f"{mine} missing")
                continue
            if p.name.startswith("animation_") and p.read_bytes() != mine.read_bytes():
                bad.append(f"{mine.relative_to(ROOT)} differs byte-for-byte from a fresh animation build")
            x, y = Image.open(p).convert("RGBA"), Image.open(mine).convert("RGBA")
            if x.size != y.size or ImageChops.difference(x, y).getbbox() is not None:
                bad.append(f"{mine.relative_to(ROOT)} differs from a fresh build")
        if json.loads((fresh_root / "manifest.json").read_text()) != json.loads((ROOT / "assets" / "manifest.json").read_text()):
            bad.append("assets/manifest.json differs from a fresh build")
        campaign = fresh_root / "campaign_art.json"
        if campaign.is_file():
            committed = ROOT / "assets/campaign_art.json"
            if not committed.is_file() or campaign.read_bytes() != committed.read_bytes():
                bad.append("assets/campaign_art.json differs from a fresh build")
            for p in sorted((fresh_root / "illustrations").rglob("*.png")):
                committed = ROOT / "assets" / p.relative_to(fresh_root)
                if not committed.is_file() or p.read_bytes() != committed.read_bytes():
                    bad.append(str(committed.relative_to(ROOT)) + " differs from a fresh build")
        menu = fresh_root / "menus/manifest.json"
        if menu.is_file():
            for p in sorted((fresh_root / "menus").glob("*")):
                committed = ROOT / "assets/menus" / p.name
                if not committed.is_file() or p.read_bytes() != committed.read_bytes():
                    bad.append(str(committed.relative_to(ROOT)) + " differs from a fresh build")
        if (fresh_root / "towns/manifest.json").is_file():
            for p in sorted((fresh_root / "towns").rglob("*")):
                if p.is_file():
                    committed = ROOT / "assets" / p.relative_to(fresh_root)
                    if not committed.is_file() or p.read_bytes() != committed.read_bytes():
                        bad.append(str(committed.relative_to(ROOT)) + " differs from a fresh build")
        if (fresh_root / "artifacts").is_dir():
            for p in sorted((fresh_root / "artifacts").glob("*.png")):
                committed = ROOT / "assets" / p.relative_to(fresh_root)
                if not committed.is_file() or ImageChops.difference(Image.open(p).convert("RGBA"), Image.open(committed).convert("RGBA")).getbbox() is not None:
                    bad.append(str(committed.relative_to(ROOT)) + " differs from a fresh build")
        animation = fresh_root / "animations.json"
        if animation.is_file():
            committed = ROOT / "assets/animations.json"
            if not committed.is_file() or animation.read_bytes() != committed.read_bytes():
                bad.append("assets/animations.json differs from a fresh build")
        if (fresh_root / "battlefields/manifest.json").is_file():
            for p in sorted((fresh_root / "battlefields").glob("*")):
                committed = ROOT / "assets/battlefields" / p.name
                if not committed.is_file() or p.read_bytes() != committed.read_bytes():
                    bad.append(str(committed.relative_to(ROOT)) + " differs from fresh full-resolution battlefield export")
    for b in bad:
        print("STALE:", b)
    print("build output up to date" if not bad else "run: python3 tools/assets/pipeline.py build")
    return 1 if bad else 0


def cmd_prompts(a) -> int:
    style = json.loads((ROOT / "assets/specs/style.json").read_text())
    out = ["# Generation prompts", "", "Generated by `pipeline.py prompts` from assets/specs. Save results as "
           "`assets/source/generated/<id>.png`, then run `pipeline.py build`.", ""]
    for s in specs.load_sprite_specs(ROOT / "assets/specs"):
        if s.get("generate", True):
            out += [f"## {s['id']}", "", generate.build_prompt(s, style), ""]
    dest = ROOT / "assets/source/prompts.md"
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text("\n".join(out))
    print(f"wrote {dest.relative_to(ROOT)}")
    return 0


def cmd_generate(a) -> int:
    style = json.loads((ROOT / "assets/specs/style.json").read_text())
    only = set(a.only.split(",")) if a.only else None
    return generate.run(specs.load_sprite_specs(ROOT / "assets/specs"), style, ROOT / "assets/source/generated",
                        a.provider, only, a.force)


def cmd_inventory(a) -> int:
    dest = ROOT / "assets/inventory.json"
    dest.write_text(json.dumps(production.inventory(ROOT), indent=2) + "\n")
    print(f"wrote {dest.relative_to(ROOT)}")
    return 0


def cmd_contact_sheet(a) -> int:
    dest = ROOT / "docs/art/production" / f"{a.faction}-contact.png"
    production.contact_sheet(ROOT, a.faction, dest)
    print(f"wrote {dest.relative_to(ROOT)}")
    return 0


def cmd_import_sheet(a) -> int:
    production.import_sheet(ROOT, (ROOT / a.batch).resolve(), a.force)
    return 0


def cmd_batch_contact(a) -> int:
    print(production.batch_contact(ROOT, a.batch).relative_to(ROOT))
    return 0


def cmd_illustrations(a) -> int:
    from crowns_of_cinder_assets import illustrations
    manifest = illustrations.build(ROOT)
    print(f"exported {sum(r['generated'] for r in manifest['illustrations'])} campaign illustrations at source resolution")
    print(illustrations.contact_sheet(ROOT).relative_to(ROOT))
    if any(r["usage"] == "journey" for r in manifest["illustrations"]):
        print(illustrations.contact_sheet(ROOT, "journey").relative_to(ROOT))
    return 0


def cmd_stage_illustration(a) -> int:
    from crowns_of_cinder_assets import illustrations
    illustrations.stage(ROOT, a.id, Path(a.source), a.replace_unapproved,
                        (ROOT / a.prompt).resolve() if a.prompt else None)
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("build")
    b.add_argument("--no-import", action="store_true", help="skip `godot --import`")
    b.add_argument("--no-generated", action="store_true", help="ignore assets/source/generated (placeholders only)")
    sub.add_parser("validate")
    c = sub.add_parser("check")
    c.add_argument("--no-generated", action="store_true")
    sub.add_parser("prompts")
    sub.add_parser("inventory")
    sub.add_parser("stage-ultimate", help="reproduce ultimate layers from the artwork registry")
    dlc = sub.add_parser("stage-dlc", help="isolate optional DLC art with existing adaptive gutters")
    dlc.add_argument("--batch", help="one batch ID, or all available sources")
    contact = sub.add_parser("contact-sheet")
    contact.add_argument("--faction", required=True)
    imp = sub.add_parser("import-sheet")
    imp.add_argument("--batch", required=True, help="directory containing source.png and reviewed layout.json")
    imp.add_argument("--force", action="store_true")
    bc = sub.add_parser("batch-contact")
    bc.add_argument("--batch", required=True)
    sub.add_parser("illustrations")
    si = sub.add_parser("stage-illustration")
    si.add_argument("--id", required=True)
    si.add_argument("--source", required=True)
    si.add_argument("--replace-unapproved", action="store_true")
    si.add_argument("--prompt", help="revision prompt path relative to repository")
    g = sub.add_parser("generate")
    g.add_argument("--provider", default="openai", choices=sorted(generate.PROVIDERS))
    g.add_argument("--only", default="")
    g.add_argument("--force", action="store_true")
    a = ap.parse_args()
    if a.cmd == "stage-ultimate":
        from crowns_of_cinder_assets.ultimate_buildings import stage
        stage(ROOT)
        return 0
    if a.cmd == "stage-dlc":
        from crowns_of_cinder_assets.dlc import stage
        stage(ROOT, a.batch)
        return 0
    return {"build": cmd_build, "validate": cmd_validate, "check": cmd_check, "prompts": cmd_prompts,
            "generate": cmd_generate, "inventory": cmd_inventory, "contact-sheet": cmd_contact_sheet,
            "import-sheet": cmd_import_sheet, "batch-contact": cmd_batch_contact,
            "illustrations": cmd_illustrations, "stage-illustration": cmd_stage_illustration}[a.cmd](a)


if __name__ == "__main__":
    sys.exit(main())
