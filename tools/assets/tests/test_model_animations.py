"""3D model bake pipeline: approved bake sheets replace battle clips, pending
or changed sheets do not, the pixel pass lands on the anchor and the master
palette, imported clips map to battle actions by name, and the Tripo client
records each paid task before waiting on it."""
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from crowns_of_cinder_assets import animations, model_animations
from crowns_of_cinder_assets.palette import Palette
import bake_models
import numpy as np
import rigid_weapon
import split_weapon
import tripo

SIZE = animations.SIZE


def unit_spec(sheet: str, sha: str | None = None) -> dict:
    unit = {"id": "pike_militia", "model": "x.glb", "bake": {"sheet": sheet},
            "clips": {"idle": {"clip": "Idle", "frames": 2}, "move": {"clip": "Walk", "frames": 3},
                      "attack": {"clip": "Thrust", "frames": 4, "impact_frame": 2, "ms": 100}}}
    if sha:
        unit["bake"]["sheet_sha256"] = sha
    return {"schema_version": 1, "units": [unit]}


def figure(x: int, colour=(80, 90, 120, 255)) -> Image.Image:
    img = Image.new("RGBA", SIZE)
    ImageDraw.Draw(img).rectangle((x, 100, x + 20, 200), fill=colour)
    return img


class ModelBuildTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        (self.root / "assets/specs").mkdir(parents=True)
        sheet = Image.new("RGBA", (4 * SIZE[0], 3 * SIZE[1]))
        for row, count in enumerate([2, 3, 4]):
            for col in range(count):
                sheet.paste(figure(140 + col * 5), (col * SIZE[0], row * SIZE[1]))
        self.sheet_rel = "assets/source/models/pike_militia/pike_militia_bake.png"
        (self.root / self.sheet_rel).parent.mkdir(parents=True)
        sheet.save(self.root / self.sheet_rel)
        self.sha = animations.digest(self.root / self.sheet_rel)

    def tearDown(self):
        self.tmp.cleanup()

    def manifest(self):
        return {"units": {"creature_pike_militia": {"atlas": "animation_concord-01", "actions": {
            "move": {"frames": [[0, 0, 320, 256]]}, "attack": {"frames": [[0, 0, 320, 256]]}}}},
            "pending": [], "atlases": {}, "qc": {}}

    def write_spec(self, spec):
        (self.root / model_animations.SPEC).write_text(json.dumps(spec))

    def test_approved_sheet_replaces_battle_clips(self):
        self.write_spec(unit_spec(self.sheet_rel, self.sha))
        manifest = self.manifest()
        model_animations.build(self.root, self.root, manifest)
        actions = manifest["units"]["creature_pike_militia"]["actions"]
        self.assertEqual(sorted(actions), ["attack", "idle", "move"])
        self.assertEqual(actions["move"]["atlas"], "animation_model_pike_militia")
        self.assertEqual(len(actions["move"]["frames"]), 3)
        self.assertTrue(actions["move"]["loop"])
        self.assertFalse(actions["attack"]["loop"])
        self.assertEqual(actions["attack"]["events"], [{"time_ms": 200, "name": "impact"}])
        self.assertEqual(actions["idle"]["frames"][1], [320, 0, 320, 256])
        atlas = manifest["atlases"]["animation_model_pike_militia"]
        self.assertEqual(atlas["size"], [4 * SIZE[0], 3 * SIZE[1]])
        self.assertTrue((self.root / atlas["path"].removeprefix("res://")).is_file())

    def test_pending_sheet_changes_nothing(self):
        self.write_spec(unit_spec(self.sheet_rel))
        manifest = self.manifest()
        model_animations.build(self.root, self.root, manifest)
        self.assertEqual(manifest, self.manifest())

    def test_changed_sheet_is_rejected(self):
        self.write_spec(unit_spec(self.sheet_rel, "0" * 64))
        with self.assertRaises(ValueError):
            model_animations.build(self.root, self.root, self.manifest())

    def test_wrong_sheet_size_is_rejected(self):
        spec = unit_spec(self.sheet_rel, self.sha)
        spec["units"][0]["clips"]["attack"]["frames"] = 6
        self.write_spec(spec)
        with self.assertRaises(ValueError):
            model_animations.build(self.root, self.root, self.manifest())

    def test_impact_frame_must_be_inside_the_clip(self):
        spec = unit_spec(self.sheet_rel, self.sha)
        spec["units"][0]["clips"]["attack"]["impact_frame"] = 4
        self.write_spec(spec)
        with self.assertRaises(ValueError):
            model_animations.build(self.root, self.root, self.manifest())

    def test_repo_spec_entries_are_consistent(self):
        for unit in model_animations.load_spec(ROOT).get("units", []):
            if not unit.get("clips"):
                continue   # model made, not animated yet
            self.assertTrue(model_animations.layout(unit), unit["id"])
            for action in unit["clips"]:
                self.assertIn(action, model_animations.ACTIONS)


class PixelPassTests(unittest.TestCase):
    def test_rest_pose_lands_on_the_anchor_in_palette_with_outline(self):
        palette = Palette.load(ROOT / "assets/specs/palette.json")
        raw = Image.new("RGBA", (640, 512))
        ImageDraw.Draw(raw).rectangle((300, 100, 340, 400), fill=(70, 80, 110, 255))
        scale, dx, dy = bake_models.placement(raw, 120)
        cell = bake_models.pixelate(raw, scale, dx, dy, palette)
        self.assertEqual(cell.size, SIZE)
        box = cell.getchannel("A").getbbox()
        self.assertLessEqual(abs(box[3] - 1 - animations.ANCHOR[1]), 2)
        self.assertLessEqual(abs((box[0] + box[2]) / 2 - animations.ANCHOR[0]), 2)
        self.assertEqual(palette.off_palette_pixels(cell), 0)
        self.assertEqual(cell.getpixel((box[0], (box[1] + box[3]) // 2))[:3], palette.outline)

    def test_empty_render_is_an_error(self):
        with self.assertRaises(ValueError):
            bake_models.placement(Image.new("RGBA", (64, 64)), 120)


class ImportTests(unittest.TestCase):
    def test_clips_map_by_name_and_overrides_win(self):
        available = {"a.glb": ["Armature|Idle_Breathing", "Run Forward"], "b.glb": ["Bite_Attack", "Dying"]}
        mapped = bake_models.map_clips(available, {})
        self.assertEqual(mapped["idle"], {"model": "a.glb", "clip": "Armature|Idle_Breathing"})
        self.assertEqual(mapped["move"]["clip"], "Run Forward")
        self.assertEqual(mapped["attack"], {"model": "b.glb", "clip": "Bite_Attack"})
        self.assertEqual(mapped["death"]["clip"], "Dying")
        self.assertEqual(bake_models.map_clips(available, {"move": "run forward"})["move"]["clip"], "Run Forward")
        with self.assertRaises(SystemExit):
            bake_models.map_clips(available, {"attack": "Kick"})


def tube(a, b, radius, rings=40, sides=8):
    """Vertices and triangles of an open tube from a to b."""
    a, b = np.asarray(a, float), np.asarray(b, float)
    axis = (b - a) / np.linalg.norm(b - a)
    side = np.cross(axis, [1.0, 0.0, 0.0])
    side /= np.linalg.norm(side)
    other = np.cross(axis, side)
    pts = [a + (b - a) * t + radius * (np.cos(k * 2 * np.pi / sides) * side + np.sin(k * 2 * np.pi / sides) * other)
           for t in np.linspace(0, 1, rings) for k in range(sides)]
    tris = []
    for r in range(rings - 1):
        for k in range(sides):
            i, j = r * sides + k, r * sides + (k + 1) % sides
            tris += [(i, j, i + sides), (j, j + sides, i + sides)]
    return np.array(pts), np.array(tris)


class SplitWeaponTests(unittest.TestCase):
    def test_pole_and_bent_butt_are_found_body_is_kept(self):
        body, body_tri = tube([0.3, 0.0, 0], [0.3, 0.7, 0], 0.15)
        shaft, shaft_tri = tube([0.6, 0.25, 0], [0.6, 1.0, 0], 0.02)
        butt, butt_tri = tube([0.66, 0.0, 0], [0.62, 0.24, 0], 0.02)   # bent away from the line
        pos = np.vstack([body, shaft, butt])
        tri = np.vstack([body_tri, shaft_tri + len(body), butt_tri + len(body) + len(shaft)])
        found = split_weapon.pole(pos)
        self.assertLess(abs(found["end"][0] - 0.6), 0.02)
        self.assertGreater(found["end"][1], 0.95)
        extra = split_weapon.remnants(pos, tri, found)
        mask = found["mask"] | extra
        self.assertFalse(mask[:len(body)].any())
        self.assertTrue(mask[len(body):len(body) + len(shaft)].all())
        self.assertTrue(mask[len(body) + len(shaft):].all())


class RigidWeaponTests(unittest.TestCase):
    def test_auto_finds_the_blade_not_the_arm_or_body(self):
        body, body_tri = tube([0.0, 0.0, 0], [0.0, 0.7, 0], 0.15)
        arm, arm_tri = tube([0.12, 0.55, 0], [0.35, 0.35, 0], 0.04)
        blade, blade_tri = tube([0.33, 0.37, 0], [0.9, 0.1, 0], 0.015, rings=80)
        pos = np.vstack([body, arm, blade])
        tri = np.vstack([body_tri, arm_tri + len(body), blade_tri + len(body) + len(arm)])
        hand, elbow = np.array([0.35, 0.35, 0]), np.array([0.2, 0.48, 0])
        back = (elbow - hand) / np.linalg.norm(elbow - hand)
        (a, b, r), guard = rigid_weapon.auto_capsule(pos, hand, back)
        self.assertLess(np.linalg.norm(np.subtract(b, [0.9, 0.1, 0])), 0.04)
        self.assertLess(r, 0.05)
        mask = rigid_weapon.select(pos, {"capsule": [a, b, r]}, None, [], tri)
        self.assertGreater(mask[len(body) + len(arm):].mean(), 0.97)
        self.assertFalse(mask[:len(body)].any())

    def test_slab_takes_the_whole_shield_sheet(self):
        body, body_tri = tube([0.0, 0.0, 0], [0.0, 0.7, 0], 0.15)
        # A thick shield: two faces 0.04 apart, joined at the rim.
        xs, ys = np.meshgrid(np.linspace(-0.2, 0.2, 12), np.linspace(0.05, 0.6, 12))
        front = np.stack([xs.ravel(), ys.ravel(), np.full(xs.size, -0.25)], axis=1)
        rear = front + [0, 0, 0.04]
        sheet = np.vstack([front, rear])
        tris = []
        for i in range(11):
            for j in range(11):
                k = i * 12 + j
                tris += [(k, k + 1, k + 12), (k + 1, k + 13, k + 12)]
        tris = np.array(tris)
        # The bottom and top edges link the faces.
        rim = np.array([(k, k + 144, k + 1) for k in range(11)] + [(k, k + 144, k + 1) for k in range(132, 143)])
        pos = np.vstack([body, sheet])
        tri = np.vstack([body_tri, tris + len(body), tris + len(body) + 144, rim + len(body)])
        region = {"slab": [[[-0.2, -0.25], [0.2, -0.25]], 0.015, [0.0, 0.7]]}
        mask = rigid_weapon.select(pos, region, None, [], tri)
        self.assertTrue(mask[len(body):].all())   # the rear face joins by growth
        self.assertFalse(mask[:len(body)].any())


class TripoClientTests(unittest.TestCase):
    def test_task_id_is_saved_before_waiting_and_reused(self):
        calls = []
        status = iter(["queued", "running", "success"])

        def transport(method, url, payload, body, headers):
            calls.append((method, url.rsplit("/", 1)[-1], payload))
            self.assertEqual(headers["Authorization"], "Bearer k")
            if method == "POST":
                return {"code": 0, "data": {"task_id": "t1"}}
            return {"code": 0, "data": {"status": next(status, "success"), "output": {"model": "https://x/m.glb"}}}

        client = tripo.Client("k", transport, sleep=lambda s: None)
        spec, unit, saved = {"units": []}, {"id": "scorchhound"}, []
        with patch.object(tripo, "save", lambda s: saved.append(json.dumps(unit))):
            task = tripo.step(spec, unit, "model_task", client, lambda: {"type": "image_to_model"}, False)
            self.assertEqual(tripo.model_url(task), "https://x/m.glb")
            self.assertIn("t1", saved[0])
            tripo.step(spec, unit, "model_task", client, lambda: {"type": "image_to_model"}, False)
        self.assertEqual([c for c in calls if c[0] == "POST"], [("POST", "task", {"type": "image_to_model"})])

    def test_failed_task_and_api_error_raise(self):
        client = tripo.Client("k", lambda *a: {"code": 0, "data": {"status": "failed"}}, sleep=lambda s: None)
        with self.assertRaises(tripo.TripoError):
            client.wait("t")
        client = tripo.Client("k", lambda *a: {"code": 2001, "message": "no credits"})
        with self.assertRaises(tripo.TripoError):
            client.balance()
        seen = []
        tripo.Client("", lambda m, u, p, b, h: seen.append(h) or {"code": 0, "data": {}}).balance()
        self.assertEqual(seen, [{}])   # the network secret supplies the header


if __name__ == "__main__":
    unittest.main()
