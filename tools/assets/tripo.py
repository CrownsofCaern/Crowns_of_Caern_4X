"""Make rigged, animated 3D battle models with the Tripo API.

  python3 tools/assets/tripo.py balance
  python3 tools/assets/tripo.py model ID [--image PNG] [--crop L,T,R,B]   # painting -> textured model
  python3 tools/assets/tripo.py rig ID                                    # auto-rig (biped / quadruped / ...)
  python3 tools/assets/tripo.py animate ID [PRESET ...]                   # preset clips onto the rig
  python3 tools/assets/tripo.py all ID [--image PNG]                      # model, rig and animate in one go
  python3 tools/assets/tripo.py status

Needs network access to api.tripo3d.ai (plus the host the model downloads
come from) and the API key: either as a Bearer network secret for
api.tripo3d.ai in the cloud environment (the proxy adds the header, so the
key never reaches this script) or as TRIPO_API_KEY. Every task Tripo accepts is written to
assets/specs/creature_models.json straight away (unit["tripo"]), so a rerun
resumes or re-downloads the same task instead of paying for a new one;
--force asks for a fresh task. Downloads land in assets/source/models/<id>/
(Godot-ignored; the bake tool reads GLBs straight from disk).

The default image is the unit's drawn still, scaled up 4x. A larger painting
of the creature gives Tripo far more to work with: pass --image (and --crop to
cut one creature out of a sheet). After `animate`, the unit's clips point at
the downloaded files; tune frame counts in the spec, then run
`bake_models.py render ID`.
"""
from __future__ import annotations

import argparse
import io
import json
import os
import sys
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path
from typing import Callable

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from crowns_of_cinder_assets import model_animations  # noqa: E402
from PIL import Image  # noqa: E402

API = os.environ.get("TRIPO_API_BASE", "https://api.tripo3d.ai/v2/openapi")
# Found in the Nov 10 test: humans need the default (v1) rigger with the Mixamo
# skeleton, because preset animations only retarget onto v1 rigs and the v2
# rigger gave the pikeman one leg. The v1 rigger fails on quadrupeds (error
# 1004); the v2 rigger rigs them and quadruped presets retarget onto it.
RIG_V2 = os.environ.get("TRIPO_RIG_VERSION", "v2.0-20250506")
DONE = {"success"}
FAILED = {"failed", "cancelled", "banned", "expired", "unknown"}
# Battle actions and the Tripo animation presets that feed them, per rig type.
PRESETS = {
    "biped": {"idle": "preset:idle", "move": "preset:walk", "attack": "preset:slash"},
    # Only walk exists for quadrupeds (bite/attack are rejected as invalid names).
    "quadruped": {"move": "preset:quadruped:walk"},
    # Crawlers (spiders, crabs, beetles): walk only, like quadrupeds.
    "hexapod": {"move": "preset:hexapod:walk"},
    "octopod": {"move": "preset:octopod:walk"},
}
FRAMES = {"idle": 6, "move": 8, "attack": 8, "death": 7}

Transport = Callable[[str, str, dict | None, bytes | None, dict], dict]


USER_AGENT = "crowns-of-cinder-assets/1.0"


class TripoError(RuntimeError):
    pass


def http(method: str, url: str, payload: dict | None, body: bytes | None, headers: dict) -> dict:
    data = json.dumps(payload).encode() if payload is not None else body
    if payload is not None:
        headers = {**headers, "Content-Type": "application/json"}
    # Tripo's edge (Cloudflare) rejects Python's default user agent (error 1010).
    headers = {"User-Agent": USER_AGENT, **headers}
    request = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            return json.loads(response.read())
    except urllib.error.HTTPError as error:
        hint = " (no API key: add a Bearer network secret for api.tripo3d.ai or set TRIPO_API_KEY)" if error.code == 401 else ""
        raise TripoError(f"{method} {url}: HTTP {error.code} {error.read()[:400]!r}{hint}") from None
    except urllib.error.URLError as error:
        raise TripoError(f"{method} {url}: {error.reason} (is the host allowed in the environment's network settings?)") from None


class Client:
    def __init__(self, key: str, transport: Transport = http, sleep: Callable[[float], None] = time.sleep):
        # No key: the environment's network secret adds the header on the way out.
        self.headers = {"Authorization": f"Bearer {key}"} if key else {}
        self.transport = transport
        self.sleep = sleep

    def _data(self, reply: dict) -> dict:
        if reply.get("code", 0) != 0:
            raise TripoError(f"Tripo error {reply.get('code')}: {reply.get('message', reply)}")
        return reply.get("data", {})

    def balance(self) -> dict:
        return self._data(self.transport("GET", f"{API}/user/balance", None, None, self.headers))

    def upload(self, png: bytes) -> str:
        boundary = uuid.uuid4().hex
        body = (f"--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"image.png\"\r\n"
                f"Content-Type: image/png\r\n\r\n").encode() + png + f"\r\n--{boundary}--\r\n".encode()
        headers = {**self.headers, "Content-Type": f"multipart/form-data; boundary={boundary}"}
        data = self._data(self.transport("POST", f"{API}/upload", None, body, headers))
        return data.get("image_token") or data["file_token"]

    def create(self, payload: dict) -> str:
        return self._data(self.transport("POST", f"{API}/task", payload, None, self.headers))["task_id"]

    def wait(self, task_id: str, timeout_s: float = 1800, every_s: float = 5) -> dict:
        waited = 0.0
        while True:
            task = self._data(self.transport("GET", f"{API}/task/{task_id}", None, None, self.headers))
            status = task.get("status", "")
            if status in DONE:
                return task
            if status in FAILED:
                raise TripoError(f"task {task_id} {status}: {task.get('error', '')}")
            if waited >= timeout_s:
                raise TripoError(f"task {task_id} still {status} after {int(waited)} s; rerun to resume")
            self.sleep(every_s)
            waited += every_s


def download(url: str, destination: Path) -> Path:
    destination.parent.mkdir(parents=True, exist_ok=True)
    try:
        # The download CDN refuses Python's default user agent.
        request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
        with urllib.request.urlopen(request, timeout=300) as response:
            destination.write_bytes(response.read())
    except urllib.error.URLError as error:
        host = urllib.request.urlparse(url).hostname
        raise TripoError(f"download from {host} failed: {getattr(error, 'reason', error)} (allow {host}?)") from None
    return destination


def model_url(task: dict) -> str:
    out = task.get("output", {})
    for key in ("pbr_model", "model", "base_model"):
        if out.get(key):
            return out[key]
    raise TripoError(f"task {task.get('task_id')} has no model output: {sorted(out)}")


# --- spec bookkeeping --------------------------------------------------------

def load() -> dict:
    return model_animations.load_spec(ROOT)


def save(spec: dict) -> None:
    path = ROOT / model_animations.SPEC
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(spec, indent=2) + "\n")


def unit_entry(spec: dict, uid: str) -> dict:
    for unit in spec.setdefault("units", []):
        if unit["id"] == uid:
            return unit
    unit = {"id": uid}
    spec["units"].append(unit)
    return unit


def model_dir(uid: str) -> Path:
    return ROOT / "assets/source/models" / uid


def rel(path: Path) -> str:
    return str(path.relative_to(ROOT))


def source_image(uid: str, image: str | None, crop: str | None) -> bytes:
    if image:
        img = Image.open(image).convert("RGBA")
    else:
        still = ROOT / f"assets/build/creature/creature_{uid}.png"
        if not still.is_file():
            raise TripoError(f"{uid}: no drawn still; pass --image")
        img = Image.open(still).convert("RGBA")
        img = img.resize((img.width * 4, img.height * 4), Image.Resampling.NEAREST)
    if crop:
        img = img.crop(tuple(int(v) for v in crop.split(",")))
    buffer = io.BytesIO()
    img.save(buffer, "PNG")
    return buffer.getvalue()


def step(spec: dict, unit: dict, name: str, client: Client, payload: Callable[[], dict], force: bool) -> dict:
    """Runs one Tripo task, recording its id before waiting so it is never paid twice."""
    record = unit.setdefault("tripo", {})
    if force or not record.get(name):
        record[name] = client.create(payload())
        save(spec)
    return client.wait(record[name])


def run_model(spec: dict, unit: dict, client: Client, image: str | None, crop: str | None, force: bool) -> None:
    uid = unit["id"]

    def payload() -> dict:
        token = client.upload(source_image(uid, image, crop))
        body = {"type": "image_to_model", "file": {"type": "png", "file_token": token},
                "texture": True, "pbr": True, "texture_quality": "detailed"}
        if os.environ.get("TRIPO_MODEL_VERSION"):
            body["model_version"] = os.environ["TRIPO_MODEL_VERSION"]
        return body

    task = step(spec, unit, "model_task", client, payload, force)
    path = download(model_url(task), model_dir(uid) / f"{uid}_model.glb")
    unit["tripo"]["model"] = rel(path)
    save(spec)
    print(f"{uid}: model {rel(path)}")


def run_rig(spec: dict, unit: dict, client: Client, force: bool, rig_type: str | None = None) -> None:
    uid = unit["id"]
    base = unit.get("tripo", {}).get("model_task")
    if not base:
        raise TripoError(f"{uid}: run `model` first")
    check = step(spec, unit, "rigcheck_task", client,
                 lambda: {"type": "animate_prerigcheck", "original_model_task_id": base}, force)
    out = check.get("output", {})
    if not out.get("riggable", True):
        # The check is cautious: the pikeman it rejected rigged fine.
        print(f"{uid}: Tripo's pre-check says not riggable ({out}); trying anyway (a failed task costs nothing)")
    # --rig-type overrides the pre-check, which says "others" for crawlers,
    # robed casters and dragons that rig fine as quadruped, biped or avian.
    rig_type = rig_type or out.get("rig_type", "biped")
    unit["tripo"]["rig_type"] = rig_type
    task = step(spec, unit, "rig_task", client, lambda: {
        "type": "animate_rig", "original_model_task_id": base, "out_format": "glb", "rig_type": rig_type,
        **({"spec": "mixamo"} if rig_type == "biped" else {"model_version": RIG_V2})}, force)
    path = download(model_url(task), model_dir(uid) / f"{uid}_rigged.glb")
    unit["tripo"]["rigged"] = rel(path)
    unit.setdefault("model", rel(path))
    save(spec)
    print(f"{uid}: {rig_type} rig {rel(path)}")


def run_animate(spec: dict, unit: dict, client: Client, presets: list[str], force: bool) -> None:
    uid = unit["id"]
    record = unit.get("tripo", {})
    if not record.get("rig_task"):
        raise TripoError(f"{uid}: run `rig` first")
    table = PRESETS.get(record.get("rig_type", "biped"), PRESETS["biped"])
    wanted = {action: preset for action, preset in table.items() if not presets or preset in presets or action in presets}
    clips = unit.setdefault("clips", {})
    for action, preset in wanted.items():
        name = f"anim_{action}_task"
        task = step(spec, unit, name, client, lambda p=preset: {
            "type": "animate_retarget", "original_model_task_id": record["rig_task"], "out_format": "glb",
            "animation": p, "bake_animation": True}, force)
        path = download(model_url(task), model_dir(uid) / f"{uid}_{action}.glb")
        clip = clips.setdefault(action, {"frames": FRAMES[action]})
        clip["model"] = rel(path)
        clip["clip"] = clip.get("clip", "")   # empty: the file's first clip
        clip["preset"] = preset
        save(spec)
        print(f"{uid}: {action} <- {preset} ({rel(path)})")


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("balance")
    sub.add_parser("status")
    for name in ("model", "rig", "animate", "all"):
        p = sub.add_parser(name)
        p.add_argument("id")
        p.add_argument("--force", action="store_true", help="pay for a fresh task instead of resuming the recorded one")
        if name in ("model", "all"):
            p.add_argument("--image")
            p.add_argument("--crop", help="L,T,R,B box to cut from the image")
        if name in ("rig", "all"):
            p.add_argument("--rig-type", choices=["biped", "quadruped", "hexapod", "octopod", "avian", "serpentine", "aquatic"],
                           help="rig as this body type instead of what Tripo's pre-check suggests")
        if name == "animate":
            p.add_argument("presets", nargs="*", help="actions or presets to (re)make; default all")
    args = parser.parse_args(argv)
    if args.cmd == "status":
        for unit in load().get("units", []):
            t = unit.get("tripo", {})
            steps = [k.removesuffix("_task") for k in t if k.endswith("_task")]
            print(f"{unit['id']:24} {t.get('rig_type', '-'):10} {', '.join(steps) or '-'}")
        return
    client = Client(os.environ.get("TRIPO_API_KEY", ""))
    if args.cmd == "balance":
        print(json.dumps(client.balance(), indent=2))
        return
    spec = load()
    unit = unit_entry(spec, args.id)
    try:
        if args.cmd in ("model", "all"):
            run_model(spec, unit, client, args.image, args.crop, args.force)
        if args.cmd in ("rig", "all"):
            run_rig(spec, unit, client, args.force, args.rig_type)
        if args.cmd in ("animate", "all"):
            run_animate(spec, unit, client, getattr(args, "presets", []), args.force)
    except TripoError as error:
        raise SystemExit(f"tripo: {error}")


if __name__ == "__main__":
    main()
