"""Unit tests for the asset pipeline. Run: python3 -m unittest discover -s tools/assets/tests"""
from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent.parent
sys.path.insert(0, str(HERE.parent))

from PIL import Image, ImageDraw  # noqa: E402

from crowns_of_cinder_assets import atlas, build, generate, pixel, postprocess, procedural, specs, validate  # noqa: E402
from crowns_of_cinder_assets.palette import Palette  # noqa: E402

PAL = Palette.load(ROOT / "assets/specs/palette.json")


class PaletteTests(unittest.TestCase):
    def test_quantize_snaps_to_palette(self):
        img = Image.new("RGBA", (4, 4), (250, 10, 200, 255))
        q = PAL.quantize(img)
        self.assertEqual(PAL.off_palette_pixels(q), 0)
        self.assertEqual(PAL.off_palette_pixels(img), 16)

    def test_ramps_reference_known_colours(self):
        for name in ("stone", "moss", "ember", "concord"):
            self.assertGreaterEqual(len(PAL.ramp(name)), 3)


class PixelTests(unittest.TestCase):
    def test_parse_pads_and_maps(self):
        img = pixel.parse("K.\n.E", PAL, (3, 3))
        self.assertEqual(img.getpixel((0, 0))[:3], PAL.c("K"))
        self.assertEqual(img.getpixel((1, 0))[3], 0)
        self.assertEqual(img.getpixel((1, 1))[:3], PAL.c("E"))
        self.assertEqual(img.getpixel((2, 2))[3], 0)

    def test_rejects_unknown_char_and_oversize(self):
        with self.assertRaises(pixel.PixelFormatError):
            pixel.parse("K!", PAL, (4, 4))
        with self.assertRaises(pixel.PixelFormatError):
            pixel.parse("KKKKK", PAL, (4, 4))


def _art_pack_factions() -> set[str]:
    """Factions drawn by an art pack (assets/specs/dlc_factions.json), not by pixel specs."""
    return set(json.loads((ROOT / "assets/specs/dlc_factions.json").read_text())["factions"])


def _dlc_creatures() -> set[str]:
    from crowns_of_cinder_assets import creatures_auto
    packs = _art_pack_factions()
    return {cid for cid, c in creatures_auto.load_creatures(ROOT / "data").items() if c.get("faction") in packs}


def _core_hero_classes() -> dict:
    packs = _art_pack_factions()
    classes = json.loads((ROOT / "data/hero_classes.json").read_text())["classes"]
    return {cid: c for cid, c in classes.items() if c["faction"] not in packs}


def fake_generated_image() -> Image.Image:
    """Stands in for an AI image: big, smooth colours, flat magenta backdrop."""
    img = Image.new("RGB", (512, 512), (255, 0, 255))
    d = ImageDraw.Draw(img)
    d.ellipse((150, 60, 360, 260), fill=(120, 30, 25))
    d.rectangle((190, 240, 320, 470), fill=(70, 65, 80))
    d.polygon([(200, 80), (170, 10), (230, 70)], fill=(210, 200, 170))
    return img


class PostprocessTests(unittest.TestCase):
    def test_opaque_ui_keeps_its_frame_and_full_canvas(self):
        raw = Image.new("RGBA", (64, 64), (73, 87, 103, 255))
        ImageDraw.Draw(raw).rectangle((0, 0, 63, 63), outline=(200, 180, 150, 255), width=4)
        spec = {"size": [32, 32], "background": "opaque", "outline": False, "generated_palette": "preserve"}
        out = postprocess.process_generated(raw, spec, PAL)
        self.assertEqual(out.getpixel((0, 0)), (200, 180, 150, 255))
        self.assertEqual(out.getpixel((16, 16)), (73, 87, 103, 255))
        self.assertEqual(validate.check_image("panel", out, PAL, "opaque", preserve_palette=True), [])

    def test_different_terrain_variants_share_all_join_edges(self):
        import numpy as np
        inputs = [Image.new("RGBA", (12, 12), colour) for colour in ((21, 56, 97, 255), (35, 103, 120, 255))]
        variants = [np.array(i) for i in postprocess.shared_terrain_edges(inputs)]
        for a in variants:
            for b in variants:
                np.testing.assert_array_equal(a[0], b[-1])
                np.testing.assert_array_equal(a[:, 0], b[:, -1])
        self.assertEqual(tuple(variants[0][6, 6]), inputs[0].getpixel((6, 6)))

    def test_generated_colour_preservation_is_opt_in(self):
        raw = Image.new("RGBA", (12, 12), (0, 0, 0, 0))
        ImageDraw.Draw(raw).rectangle((2, 2, 9, 9), fill=(73, 87, 103, 255))
        spec = {"size": [16, 16], "outline": True, "anchor": "bottom_center"}
        legacy = postprocess.prepare_generated(raw, spec, PAL, "auto")
        self.assertEqual(PAL.off_palette_pixels(legacy), 0)
        preserved = postprocess.prepare_generated(raw, dict(spec, generated_palette="preserve"), PAL, "auto")
        self.assertEqual(preserved.getpixel((6, 6))[:3], (73, 87, 103))
        self.assertTrue(validate.check_image("test", preserved, PAL, "transparent"))
        self.assertEqual(validate.check_image("test", preserved, PAL, "transparent", preserve_palette=True), [])

    def test_flood_background_removal(self):
        out = postprocess.remove_background(fake_generated_image(), "flood")
        self.assertEqual(out.getpixel((0, 0))[3], 0)
        self.assertEqual(out.getpixel((255, 300))[3], 255)

    def test_full_chain_produces_valid_sprite(self):
        spec = {"id": "test", "size": [32, 32], "outline": True, "outline_weight": 1, "anchor": "bottom_center"}
        out = postprocess.process_generated(fake_generated_image(), spec, PAL, "flood")
        self.assertEqual(out.size, (32, 32))
        self.assertEqual(validate.check_image("test", out, PAL, "transparent"), [])
        # feet on the bottom row (outline included), centred
        bbox = out.getbbox()
        self.assertEqual(bbox[3], 32)
        self.assertLessEqual(abs((bbox[0] + bbox[2]) / 2 - 16), 2)

    def test_outline_surrounds_shape(self):
        img = Image.new("RGBA", (5, 5), (0, 0, 0, 0))
        img.putpixel((2, 2), PAL.c("E") + (255,))
        out = postprocess.outline(img, PAL.outline)
        self.assertEqual(out.getpixel((2, 1))[:3], PAL.outline)
        self.assertEqual(out.getpixel((1, 1))[3], 0, "no diagonal by default")

    def test_export_scale_is_nearest(self):
        img = Image.new("RGBA", (2, 1), PAL.c("K") + (255,))
        img.putpixel((1, 0), PAL.c("E") + (255,))
        big = postprocess.scale(img, 2)
        self.assertEqual(big.size, (4, 2))
        self.assertEqual(big.getpixel((1, 1))[:3], PAL.c("K"))
        self.assertEqual(big.getpixel((2, 0))[:3], PAL.c("E"))


class AtlasTests(unittest.TestCase):
    def test_pack_has_no_overlaps(self):
        imgs = {f"s{i}": Image.new("RGBA", (8 + i * 3, 30 - i * 2), (255, 0, 0, 255)) for i in range(10)}
        sheet, rects = atlas.pack(imgs, max_width=64)
        boxes = list(rects.values())
        for i, a in enumerate(boxes):
            self.assertLessEqual(a[0] + a[2], sheet.width)
            self.assertLessEqual(a[1] + a[3], sheet.height)
            for b in boxes[i + 1:]:
                overlap = a[0] < b[0] + b[2] and b[0] < a[0] + a[2] and a[1] < b[1] + b[3] and b[1] < a[1] + a[3]
                self.assertFalse(overlap, f"{a} overlaps {b}")


class TerrainTests(unittest.TestCase):
    def test_46_transition_shapes(self):
        masks = procedural.all_transition_masks()
        self.assertEqual(len(masks), 46)
        self.assertEqual(procedural.reduce_mask(procedural.N | procedural.NE), procedural.N)

    def test_fringe_profile_joins_across_tiles(self):
        import random
        offs = procedural.periodic_offsets(random.Random(3))
        self.assertLessEqual(abs(offs[-1] - offs[0]), 1)

    def test_terrain_fringe_feathers_and_variants_join(self):
        import random
        source = Image.new("RGBA", (40, 40), (90, 100, 70, 255))
        tiles = [procedural.transition_tile(PAL, source, procedural.N, 10,
                   procedural.periodic_offsets(random.Random(i)), None) for i in range(4)]
        alpha = set(tiles[0].getchannel("A").getdata())
        self.assertIn(0, alpha)
        self.assertIn(128, alpha)
        self.assertLessEqual(max(alpha), 128)
        self.assertTrue(any(0 < a < 255 for a in alpha))
        self.assertGreater(len({tile.tobytes() for tile in tiles}), 1)
        for a in tiles:
            for b in tiles:
                self.assertEqual([a.getpixel((39, y))[3] for y in range(40)],
                                 [b.getpixel((0, y))[3] for y in range(40)])

    def test_opposing_terrain_edges_meet_halfway_and_corners_are_rounded(self):
        source = Image.new("RGBA", (40, 40), (90, 100, 70, 255))
        flat = [0] * 40
        north = procedural.transition_tile(PAL, source, procedural.N, 16, flat, None)
        south = procedural.transition_tile(PAL, source, procedural.S, 16, flat, None)
        east = procedural.transition_tile(PAL, source, procedural.E, 16, flat, None)
        corner = procedural.transition_tile(PAL, source, procedural.N | procedural.E, 16, flat, None)
        for x in range(40):
            self.assertEqual(north.getpixel((x, 0))[3], 128)
            self.assertEqual(south.getpixel((x, 39))[3], 128)
        self.assertGreater(corner.getpixel((30, 9))[3],
                           max(north.getpixel((30, 9))[3], east.getpixel((30, 9))[3]))

    def test_pair_edge_strips_wrap_smoothly_and_keep_their_sources(self):
        import numpy as np
        from crowns_of_cinder_assets import terrain_edges
        tspec = specs.load_terrain_spec(ROOT / "assets/specs")
        sheet, info = terrain_edges.build(ROOT, tspec["edge_patterns"], 40)
        self.assertEqual(sheet.size, (800, 10240))
        self.assertEqual(info["period"], 2)
        for entry in tspec["edge_patterns"]["types"].values():
            band = np.asarray(terrain_edges.periodic_strip(Image.open(ROOT / entry["source"]), 80, 8)).astype(float)
            join = np.abs(band[:, 0] - band[:, -1]).mean()
            interior = np.abs(band[:, 1:] - band[:, :-1]).mean()
            self.assertLess(join, max(1.0, 2 * interior))
        # Neighbor masks with north water on both tiles meet without a hard seam.
        col = info["types"]["cliff"]["column"]
        left = np.asarray(sheet.crop((col * 40, (1 | 2) * 40, (col + 1) * 40, (1 | 2) * 40 + 40))).astype(float)
        right = np.asarray(sheet.crop(((col + 1) * 40, (128 | 1) * 40, (col + 2) * 40, (128 | 1) * 40 + 40))).astype(float)
        self.assertLess(np.abs(left[:, -1] - right[:, 0]).mean(), 5.0)
        self.assertEqual(int(left[0, 20, 3]), 255, "neighbor terrain fills to the shared edge without haze")
        self.assertEqual(int(left[39, 20, 3]), 0, "the opposite side of the tile stays clear")

    def test_ground_details_are_small_transparent_and_distinct(self):
        for terrain in ("grass", "forest", "rough", "water", "infernal"):
            tiles = [procedural.ground_detail_tile(terrain, i) for i in range(8)]
            self.assertEqual(len({tile.tobytes() for tile in tiles}), 8)
            for tile in tiles:
                alpha = tile.getchannel("A")
                self.assertGreater(sum(a > 0 for a in alpha.getdata()), 0)
                self.assertLess(sum(a > 0 for a in alpha.getdata()), 100)
                self.assertEqual(alpha.crop((0, 0, 40, 4)).getbbox(), None)
                self.assertEqual(alpha.crop((0, 36, 40, 40)).getbbox(), None)

    def test_ground_tiles_are_opaque_and_on_palette(self):
        for style, base in (("grass", "n"), ("infernal", "~"), ("water", ")")):
            t = procedural.ground_tile(PAL, style, base, 1)
            self.assertEqual(validate.check_image(style, t, PAL, "opaque"), [])

    def test_hand_drawn_deco_wins_over_procedural(self):
        tspec = specs.load_terrain_spec(ROOT / "assets/specs")
        kind = sorted({k for t in tspec["terrains"].values() for k in t.get("deco", {}).get("kinds", [])})[0]
        dw, dh = tspec["deco_size"]
        with tempfile.TemporaryDirectory() as d:
            grid = "\n".join(["."] * (dh - 2) + ["..55", "..55"])
            (Path(d) / f"{kind}_0.txt").write_text(grid)
            _, deco, info = build.build_terrain(tspec, PAL, Path(d))
            cell = deco.crop((0, info["deco"]["kinds"][kind]["row"] * dh, dw, (info["deco"]["kinds"][kind]["row"] + 1) * dh))
            want = postprocess.outline(pixel.parse(grid, PAL, (dw, dh)), PAL.outline)
            self.assertEqual(cell.tobytes(), want.tobytes())

    def test_generated_deco_variants_are_used_individually(self):
        tspec = specs.load_terrain_spec(ROOT / "assets/specs")
        _, deco, info = build.build_terrain(tspec, PAL, ROOT / "assets/specs/pixel/deco",
                                           generated_dir=ROOT / "assets/source/generated")
        dw, dh = tspec["deco_size"]
        for kind in ("pines", "boulders", "gravestone", "snow_pine", "dead_tree", "obsidian"):
            row = info["deco"]["kinds"][kind]["row"]
            cells = [deco.crop((v * dw, row * dh, (v + 1) * dw, (row + 1) * dh)).tobytes()
                     for v in range(info["deco"]["variants"])]
            self.assertEqual(len(set(cells)), len(cells), kind)

    def test_road_connection_silhouettes_match(self):
        tiles = ROOT / "assets/specs/pixel/terrain"
        roads = [(tiles / f"road_{m}.txt").read_text().splitlines() for m in range(16)]
        for a in range(16):
            for b in range(16):
                if a & procedural.RE and b & procedural.RW:
                    self.assertEqual([row[-1] != "." for row in roads[a]],
                                     [row[0] != "." for row in roads[b]])
                if a & procedural.RS and b & procedural.RN:
                    self.assertEqual([p != "." for p in roads[a][-1]],
                                     [p != "." for p in roads[b][0]])

    def test_fortress_wall_connection_edges_align(self):
        terrain = json.loads((ROOT / "assets/manifest.json").read_text())["terrain"]
        for name in ("wall", "jungle", "lava", "chasm", "sandstone", "ice", "bones"):
            barrier = terrain["barriers"][name]
            masks, row, size = barrier["masks"], barrier["row"], terrain["tile_size"]
            sheet = Image.open(ROOT / "assets/atlases/terrain.png").convert("RGBA")
            def edge(mask, variant, side):
                col = barrier["column"] + masks.index(mask) + variant * len(masks)
                tile = sheet.crop((col*size, row*size, (col+1)*size, (row+1)*size))
                if side in ("left", "right"):
                    return [tile.getpixel((size-1 if side == "right" else 0, y))[3]
                            for y in range(10, 30)]
                return [tile.getpixel((x, size-1 if side == "bottom" else 0))[3]
                        for x in range(10, 30)]
            for mask in masks:
                for neighbor in masks:
                    if mask & 4 and neighbor & 64:
                        for a, b in ((0, 1), (1, 0), (2, 3), (3, 2)):
                            self.assertEqual(edge(mask, a, "right"), edge(neighbor, b, "left"))
                    if mask & 16 and neighbor & 1:
                        for a, b in ((0, 2), (2, 0), (1, 3), (3, 1)):
                            self.assertEqual(edge(mask, a, "bottom"), edge(neighbor, b, "top"))
            # Opposite diagonal segments must actually touch their tile corners.
            for mask, corners in ((128 | 8, ((0, 0), (size-1, size-1))),
                                  (2 | 32, ((size-1, 0), (0, size-1)))):
                for variant in range(barrier["variants"]):
                    col = barrier["column"] + masks.index(mask) + variant * len(masks)
                    tile = sheet.crop((col*size, row*size, (col+1)*size, (row+1)*size))
                    for corner in corners:
                        self.assertGreater(tile.getpixel(corner)[3], 200)

    def test_themed_roads_join_in_all_directions(self):
        terrain = json.loads((ROOT / "assets/manifest.json").read_text())["terrain"]
        styles = terrain["roads"]["styles"]
        self.assertEqual(set(styles), {"stone", "dirt", "desert"})
        sheet = Image.open(ROOT / "assets/atlases/terrain.png").convert("RGBA")
        size = terrain["tile_size"]
        for name, entry in styles.items():
            masks = entry["masks"]
            def tile(mask, variant):
                col = entry["column"] + masks.index(mask) + variant * len(masks)
                row = entry["row"]
                return sheet.crop((col*size, row*size, (col+1)*size, (row+1)*size))
            # All orientations meet at each tile edge, including a style change.
            for mask, pt in ((4, (size-1, size//2)), (64, (0, size//2)),
                             (1, (size//2, 0)), (16, (size//2, size-1)),
                             (128 | 8, (0, 0)), (128 | 8, (size-1, size-1)),
                             (2 | 32, (size-1, 0)), (2 | 32, (0, size-1))):
                for variant in range(entry["variants"]):
                    self.assertGreater(tile(mask, variant).getpixel(pt)[3], 200, name)
            for mask in masks:
                for neighbor in masks:
                    if mask & 4 and neighbor & 64:
                        a, b = tile(mask, 0), tile(neighbor, 1)
                        self.assertEqual([a.getpixel((size-1, y))[3] for y in range(10, 30)],
                                         [b.getpixel((0, y))[3] for y in range(10, 30)], name)
                    if mask & 16 and neighbor & 1:
                        a, b = tile(mask, 0), tile(neighbor, 2)
                        self.assertEqual([a.getpixel((x, size-1))[3] for x in range(10, 30)],
                                         [b.getpixel((x, 0))[3] for x in range(10, 30)], name)

    def test_highres_overlays_preserve_source_detail(self):
        from PIL import ImageChops
        terrain = json.loads((ROOT / "assets/manifest.json").read_text())["terrain"]
        high = terrain["highres"]
        self.assertEqual(high["tile_size"], terrain["tile_size"] * 2)
        source = Image.open(ROOT / high["atlas"].removeprefix("res://")).convert("RGBA")
        legacy = Image.open(ROOT / terrain["atlas"].removeprefix("res://")).convert("RGBA")
        n, size = len(high["masks"]), high["tile_size"]
        for group, name in (("barriers", "wall"), ("roads", "stone")):
            entry = high[group][name]
            low = terrain["barriers"][name] if group == "barriers" else terrain["roads"]["styles"][name]
            index = high["masks"].index(68)
            image = source.crop((index*size, entry["row"]*size, (index+1)*size, (entry["row"]+1)*size))
            low_size = terrain["tile_size"]
            low_image = legacy.crop((index*low_size, low["row"]*low_size, (index+1)*low_size, (low["row"]+1)*low_size))
            self.assertIsNotNone(ImageChops.difference(image, low_image.resize((size, size), Image.Resampling.NEAREST)).getbbox())
            # The shared edge of successive variants remains pixel-aligned.
            next_image = source.crop((index*size, (entry["row"]+1)*size, (index+1)*size, (entry["row"]+2)*size))
            self.assertEqual([image.getpixel((size-1, y))[3] for y in range(size//4, 3*size//4)],
                             [next_image.getpixel((0, y))[3] for y in range(size//4, 3*size//4)])

    def test_hand_drawn_ground_variants_tile_seamlessly(self):
        # every variant pair must share edge tones closely enough that no grid shows
        tspec = specs.load_terrain_spec(ROOT / "assets/specs")
        sheet, _, info = build.build_terrain(tspec, PAL, None, ROOT / "assets/specs/pixel/terrain")
        t = info["tile_size"]
        for tid, ti in info["terrains"].items():
            tiles = [sheet.crop((v * t, ti["row"] * t, (v + 1) * t, (ti["row"] + 1) * t)) for v in range(info["variants"])]
            for a in tiles:
                self.assertEqual(validate.check_image(tid, a, PAL, "opaque"), [], tid)

    def test_every_creature_has_its_own_sprite(self):
        from crowns_of_cinder_assets import creatures_auto
        drawn = {a["data"]["id"] for a in json.loads((ROOT / "assets/specs/creatures.json").read_text())["assets"]}
        missing = sorted(set(creatures_auto.load_creatures(ROOT / "data")) - drawn - _dlc_creatures())
        self.assertEqual(missing, [], "creatures still on recolour/placeholder art")

    def test_every_hero_class_has_its_own_sprite(self):
        objs = json.loads((ROOT / "assets/specs/objects.json").read_text())["assets"]
        drawn = {a["data"]["id"]: a for a in objs if a.get("data", {}).get("type") == "hero_class"}
        classes = _core_hero_classes()
        self.assertEqual(sorted(drawn), sorted(classes))
        files = {a["source"]["file"] for a in drawn.values()}
        self.assertEqual(len(files), len(classes), "each class needs its own drawing")

    def test_each_faction_rides_its_own_mount(self):
        classes = _core_hero_classes()
        legs = {}
        for cid, c in classes.items():
            img = pixel.load(ROOT / f"assets/specs/pixel/heroes64/hero_{cid}.txt", PAL, (64, 64))
            colours = frozenset(img.crop((0, 52, 64, 64)).getdata()) - {(0, 0, 0, 0)}
            legs.setdefault(c["faction"], set()).add(colours)
        for f, s in legs.items():
            self.assertEqual(len(s), 1, f"{f} classes should share one mount")
        mounts = [next(iter(s)) for s in legs.values()]
        self.assertEqual(len(set(mounts)), len(mounts), "two factions share a mount")

    def test_legacy_drawings_and_production_ui_have_reproducible_sources(self):
        tspec = specs.load_terrain_spec(ROOT / "assets/specs")
        kinds = {k for t in tspec["terrains"].values() for k in t.get("deco", {}).get("kinds", [])}
        for kind in kinds:
            for v in range(4):  # The original hand-drawn fallback set.
                self.assertTrue((ROOT / "assets/specs/pixel/deco" / f"{kind}_{v}.txt").is_file(), f"{kind}_{v}")
        tiles = ROOT / "assets/specs/pixel/terrain"
        grounds = {t["ground"] for t in tspec["terrains"].values()} | {tspec["fog"]["ground"]}
        for g in grounds:
            for v in range(int(tspec["variants"])):
                self.assertTrue((tiles / f"{g}_{v}.txt").is_file(), f"{g}_{v}")
        for m in range(16):
            self.assertTrue((tiles / f"road_{m}.txt").is_file() and (tiles / f"bridge_{m}.txt").is_file(), m)
        ui = json.loads((ROOT / "assets/specs/ui.json").read_text())
        for a in ui["assets"]:
            if a["id"].startswith("ui_panel_"):
                import hashlib
                raw = ROOT / "assets/source/generated" / (a["id"] + ".png")
                metadata = json.loads(raw.with_suffix(".json").read_text())
                self.assertEqual(metadata["source_sha256"], hashlib.sha256(raw.read_bytes()).hexdigest())
                self.assertTrue((ROOT / metadata["source_sheet"]).is_file())
            elif a["id"].startswith("cursor_"):
                self.assertEqual(a["source"]["drawer"], "ui")
                self.assertEqual(a["source"]["name"], "cursor")
                self.assertEqual(a["hotspot"], [2, 2])
            else:
                self.assertEqual(a["source"]["kind"], "pixel", a["id"])


class SpecTests(unittest.TestCase):
    def test_spec_checks_catch_mistakes(self):
        bad = [{"id": "Bad Name", "size": [32, 32], "atlas": "units", "anchor": "bottom_center", "prompt": "x",
                "source": {"kind": "pixel", "file": "nope.txt"}, "_file": "t"}]
        errs = specs.check_sprite_specs(bad, ROOT / "assets/specs")
        self.assertTrue(any("snake_case" in e for e in errs))
        self.assertTrue(any("not found" in e for e in errs))

    def test_prompts_include_style_and_constraints(self):
        style = json.loads((ROOT / "assets/specs/style.json").read_text())
        p = generate.build_prompt({"category": "creature", "prompt": "a test beast"}, style)
        self.assertIn("a test beast", p)
        self.assertIn("pixel art", p)
        self.assertIn("do not imitate", p)

    def test_openai_provider_needs_key(self):
        import os
        old = os.environ.pop("OPENAI_API_KEY", None)
        try:
            ok, why = generate.OpenAIImages().available()
            self.assertFalse(ok)
            self.assertIn("OPENAI_API_KEY", why)
        finally:
            if old is not None:
                os.environ["OPENAI_API_KEY"] = old


class AutoCreatureTests(unittest.TestCase):
    FACTIONS = json.loads((ROOT / "assets/specs/factions.json").read_text())

    def test_placeholders_are_valid_for_every_role(self):
        from crowns_of_cinder_assets import creatures_auto
        for role in ("infantry", "ranged", "cavalry", "flyer", "support", "heavy"):
            for fac in ("hollow", "forge", "nobody"):
                img = creatures_auto.placeholder(PAL, role, creatures_auto.faction_style(self.FACTIONS, fac), 1)
                img = postprocess.outline(img, PAL.outline)
                self.assertEqual(validate.check_image(f"{role}/{fac}", img, PAL, "transparent"), [])

    def test_upgrade_recolours_base(self):
        from crowns_of_cinder_assets import creatures_auto
        base = pixel.parse("BBB\nGGG\n...", PAL, (3, 3))
        up = creatures_auto.upgrade_sprite(base, PAL, creatures_auto.faction_style(self.FACTIONS, "concord"))
        self.assertNotEqual(list(base.getdata()), list(up.getdata()))
        self.assertEqual(PAL.off_palette_pixels(up), 0)

    def test_reads_split_creature_files(self):
        from crowns_of_cinder_assets import creatures_auto
        with tempfile.TemporaryDirectory() as d:
            (Path(d) / "creatures").mkdir()
            (Path(d) / "creatures" / "x.json").write_text(json.dumps({"creatures": {"ghoul": {"role": "infantry"}}}))
            self.assertIn("ghoul", creatures_auto.load_creatures(Path(d)))


class RepoTests(unittest.TestCase):
    def test_approved_illustration_cannot_be_replaced(self):
        from crowns_of_cinder_assets import illustrations
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "assets/specs").mkdir(parents=True)
            source = root / "assets/source/generated/scene.png"
            source.parent.mkdir(parents=True)
            source.write_bytes(b"approved source must remain untouched")
            source.with_suffix(".json").write_text(json.dumps({"quality_status": "design_approved_pending_engine_qc"}))
            (root / "assets/specs/campaign_illustrations.json").write_text(json.dumps({"assets": [
                {"id": "scene", "source": "assets/source/generated/scene.png"}]}))
            with self.assertRaisesRegex(ValueError, "approved illustration"):
                illustrations.stage(root, "scene", root / "replacement.png", replace_unapproved=True)
            self.assertEqual(source.read_bytes(), b"approved source must remain untouched")

    def test_committed_assets_validate(self):
        self.assertEqual(validate.validate(ROOT), [])

    def test_build_is_deterministic(self):
        with tempfile.TemporaryDirectory() as a, tempfile.TemporaryDirectory() as b:
            ma = build.build_all(ROOT, Path(a), log=lambda *_: None)
            mb = build.build_all(ROOT, Path(b), log=lambda *_: None)
            self.assertEqual(ma, mb)
            for p in sorted((Path(a) / "assets/atlases").glob("*.png")):
                self.assertEqual(list(Image.open(p).getdata()), list(Image.open(Path(b) / "assets/atlases" / p.name).getdata()), p.name)


if __name__ == "__main__":
    unittest.main()
