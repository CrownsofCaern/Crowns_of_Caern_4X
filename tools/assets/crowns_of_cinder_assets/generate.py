"""AI image generation hook.

Generation is decoupled from the build: providers write raw images to
assets/source/generated/<id>.png and `build` post-processes any raw image it
finds (background removal, crop, resize, palette, outline, validation). So any
tool can feed the pipeline: run `generate` with a configured provider, or drop
images from another service into that folder by hand.
"""
from __future__ import annotations

import base64
import io
import json
import os
import urllib.request
from pathlib import Path

from PIL import Image


def build_prompt(spec: dict, style: dict) -> str:
    cat = style["categories"].get(spec.get("category", "object"), "")
    extra = spec.get("pose", "")
    return " ".join(p for p in (style["preamble"], cat, spec["prompt"] + ".", extra, style["constraints"]) if p).strip()


class Provider:
    name = "base"

    def available(self) -> tuple[bool, str]:
        raise NotImplementedError

    def generate(self, prompt: str) -> Image.Image:
        raise NotImplementedError


class OpenAIImages(Provider):
    """OpenAI Images API (gpt-image-1 by default). Needs OPENAI_API_KEY;
    REIGNEM_IMAGE_MODEL overrides the model."""
    name = "openai"
    url = "https://api.openai.com/v1/images/generations"

    def __init__(self) -> None:
        self.key = os.environ.get("OPENAI_API_KEY", "")
        self.model = os.environ.get("REIGNEM_IMAGE_MODEL", "gpt-image-1")

    def available(self) -> tuple[bool, str]:
        if not self.key:
            return False, "OPENAI_API_KEY is not set"
        return True, f"model {self.model}"

    def generate(self, prompt: str) -> Image.Image:
        body = json.dumps({"model": self.model, "prompt": prompt, "size": "1024x1024", "n": 1,
                           "background": "transparent", "output_format": "png"}).encode()
        req = urllib.request.Request(self.url, data=body, headers={
            "Authorization": f"Bearer {self.key}", "Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=300) as r:
            data = json.loads(r.read())
        return Image.open(io.BytesIO(base64.b64decode(data["data"][0]["b64_json"]))).convert("RGBA")


PROVIDERS = {"openai": OpenAIImages}


def run(specs_list: list[dict], style: dict, out_dir: Path, provider_name: str, only: set[str] | None,
        force: bool, log=print) -> int:
    prov = PROVIDERS[provider_name]()
    ok, why = prov.available()
    if not ok:
        log(f"provider '{provider_name}' unavailable: {why}")
        return 2
    out_dir.mkdir(parents=True, exist_ok=True)
    n = 0
    for s in specs_list:
        if only and s["id"] not in only:
            continue
        if not s.get("generate", True):
            continue
        dest = out_dir / f"{s['id']}.png"
        if dest.exists() and not force:
            continue
        log(f"generating {s['id']} ...")
        prov.generate(build_prompt(s, style)).save(dest)
        n += 1
    log(f"generated {n} images into {out_dir}")
    return 0
