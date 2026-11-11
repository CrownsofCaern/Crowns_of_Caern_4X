#!/usr/bin/env python3
"""Build the Crowns of Caern manual: a static, self-contained HTML site.

    python3 tools/manual/build_manual.py [--out export/manual] [--only home,faction-concord]

Sources
- docs/manual/pages/*.md: hand-written pages (lore, how to play, developer overview). Front matter sets
  the title, nav section and banner art; {{name}} lines insert generated blocks (see BLOCKS).
- docs/manual/data/*.json: hand-written lore that has no home in the game data (faction and hero bios).
- data/*.json and data/creatures/*.json: units, heroes, campaigns. These pages are generated, so the
  manual follows every balance or story change after a rebuild.
- assets/: artwork. Paintings are resized to JPEG and sprites copied as PNG into <out>/img. A campaign
  chapter without a briefing painting shows a labelled slot until the art lands in assets/campaign_art.json.
- docs/*.md and tools/assets/README.md: rendered unchanged as the developer section.

Only Pillow is needed (the asset pipeline already requires it). The output folder is git-ignored; open
<out>/index.html in a browser.
"""

from __future__ import annotations

import argparse
import html
import json
import os
import re
import shutil
import sys
from dataclasses import dataclass, field
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import mdlite  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
MANUAL = ROOT / "docs" / "manual"
GITHUB_BLOB = "https://github.com/CrownsofCaern/Crowns_of_Caern_4X/blob/main/"
TITLE = "Crowns of Caern"

FACTION_ORDER = ["concord", "hollow", "ashen", "thornwood", "forge", "frostmarch", "darkelf", "fishmen"]
CAMPAIGN_ORDER = ["last_light", "pale_inheritance", "unsealing", "briar_oath", "shuttered_halls", "ashwinter",
	"long_watch", "six_eyes", "drowned_oath"]
EXPANSION_FACTIONS = {"darkelf", "fishmen"}
TERRAIN_NAMES = {"grass": "Grassland", "infernal": "Cinder wastes", "swamp": "Swamp", "forest": "Forest",
	"rough": "Rocky highland", "snow": "Snowfield", "desert": "Desert", "dirt": "Dirt", "water": "Water"}
RESOURCE_ORDER = ["gold", "wood", "ore", "mercury", "sulfur", "crystal", "gems"]
ROLE_NAMES = {"infantry": "Infantry", "ranged": "Ranged", "cavalry": "Cavalry", "flyer": "Flyer",
	"caster": "Caster", "support": "Support", "brute": "Brute", "construct": "Construct"}
STAT_WORDS = {"attack": "attack", "defense": "defense", "speed": "speed", "initiative": "initiative", "morale": "morale", "damage": "damage"}
# Emblem cells in assets/emblems/factions_detailed.png (reading order in assets/emblems/README.md).
EMBLEM_CELLS = ["concord", "ashen", "hollow", "thornwood", "forge", "frostmarch", "darkelf", "fishmen"]

# Developer docs rendered into the site, in nav order: (source, slug, title).
DEV_DOCS = [
	("docs/manual/README.md", "dev-manual", "Editing this manual"),
	("docs/REPOSITORY_GUIDE.md", "dev-repository", "Repository guide"),
	("docs/DESIGN.md", "dev-design", "Design and architecture"),
	("docs/FACTIONS.md", "dev-factions", "Faction design and balance"),
	("docs/STORY.md", "dev-story", "Story bible"),
	("docs/ART_BIBLE.md", "dev-art-bible", "Art bible"),
	("tools/assets/README.md", "dev-asset-pipeline", "Asset pipeline"),
	("docs/MAP_EDITOR.md", "dev-map-editor", "Map editor"),
	("docs/GAMEPLAY_VARIETY_PLAN.md", "dev-variety", "Gameplay variety plan"),
	("docs/IOS.md", "dev-ios", "iOS export"),
]


def load(rel: str):
	with open(ROOT / rel, encoding="utf-8") as f:
		return json.load(f)


def esc(s) -> str:
	return html.escape(str(s), quote=True)


def res_path(p: str) -> str:
	return p[len("res://"):] if p.startswith("res://") else p


# --------------------------------------------------------------------------- images
class Images:
	"""Copies artwork into <out>/img once, resized for the web."""

	def __init__(self, out: Path):
		self.out = out / "img"
		self.out.mkdir(parents=True, exist_ok=True)
		self.done: dict[tuple, str] = {}

	def _name(self, rel: str, tag: str, ext: str) -> str:
		rel = res_path(rel)
		stem = re.sub(r"[^a-zA-Z0-9]+", "_", str(Path(rel).with_suffix(""))).strip("_").lower()
		stem = re.sub(r"^(assets|docs)_", "", stem)
		return "%s%s.%s" % (stem, tag, ext)

	def painting(self, rel: str, width: int = 1600) -> str | None:
		"""A large illustration: JPEG, at most `width` px wide."""
		key = ("p", rel, width)
		if key in self.done:
			return self.done[key]
		src = ROOT / res_path(rel)
		if not src.is_file():
			return None
		name = self._name(rel, "", "jpg")
		dst = self.out / name
		if not dst.exists() or dst.stat().st_mtime < src.stat().st_mtime:
			im = Image.open(src)
			has_alpha = im.mode in ("RGBA", "LA") or "transparency" in im.info
			if has_alpha:
				im = im.convert("RGBA")
				bg = Image.new("RGBA", im.size, (17, 12, 10, 255))
				bg.alpha_composite(im)
				im = bg
			im = im.convert("RGB")
			if im.width > width:
				im = im.resize((width, round(im.height * width / im.width)), Image.LANCZOS)
			im.save(dst, "JPEG", quality=84, optimize=True, progressive=True)
		self.done[key] = "img/" + name
		return self.done[key]

	def sprite(self, rel: str) -> str | None:
		"""Pixel art: copied as is, scaled up in CSS with image-rendering: pixelated."""
		key = ("s", rel)
		if key in self.done:
			return self.done[key]
		src = ROOT / res_path(rel)
		if not src.is_file():
			return None
		name = self._name(rel, "", "png")
		dst = self.out / name
		if not dst.exists() or dst.stat().st_mtime < src.stat().st_mtime:
			shutil.copyfile(src, dst)
		self.done[key] = "img/" + name
		return self.done[key]

	def png(self, rel: str, width: int) -> str | None:
		"""A transparent picture (emblems, wordmark, portraits) downscaled as PNG."""
		key = ("t", rel, width)
		if key in self.done:
			return self.done[key]
		src = ROOT / res_path(rel)
		if not src.is_file():
			return None
		name = self._name(rel, "_%d" % width, "png")
		dst = self.out / name
		if not dst.exists() or dst.stat().st_mtime < src.stat().st_mtime:
			im = Image.open(src).convert("RGBA")
			if im.width > width:
				im = im.resize((width, round(im.height * width / im.width)), Image.LANCZOS)
			im.save(dst, "PNG", optimize=True)
		self.done[key] = "img/" + name
		return self.done[key]

	def emblem(self, faction: str, width: int = 256) -> str | None:
		key = ("e", faction, width)
		if key in self.done:
			return self.done[key]
		tres = ROOT / "assets" / "emblems" / ("%s.tres" % faction)
		sheet = ROOT / "assets" / "emblems" / "factions_detailed.png"
		if not tres.is_file() or not sheet.is_file():
			return None
		m = re.search(r"region = Rect2\(([\d.]+), ([\d.]+), ([\d.]+), ([\d.]+)\)", tres.read_text())
		if not m:
			return None
		x, y, w, h = (float(v) for v in m.groups())
		name = "emblem_%s_%d.png" % (faction, width)
		dst = self.out / name
		if not dst.exists() or dst.stat().st_mtime < sheet.stat().st_mtime:
			im = Image.open(sheet).convert("RGBA").crop((round(x), round(y), round(x + w), round(y + h)))
			im = _key_out_dark(im)
			im = im.resize((width, width), Image.LANCZOS)
			im.save(dst, "PNG", optimize=True)
		self.done[key] = "img/" + name
		return self.done[key]

	def town(self, faction: str, manifest: dict, width: int = 1600) -> str | None:
		"""The faction's town painting with every building at its final stage."""
		key = ("town", faction, width)
		if key in self.done:
			return self.done[key]
		scene = manifest.get("factions", {}).get(faction)
		if not scene:
			return None
		bg_path = ROOT / res_path(scene["background"])
		if not bg_path.is_file():
			return None
		name = "town_%s.jpg" % faction
		dst = self.out / name
		if not dst.exists():
			bg = Image.open(bg_path).convert("RGBA")
			scale = bg.width / scene["size"][0]
			for slot in sorted(scene["slots"], key=lambda s: s["at"][1]):
				variant = None
				for v in reversed(slot["variants"]):
					if v in scene.get("assets", {}) and (ROOT / res_path(scene["assets"][v])).is_file():
						variant = v
						break
				if variant is None:
					continue
				tex = Image.open(ROOT / res_path(scene["assets"][variant])).convert("RGBA")
				lim_w, lim_h = slot["size"][0] * scale, slot["size"][1] * scale
				f = min(lim_w / tex.width, lim_h / tex.height)
				tw, th = max(1, round(tex.width * f)), max(1, round(tex.height * f))
				tex = tex.resize((tw, th), Image.LANCZOS)
				fx, fy = slot["at"][0] * scale, slot["at"][1] * scale
				bg.alpha_composite(tex, (round(fx - tw / 2), round(fy - th)))
			im = bg.convert("RGB")
			if im.width > width:
				im = im.resize((width, round(im.height * width / im.width)), Image.LANCZOS)
			im.save(dst, "JPEG", quality=84, optimize=True, progressive=True)
		self.done[key] = "img/" + name
		return self.done[key]


def _key_out_dark(im: Image.Image) -> Image.Image:
	"""The emblem sheet has a near-black ground; fade it to transparent from the cell's edge colour."""
	px = im.load()
	w, h = im.size
	corner = px[2, 2]
	cr, cg, cb = corner[:3]
	out = im.copy()
	op = out.load()
	for yy in range(h):
		for xx in range(w):
			r, g, b, a = px[xx, yy]
			d = abs(r - cr) + abs(g - cg) + abs(b - cb)
			if d < 18:
				op[xx, yy] = (r, g, b, 0)
			elif d < 40:
				op[xx, yy] = (r, g, b, int(a * (d - 18) / 22))
	return out


# --------------------------------------------------------------------------- game data
@dataclass
class Game:
	factions: dict
	creatures: dict
	abilities: dict
	classes: dict
	campaigns: dict
	art: list
	towns: dict
	resources: dict
	skills: dict
	spells: dict
	artifacts: dict
	hero_bios: dict
	faction_lore: dict
	heroes: dict = field(default_factory=dict)

	@staticmethod
	def load() -> "Game":
		creatures: dict = {}
		for p in sorted((ROOT / "data" / "creatures").glob("*.json")):
			creatures.update(json.loads(p.read_text())["creatures"])
		g = Game(
			factions=load("data/factions.json")["factions"],
			creatures=creatures,
			abilities=load("data/abilities.json")["abilities"],
			classes=load("data/hero_classes.json")["classes"],
			campaigns=load("data/campaigns.json")["campaigns"],
			art=load("assets/campaign_art.json")["illustrations"],
			towns=load("assets/towns/manifest.json"),
			resources=load("data/resources.json").get("resources", {}),
			skills=load("data/skills.json")["skills"],
			spells=load("data/spells.json").get("spells", {}),
			artifacts=load("data/artifacts.json"),
			hero_bios=_read_json(MANUAL / "data" / "heroes.json"),
			faction_lore=_read_json(MANUAL / "data" / "factions.json"),
		)
		g._collect_heroes()
		return g

	def _collect_heroes(self) -> None:
		"""Named campaign heroes: name and class from each campaign's cast, first appearance wins."""
		portrait_dir = ROOT / "assets" / "hero_portraits" / "campaign"
		home = {}
		for cid in CAMPAIGN_ORDER:
			for hid in self.campaigns.get(cid, {}).get("heroes", []):
				home.setdefault(hid, cid)
		for cid in CAMPAIGN_ORDER:
			camp = self.campaigns.get(cid)
			if not camp:
				continue
			for ch in camp["chapters"]:
				for cast in ch.get("cast", []):
					hid = cast.get("id", "")
					if not hid or hid in self.heroes or not cast.get("name") or not cast.get("class"):
						continue
					if not (portrait_dir / ("%s.png" % hid)).is_file():
						continue
					klass = self.classes.get(cast["class"], {})
					self.heroes[hid] = {"id": hid, "name": cast["name"], "class": cast["class"],
						"faction": klass.get("faction", camp["faction"]), "campaign": home.get(hid, cid)}

	def roster(self, faction: str) -> list[tuple[dict, dict | None]]:
		"""(base, upgrade) pairs ordered by tier."""
		bases = [(k, v) for k, v in self.creatures.items() if v.get("faction") == faction and not v.get("upgrade_of")]
		bases.sort(key=lambda kv: (kv[1].get("tier", 0), kv[0]))
		out = []
		for k, v in bases:
			v = dict(v, id=k)
			up = self.creatures.get(v.get("upgrade", ""))
			out.append((v, dict(up, id=v["upgrade"]) if up else None))
		return out

	def briefing_art(self, campaign: str, chapter: str) -> str | None:
		for it in self.art:
			if it["campaign"] == campaign and it["chapter"] == chapter and it["usage"] == "briefing":
				return it["path"]
		return None

	def journey_art(self, campaign: str) -> str | None:
		for it in self.art:
			if it["campaign"] == campaign and it["usage"] == "journey":
				return it["path"]
		p = "assets/illustrations/journeys/%s.png" % campaign
		return p if (ROOT / p).is_file() else None


def _read_json(path: Path) -> dict:
	if not path.is_file():
		return {}
	return json.loads(path.read_text(encoding="utf-8"))


# --------------------------------------------------------------------------- pages
@dataclass
class Page:
	slug: str
	title: str
	section: str
	order: float
	body: str = ""
	eyebrow: str = ""
	lede: str = ""
	banner: str | None = None   # image url (already in img/)
	crest: str | None = None
	nav_icon: str | None = None
	nav_title: str | None = None
	toc: bool = False
	description: str = ""


SECTIONS = [
	("begin", "Begin"),
	("world", "The World"),
	("peoples", "The Peoples"),
	("heroes", "Heroes"),
	("campaigns", "Campaigns"),
	("play", "How to Play"),
	("dev", "For Developers"),
]


class Site:
	def __init__(self, out: Path):
		self.out = out
		self.img = Images(out)
		self.game = Game.load()
		self.pages: dict[str, Page] = {}
		self.dev_slugs = {Path(src).resolve(): slug for src, slug, _ in [(str(ROOT / s), sl, t) for s, sl, t in DEV_DOCS]}

	# ----------------------------------------------------------- helpers
	def add(self, page: Page) -> None:
		self.pages[page.slug] = page

	def link_hook_for(self, source: Path | None):
		def hook(url: str) -> str:
			if url.startswith(("http://", "https://", "#", "mailto:")):
				return url
			if url.startswith("page:"):
				return url[5:] + ".html"
			if source is None:
				return url
			target, _, anchor = url.partition("#")
			resolved = (source.parent / target).resolve()
			if resolved in self.dev_slugs:
				return self.dev_slugs[resolved] + ".html" + ("#" + anchor if anchor else "")
			try:
				rel = resolved.relative_to(ROOT)
			except ValueError:
				return url
			return GITHUB_BLOB + str(rel).replace(os.sep, "/") + ("#" + anchor if anchor else "")
		return hook

	def image_hook_for(self, source: Path | None):
		def hook(src: str) -> str:
			if src.startswith(("http://", "https://", "data:", "img/")):
				return src
			path = (source.parent / src).resolve() if source is not None and not src.startswith(("assets/", "docs/", "res://")) else (ROOT / res_path(src)).resolve()
			try:
				rel = str(path.relative_to(ROOT))
			except ValueError:
				return src
			url = self.img.painting(rel) if path.suffix.lower() in (".png", ".jpg", ".jpeg") and _is_large(path) else self.img.sprite(rel)
			return url or src
		return hook

	def md(self, text: str, source: Path | None = None) -> tuple[str, list]:
		text = self.expand_blocks(text)
		return mdlite.render(text, self.link_hook_for(source), self.image_hook_for(source))

	def expand_blocks(self, text: str) -> str:
		def repl(m):
			name = m.group(1)
			fn = getattr(self, "block_" + name, None)
			if fn is None:
				raise SystemExit("Unknown manual block {{%s}}" % name)
			return "\n" + fn() + "\n"
		return re.sub(r"^\{\{(\w+)\}\}\s*$", repl, text, flags=re.M)

	def plate(self, url: str | None, caption: str = "", alt: str = "") -> str:
		if not url:
			return ""
		cap = "<figcaption>%s</figcaption>" % caption if caption else ""
		return '<figure class="plate"><img src="%s" alt="%s" loading="lazy">%s</figure>' % (esc(url), esc(alt or caption), cap)

	def slot(self, title: str, hint: str) -> str:
		return '<div class="slot" role="img" aria-label="%s"><span class="slot-title">%s</span><span>Artwork to come</span><code>%s</code></div>' % (
			esc(title), esc(title), esc(hint))

	# ----------------------------------------------------------- hand-written pages
	def load_markdown_pages(self) -> None:
		for path in sorted((MANUAL / "pages").glob("*.md")):
			meta, body = _front_matter(path.read_text(encoding="utf-8"))
			html_body, heads = self.md(body, path)
			banner = None
			if meta.get("banner"):
				banner = self.img.painting(meta["banner"])
			page = Page(
				slug=meta.get("slug", path.stem),
				title=meta.get("title", path.stem),
				section=meta.get("section", "play"),
				order=float(meta.get("order", 50)),
				eyebrow=meta.get("eyebrow", ""),
				lede=meta.get("lede", ""),
				banner=banner,
				nav_title=meta.get("nav"),
				toc=meta.get("toc", "no") == "yes",
				description=meta.get("description", meta.get("lede", "")),
			)
			if page.toc:
				html_body = _toc(heads) + html_body
			page.body = '<div class="prose">%s</div>' % html_body if meta.get("wide", "no") != "yes" else html_body
			self.add(page)

	# ----------------------------------------------------------- blocks for {{...}}
	def block_faction_crests(self) -> str:
		items = []
		for fid in FACTION_ORDER:
			f = self.game.factions[fid]
			items.append('<a href="faction-%s.html"><img src="%s" alt="">%s</a>' % (fid, esc(self.img.emblem(fid, 256)), esc(f["name"])))
		return '<div class="crests">%s</div>' % "".join(items)

	def block_campaign_cards(self) -> str:
		return self._campaign_cards()

	def block_world_map(self) -> str:
		url = self.img.painting("assets/source/batches/world-atlas-002/source.png")
		return self.plate(url, "The known world. The Frostmarch under the glacier in the north, the Forge's mountain spine in the west, the Concord Marches in the middle, Sallowmere's fens in the south and the Wound burning in the east.", "Painted map of the world")

	def block_peoples_cards(self) -> str:
		cards = []
		for fid in FACTION_ORDER:
			f = self.game.factions[fid]
			lore = self.game.faction_lore.get(fid, {})
			cards.append(self._card("faction-%s.html" % fid, self.img.town(fid, self.game.towns) or "", f["name"],
				"Expansion" if fid in EXPANSION_FACTIONS else lore.get("people", ""), lore.get("tagline", f.get("roster", ""))))
		return '<div class="grid">%s</div>' % "".join(cards)

	def block_play_cards(self) -> str:
		pages = sorted((p for p in self.pages.values() if p.section == "play"), key=lambda p: p.order)
		return '<ul>%s</ul>' % "".join('<li><a href="%s.html">%s</a>: %s</li>' % (p.slug, esc(p.title), esc(p.description)) for p in pages)

	def block_battle_orders(self) -> str:
		t = _read_json(ROOT / "data" / "tactics.json")
		rows = []
		for group, label in (("stances", "Stance"), ("focus", "Focus")):
			for k, v in t.get(group, {}).items():
				rows.append("<tr><td>%s</td><td><strong>%s</strong></td><td class=\"num\">%s</td><td>%s</td></tr>" % (
					label, esc(v["name"]), v.get("min_level", 1), esc(v.get("desc", ""))))
		return '<div class="table-wrap"><table><thead><tr><th>Order</th><th>Name</th><th class="num">From level</th><th>Effect</th></tr></thead><tbody>%s</tbody></table></div>' % "".join(rows)

	def block_hero_classes(self) -> str:
		out = []
		for fid in FACTION_ORDER:
			classes = [(k, v) for k, v in self.game.classes.items() if v.get("faction") == fid]
			if not classes:
				continue
			cards = []
			for k, c in classes:
				portrait = self.img.png("assets/hero_portraits/classes/%s.png" % k, 256)
				trait, art = c.get("trait", {}), c.get("art", {})
				prim = "Attack %s &middot; Defense %s &middot; Power %s &middot; Knowledge %s" % (c.get("attack", 0), c.get("defense", 0), c.get("power", 0), c.get("knowledge", 0))
				cards.append('<div class="hero"><img src="%s" alt="" loading="lazy"><div><span class="role">%s</span><h4>%s</h4><span class="epithet">%s</span><p><strong>%s.</strong> %s</p><p><strong>%s.</strong> %s</p><p style="font-size:.8rem">Starts with %s</p></div></div>' % (
					esc(portrait or ""), "Hero class", esc(c["name"]), esc(_sentence(c.get("text", "")) if c.get("text", "")[:1].isupper() else ""),
					esc(trait.get("name", "")), esc(trait.get("text", "")), esc(art.get("name", "")), esc(art.get("text", "")), prim))
			out.append('<h3 id="classes-%s"><a href="faction-%s.html">%s</a></h3><div class="hero-row">%s</div>' % (fid, fid, esc(self.game.factions[fid]["name"]), "".join(cards)))
		return "".join(out)

	def block_skills_table(self) -> str:
		groups = {}
		for k, v in self.game.skills.items():
			groups.setdefault(v.get("group", "other"), []).append((k, v))
		labels = [("command", "Command"), ("war", "War"), ("travel", "Travel"), ("arcane", "Arcane"), ("rule", "Rule"), ("faction", "People skills"), ("class", "Class skills")]
		out = []
		for g, label in labels:
			items = sorted(groups.get(g, []), key=lambda kv: kv[1]["name"])
			if not items:
				continue
			rows = []
			for k, v in items:
				lv = v.get("levels", [])
				cells = "".join("<td>%s</td>" % esc(lv[i]["text"]) if i < len(lv) else "<td></td>" for i in range(3))
				who = ""
				if g == "faction":
					fid = k.replace("faction_", "")
					who = self.game.factions.get(fid, {}).get("name", "")
				elif g == "class":
					who = self.game.classes.get(k.replace("class_", ""), {}).get("name", "")
				name = "<strong>%s</strong>%s" % (esc(v["name"]), "<br><small>%s</small>" % esc(who) if who else "")
				rows.append("<tr><td>%s</td>%s</tr>" % (name, cells))
			out.append('<h3 id="skills-%s">%s</h3><div class="table-wrap"><table><thead><tr><th>Skill</th><th>Basic</th><th>Advanced</th><th>Expert</th></tr></thead><tbody>%s</tbody></table></div>' % (g, label, "".join(rows)))
		return "".join(out)

	def block_spells_table(self) -> str:
		magic = _read_json(ROOT / "data" / "spells.json")
		by_art = {}
		for kind, sp in magic.get("class_by_art", {}).items():
			by_art.setdefault(sp, []).append(kind)
		rows = []
		for k, v in magic.get("spells", {}).items():
			src = "Known by classes whose art is %s, from level %s" % (", ".join(sorted(by_art.get(k, []))), magic.get("class_level", 2)) if v.get("source") == "class" else "Learned at a shrine on the map"
			rows.append("<tr><td><strong>%s</strong></td><td class=\"num\">%s</td><td>%s</td><td>%s</td></tr>" % (esc(v["name"]), v.get("cost", ""), esc(v.get("description", "")), esc(src)))
		rules = _read_json(ROOT / "data" / "game_rules.json")
		intro = "<p class=\"prose\">A hero has %s mana plus %s for every point of Knowledge, and regains %s each day.</p>" % (rules.get("mana_base", 10), rules.get("mana_per_knowledge", 2), rules.get("mana_daily_regen", 1))
		return intro + '<div class="table-wrap"><table><thead><tr><th>Spell</th><th class="num">Mana</th><th>Effect</th><th>How to learn it</th></tr></thead><tbody>%s</tbody></table></div>' % "".join(rows)

	def block_equipment_tables(self) -> str:
		a = self.game.artifacts
		slot_names = {"weapon": "Weapons", "helm": "Helms", "armor": "Armour", "shield": "Shields", "boots": "Boots", "charm": "Charms", "banner": "Banners"}
		rank = {"minor": 0, "major": 1, "relic": 2}
		set_of = {}
		for sid, st in a.get("sets", {}).items():
			for piece in st["pieces"]:
				set_of[piece] = st["name"]
		out = []
		for slot in a.get("slots", []):
			items = sorted(((k, v) for k, v in a["artifacts"].items() if v.get("slot") == slot), key=lambda kv: (rank.get(kv[1].get("rarity"), 9), kv[1].get("value", 0), kv[1]["name"]))
			if not items:
				continue
			rows = []
			for k, v in items:
				icon = self.img.sprite("assets/artifacts/%s.png" % k)
				img = '<img src="%s" alt="" style="width:2.5rem;height:2.5rem;object-fit:contain;vertical-align:middle;margin-right:.5rem">' % esc(icon) if icon else ""
				extra = "<br><small>Part of the %s</small>" % esc(set_of[k]) if k in set_of else ""
				rows.append("<tr><td>%s<strong>%s</strong>%s</td><td>%s</td><td>%s</td></tr>" % (img, esc(v["name"]), extra, esc(v.get("rarity", "").title()), esc(v.get("text", ""))))
			out.append('<h2 id="slot-%s">%s</h2><div class="table-wrap"><table><thead><tr><th>Piece</th><th>Rarity</th><th>Effect</th></tr></thead><tbody>%s</tbody></table></div>' % (slot, slot_names.get(slot, slot.title()), "".join(rows)))
		sets = []
		for sid, st in a.get("sets", {}).items():
			pieces = ", ".join(a["artifacts"].get(p, {}).get("name", p) for p in st["pieces"])
			bon = "".join("<li>%s</li>" % esc(b.get("text", "")) for b in st.get("bonuses", []))
			sets.append("<h3>%s</h3><p>%s</p><ul>%s</ul>" % (esc(st["name"]), esc(pieces), bon))
		out.append('<h2 id="sets">Sets</h2><div class="prose">%s</div>' % "".join(sets))
		return "".join(out)

	# ----------------------------------------------------------- factions
	def _card(self, href, art, title, meta, text, crest=False) -> str:
		art_div = '<div class="art" style="background-image:url(\'%s\')"></div>' % esc(art) if art else ""
		return '<a class="card%s" href="%s">%s<div class="body"><span class="meta">%s</span><span class="title">%s</span><span class="text">%s</span></div></a>' % (
			" crest" if crest else "", esc(href), art_div, esc(meta), esc(title), esc(text))

	def ability_tags(self, unit: dict, previous: dict | None) -> str:
		before = {a["id"] for a in (previous or {}).get("abilities", [])}
		tags = []
		for ab in unit.get("abilities", []):
			info = self.game.abilities.get(ab["id"], {})
			name = info.get("name", ab["id"].replace("_", " ").title())
			detail = _ability_params(ab)
			title = info.get("desc", "")
			if detail:
				title = "%s (%s)" % (title, detail)
			new = previous is not None and ab["id"] not in before
			tags.append('<span class="tag%s" title="%s">%s%s</span>' % (" new" if new else "", esc(title), esc(name), " &#9733;" if new else ""))
		return '<div class="tags">%s</div>' % "".join(tags) if tags else ""

	def unit_html(self, u: dict, base: dict | None = None) -> str:
		sprite = self.img.sprite("assets/build/creature/creature_%s.png" % u["id"])
		img = '<img src="%s" alt="%s" loading="lazy">' % (esc(sprite), esc(u["name"])) if sprite else ""
		dmg = u.get("damage", [0, 0])
		stats = [("HP", u.get("hp")), ("ATK", u.get("attack")), ("DEF", u.get("defense")),
			("DMG", "%s&ndash;%s" % (dmg[0], dmg[1]) if dmg[0] != dmg[1] else dmg[0]), ("SPD", u.get("speed")),
			("INIT", u.get("initiative")), ("GROWTH", "%s/wk" % u.get("growth"))]
		stat_html = "".join("<li><b>%s</b>%s</li>" % (k, v) for k, v in stats)
		terrain = []
		for t, mods in sorted(u.get("terrain", {}).items()):
			parts = ["%+d %s" % (v, STAT_WORDS.get(k, k)) for k, v in mods.items() if isinstance(v, (int, float))]
			terrain.append("%s %s" % (TERRAIN_NAMES.get(t, t), " ".join(parts)))
		role = ROLE_NAMES.get(u.get("role", ""), u.get("role", "").title())
		extra = (" &middot; " + esc(", ".join(terrain))) if terrain else ""
		return (
			'<div class="unit%s"><div class="sprite">%s</div><div><span class="role">%s%s</span><h4>%s</h4>'
			'<p class="desc">%s</p><ul class="stats">%s</ul><div class="cost">%s</div>%s</div></div>'
		) % (" up" if base else "", img, esc(role), extra, esc(u["name"]), esc(u.get("desc", "")), stat_html,
			_cost(u.get("cost", {})), self.ability_tags(u, base))

	def faction_pages(self) -> None:
		for order, fid in enumerate(FACTION_ORDER):
			f = self.game.factions[fid]
			lore = self.game.faction_lore.get(fid, {})
			roster = self.game.roster(fid)
			parts: list[str] = []
			intro_md = lore.get("intro", "")
			facts = [
				("Native ground", ", ".join(TERRAIN_NAMES.get(t, t) for t in f.get("native_terrain", []))),
				("Hostile ground", ", ".join(TERRAIN_NAMES.get(t, t) for t in f.get("hostile_terrain", []))),
				("Strongest", {"early": "Early (weeks 1-2)", "steady": "Throughout", "late": "Late (week 3 on)"}.get(f.get("economy", {}).get("curve", ""), "")),
				("Rare resources", ", ".join(r.title() for r in f.get("economy", {}).get("key_resources", []))),
			]
			parts.append('<dl class="facts">%s</dl>' % "".join("<div><dt>%s</dt><dd>%s</dd></div>" % (esc(k), esc(v)) for k, v in facts if v))
			if intro_md:
				parts.append('<div class="prose">%s</div>' % self.md(intro_md)[0])
			if lore.get("plays"):
				parts.append('<h2 id="how-it-fights">How it fights</h2><div class="prose">%s</div>' % self.md(lore["plays"])[0])

			# heroes
			classes = [(k, v) for k, v in self.game.classes.items() if v.get("faction") == fid]
			named = [h for h in self.game.heroes.values() if h["faction"] == fid]
			if named:
				parts.append('<h2 id="heroes">Heroes of the campaign</h2><div class="hero-row">%s</div>' % "".join(self.hero_card(h) for h in named))
			if classes:
				rows = []
				for k, c in classes:
					portrait = self.img.png("assets/hero_portraits/classes/%s.png" % k, 256)
					trait, art = c.get("trait", {}), c.get("art", {})
					rows.append('<div class="hero"><img src="%s" alt="" loading="lazy"><div><span class="role">Hero class</span><h4>%s</h4><p><strong>%s.</strong> %s</p><p><strong>%s.</strong> %s</p></div></div>' % (
						esc(portrait or ""), esc(c["name"]), esc(trait.get("name", "")), esc(trait.get("text", "")), esc(art.get("name", "")), esc(art.get("text", ""))))
				parts.append('<h2 id="classes">Hero classes</h2><div class="hero-row">%s</div>' % "".join(rows))

			# roster
			tiers = []
			for base, up in roster:
				cells = self.unit_html(base) + (self.unit_html(up, base) if up else "<div></div>")
				tiers.append('<div class="tier"><div class="tier-no">%s<small>Tier</small></div>%s</div>' % (_roman(base.get("tier", 0)), cells))
			parts.append('<h2 id="roster">The roster</h2><p class="prose">Each tier has a base creature (left) and its upgrade (right). Abilities marked &#9733; are what the upgrade adds. Hover an ability for its rule. Growth is the number a dwelling adds each week.</p>%s' % "".join(tiers))

			used = []
			seen = set()
			for base, up in roster:
				for u in (base, up):
					for ab in (u or {}).get("abilities", []):
						if ab["id"] not in seen:
							seen.add(ab["id"])
							used.append(ab["id"])
			gl = "".join("<dt>%s</dt><dd>%s</dd>" % (esc(self.game.abilities.get(a, {}).get("name", a)), esc(self.game.abilities.get(a, {}).get("desc", ""))) for a in used)
			parts.append('<h2 id="abilities">Abilities in this roster</h2><dl class="glossary">%s</dl>' % gl)

			town = self.img.town(fid, self.game.towns)
			self.add(Page(slug="faction-%s" % fid, title=f["name"], section="peoples", order=order,
				eyebrow=("Expansion people" if fid in EXPANSION_FACTIONS else "Playable people") + (" &middot; " + lore["people"] if lore.get("people") else ""),
				lede=lore.get("tagline", f.get("roster", "")), banner=town, crest=self.img.emblem(fid, 256),
				nav_icon=self.img.emblem(fid, 64), nav_title=f["name"].replace("The ", ""), body="\n".join(parts),
				description=f.get("roster", "")))

	def hero_card(self, h: dict) -> str:
		portrait = self.img.png("assets/hero_portraits/campaign/%s.png" % h["id"], 256)
		bio = self.game.hero_bios.get(h["id"], {})
		klass = self.game.classes.get(h["class"], {}).get("name", h["class"])
		title = bio.get("title", "")
		camp = self.game.campaigns.get(h["campaign"], {})
		text = bio.get("bio", "")
		link = '<p><a href="campaign-%s.html">%s</a></p>' % (h["campaign"], esc(camp.get("name", ""))) if camp else ""
		epithet = '<span class="epithet">%s</span>' % esc(title) if title else ""
		return '<div class="hero"><img src="%s" alt="Portrait of %s" loading="lazy"><div><span class="role">%s</span><h4>%s</h4>%s%s%s</div></div>' % (
			esc(portrait or ""), esc(h["name"]), esc(klass), esc(h["name"]), epithet, "<p>%s</p>" % esc(text) if text else "", link)

	def bestiary_page(self) -> None:
		wild = sorted(((k, v) for k, v in self.game.creatures.items() if v.get("faction") == "wilds"), key=lambda kv: (kv[1].get("tier", 0), kv[1]["name"]))
		rows = []
		by_tier: dict[int, list] = {}
		for k, v in wild:
			by_tier.setdefault(v.get("tier", 0), []).append(dict(v, id=k))
		for t in sorted(by_tier):
			units = by_tier[t]
			cells = "".join(self.unit_html(u) for u in units)
			rows.append('<h3 id="tier-%d">Tier %s</h3><div class="grid" style="grid-template-columns:repeat(auto-fill,minmax(min(100%%,22rem),1fr))">%s</div>' % (t, _roman(t), cells))
		intro = ("<div class=\"prose\"><p>Not everything on the map answers to a crown. The wilds are the creatures that guard mines, "
			"treasure, passes and shrines: beasts twisted by the land, the restless dead of forgotten wars and things older "
			"than any people. They have no towns and no upgrades, and they fight hardest on their own ground.</p>"
			"<p>Hover over a guard on the adventure map to see how many there are; the forecast shows your odds before you attack. "
			"A resource pile next to a guard cannot be claimed until the guard is beaten.</p></div>")
		self.add(Page(slug="bestiary", title="Bestiary of the Wilds", section="peoples", order=20, eyebrow="Creatures of no faction",
			lede="Beasts, revenants and older things that guard the roads between the crowns.",
			banner=self.img.painting("assets/battlefields/swamp_blackfen.png"), body=intro + "".join(rows), nav_title="Bestiary of the Wilds",
			description="Every wild creature that guards the map, with stats and abilities."))

	# ----------------------------------------------------------- campaigns
	def _campaign_cards(self) -> str:
		cards = []
		for cid in CAMPAIGN_ORDER:
			c = self.game.campaigns.get(cid)
			if not c:
				continue
			art = self.game.journey_art(cid) or self.game.briefing_art(cid, c["chapters"][0]["id"])
			fac = self.game.factions.get(c["faction"], {}).get("name", "")
			meta = "%s &middot; %d chapters" % (fac, len(c["chapters"]))
			cards.append(self._card("campaign-%s.html" % cid, self.img.painting(art) if art else "", c["name"], html.unescape(meta), _strip_meta_text(c["text"])))
		return '<div class="grid">%s</div>' % "".join(cards)

	def campaign_pages(self) -> None:
		for order, cid in enumerate(CAMPAIGN_ORDER):
			c = self.game.campaigns.get(cid)
			if not c:
				continue
			fac = self.game.factions.get(c["faction"], {})
			parts = []
			heroes = [self.game.heroes[h] for h in c.get("heroes", []) if h in self.game.heroes]
			if heroes:
				parts.append('<h2 id="cast">The cast</h2><div class="hero-row">%s</div>' % "".join(self.hero_card(h) for h in heroes))
			parts.append('<h2 id="chapters">Chapters</h2><p class="prose">Briefings are given as the game shows them. What happens at the end of each chapter is hidden under <em>Aftermath</em>, so you can read ahead without spoiling the story.</p>')
			for n, ch in enumerate(c["chapters"], 1):
				art = self.game.briefing_art(cid, ch["id"])
				art_html = '<img src="%s" alt="%s" loading="lazy">' % (esc(self.img.painting(art)), esc(ch["name"])) if art else self.slot(
					"Chapter %d" % n, "assets/source/generated/campaign_%s_%s_briefing.png" % (cid, ch["id"]))
				badges = []
				if ch.get("max_tier"):
					badges.append('<span class="badge">Creatures up to tier %d</span>' % ch["max_tier"])
				if ch.get("level_cap"):
					badges.append('<span class="badge">Hero level cap %d</span>' % ch["level_cap"])
				if ch.get("ai", {}).get("passive"):
					badges.append('<span class="badge">Tutorial pace</span>')
				players = [p for p in (ch.get("setup", {}) or {}).get("players", []) if isinstance(p, dict)]
				if players:
					my_team = players[0].get("team")
					enemies = [p for p in players[1:] if p.get("type") == "computer" and (my_team is None or p.get("team") != my_team)]
					allies = [p for p in players[1:] if my_team is not None and p.get("team") == my_team]
					if len(enemies) >= 2:
						badges.append('<span class="badge red">%d enemies</span>' % len(enemies))
					if allies:
						badges.append('<span class="badge">With an ally</span>')
				intro = "".join("<p>%s</p>" % esc(p.strip()) for p in ch.get("intro", "").split("\n\n") if p.strip())
				outro = "".join("<p>%s</p>" % esc(p.strip()) for p in ch.get("outro", "").split("\n\n") if p.strip())
				after = '<details><summary>Aftermath (spoiler)</summary><div>%s</div></details>' % outro if outro else ""
				parts.append(
					'<section class="chapter" id="%s"><div class="chapter-art">%s</div><div><span class="num">Chapter %s</span><h3>%s</h3>'
					'<div class="badges">%s</div><p class="line">%s</p><details open class="briefing"><summary>Briefing</summary><div>%s</div></details>%s</div></section>' % (
						esc(ch["id"]), art_html, _roman(n), esc(ch["name"]), "".join(badges), esc(ch.get("text", "")), intro, after))
			journey = self.game.journey_art(cid)
			banner = self.img.painting(journey or self.game.briefing_art(cid, c["chapters"][0]["id"]) or "") if (journey or self.game.briefing_art(cid, c["chapters"][0]["id"])) else None
			self.add(Page(slug="campaign-%s" % cid, title=c["name"], section="campaigns", order=order + 1,
				eyebrow="%s campaign%s" % (fac.get("adjective", ""), " &middot; Expansion" if c["faction"] in EXPANSION_FACTIONS else ""),
				lede=_strip_meta_text(c["text"]), banner=banner, crest=self.img.emblem(c["faction"], 256),
				nav_icon=self.img.emblem(c["faction"], 64), body="\n".join(parts), description=_strip_meta_text(c["text"])))
		self.add(Page(slug="campaigns", title="Campaigns", section="campaigns", order=0, eyebrow="One war, six sides",
			lede="Six campaigns tell the Year of the Red Sky from every side of the war. Three more follow the year after.",
			banner=self.img.painting("assets/menus/menu_campaign.png"), nav_title="All campaigns",
			body='<div class="prose"><p>The six main campaigns are one war seen from six sides. They share battles: the Burning Ford, the Iron Pass and Saint Orrin\'s Rest are fought from both banks, and each side may be wrong about the other\'s reasons. All campaigns are open from the start, and you can play them in any order. Each runs ten chapters; creatures unlock by tier as the story goes on, and the last two chapters field the full roster.</p></div>' + self._campaign_cards(),
			description="All campaigns with every chapter briefing."))

	# ----------------------------------------------------------- developer docs
	def dev_pages(self) -> None:
		for order, (src, slug, title) in enumerate(DEV_DOCS):
			path = ROOT / src
			if not path.is_file():
				continue
			text = path.read_text(encoding="utf-8")
			text = re.sub(r"\A# [^\n]*\n", "", text)  # the banner shows the title
			body, heads = self.md(text, path)
			src_link = '<p class="prose" style="font-size:.85rem;color:var(--parchment-dim)">Rendered from <a href="%s%s">%s</a>. Edit that file, not this page.</p>' % (GITHUB_BLOB, src, src)
			self.add(Page(slug=slug, title=title, section="dev", order=order + 10, eyebrow="For developers",
				body=src_link + _toc([h for h in heads if h[0] == 2]) + '<div class="prose" style="max-width:52rem">%s</div>' % body,
				description="Rendered from %s." % src))

	# ----------------------------------------------------------- output
	def nav_html(self, current: str) -> str:
		groups = []
		for key, label in SECTIONS:
			pages = sorted((p for p in self.pages.values() if p.section == key), key=lambda p: (p.order, p.title))
			if not pages:
				continue
			items = []
			for p in pages:
				icon = '<img src="%s" alt="">' % esc(p.nav_icon) if p.nav_icon else ""
				cur = ' aria-current="page"' if p.slug == current else ""
				items.append('<li><a href="%s.html"%s>%s<span>%s</span></a></li>' % (p.slug, cur, icon, esc(p.nav_title or p.title)))
			groups.append("<div><h2>%s</h2><ul>%s</ul></div>" % (esc(label), "".join(items)))
		return "<nav aria-label=\"Manual\">%s</nav>" % "".join(groups)

	def broken_links(self) -> list[tuple[str, str]]:
		"""Relative links and images in the written pages that point at nothing."""
		out = []
		for f in sorted(self.out.glob("*.html")):
			for target in _links_in(f.read_text(encoding="utf-8")):
				if target and not (self.out / target).exists():
					out.append((f.name, target))
		return out

	def ordered(self) -> list[Page]:
		rank = {k: i for i, (k, _) in enumerate(SECTIONS)}
		return sorted(self.pages.values(), key=lambda p: (rank.get(p.section, 99), p.order, p.title))

	def write(self, only: set[str] | None = None) -> None:
		css = (MANUAL / "theme" / "manual.css").read_text(encoding="utf-8")
		(self.out / "manual.css").write_text(css, encoding="utf-8")
		fonts = self.out / "fonts"
		fonts.mkdir(exist_ok=True)
		for f in ("Cinzel.ttf", "Lora.ttf", "Cinzel-OFL.txt", "Lora-OFL.txt"):
			shutil.copyfile(ROOT / "assets" / "fonts" / f, fonts / f)
		mark = self.img.png("assets/menus/menu_wordmark.png", 600)
		template = (MANUAL / "theme" / "page.html").read_text(encoding="utf-8")
		ordered = self.ordered()
		for i, p in enumerate(ordered):
			if only and p.slug not in only:
				continue
			prev_p = ordered[i - 1] if i > 0 else None
			next_p = ordered[i + 1] if i + 1 < len(ordered) else None
			pager = '<nav class="pager" aria-label="Pages">%s%s</nav>' % (
				'<a href="%s.html">&larr; %s</a>' % (prev_p.slug, esc(prev_p.title)) if prev_p else "<span></span>",
				'<a href="%s.html">%s &rarr;</a>' % (next_p.slug, esc(next_p.title)) if next_p else "<span></span>")
			banner_style = ' style="background-image:url(\'%s\')"' % esc(p.banner) if p.banner else ""
			crest = '<img class="crest" src="%s" alt="">' % esc(p.crest) if p.crest else ""
			eyebrow = '<p class="eyebrow">%s</p>' % p.eyebrow if p.eyebrow else ""
			lede = '<p class="lede">%s</p>' % esc(p.lede) if p.lede else ""
			page_title = TITLE if p.slug == "index" else "%s &middot; %s" % (esc(p.title), TITLE)
			out = (template
				.replace("{{page_title}}", page_title)
				.replace("{{description}}", esc(p.description or p.lede or TITLE))
				.replace("{{wordmark}}", esc(mark or ""))
				.replace("{{nav}}", self.nav_html(p.slug))
				.replace("{{banner_class}}", "banner" if p.banner else "banner slim")
				.replace("{{banner_style}}", banner_style)
				.replace("{{crest}}", crest)
				.replace("{{eyebrow}}", eyebrow)
				.replace("{{title}}", esc(p.title))
				.replace("{{lede}}", lede)
				.replace("{{body}}", p.body)
				.replace("{{pager}}", pager))
			(self.out / ("%s.html" % p.slug)).write_text(out, encoding="utf-8")


def _links_in(text: str) -> list[str]:
	return re.findall(r'(?:href|src)="([^"#:]+?)(?:#[^"]*)?"', text)


def _is_large(path: Path) -> bool:
	try:
		with Image.open(path) as im:
			return im.width > 320
	except OSError:
		return False


def _front_matter(text: str) -> tuple[dict, str]:
	meta: dict = {}
	if text.startswith("---\n"):
		end = text.find("\n---", 4)
		if end != -1:
			for line in text[4:end].splitlines():
				if ":" in line:
					k, v = line.split(":", 1)
					meta[k.strip()] = v.strip()
			text = text[end + 4:]
	return meta, text


def _toc(heads: list) -> str:
	items = [(lvl, hid, txt) for lvl, hid, txt in heads if lvl == 2]
	if len(items) < 3:
		return ""
	return '<nav class="toc" aria-label="On this page">%s</nav>' % "".join('<a href="#%s">%s</a>' % (hid, txt) for _, hid, txt in items)


def _sentence(text: str) -> str:
	text = text.strip()
	return text if not text or text.endswith((".", "!", "?")) else text + "."


def _roman(n: int) -> str:
	return ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII"][n] if 0 <= n <= 12 else str(n)


def _cost(cost: dict) -> str:
	parts = []
	for r in RESOURCE_ORDER:
		if cost.get(r):
			parts.append("%s %s" % (cost[r], r))
	return " &middot; ".join(parts)


def _ability_params(ab: dict) -> str:
	out = []
	for k, v in ab.items():
		if k == "id":
			continue
		if isinstance(v, float) and v < 1:
			out.append("%s %d%%" % (k.replace("_", " "), round(v * 100)))
		else:
			out.append("%s %s" % (k.replace("_", " "), v))
	return ", ".join(out)


def _strip_meta_text(text: str) -> str:
	"""Campaign blurbs carry notes for players of older builds ("Chapter 1 is the tutorial; ...")."""
	text = re.sub(r"^Expansion\.\s*", "", text)
	text = re.sub(r"\s*Chapter 1 is the tutorial;[^.]*\.", "", text)
	return text.strip()


def main() -> int:
	ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
	ap.add_argument("--out", default=str(ROOT / "export" / "manual"))
	ap.add_argument("--only", default="", help="comma-separated page slugs to write (all pages are still built)")
	args = ap.parse_args()
	out = Path(args.out).resolve()
	out.mkdir(parents=True, exist_ok=True)
	site = Site(out)
	site.load_markdown_pages()
	site.faction_pages()
	site.bestiary_page()
	site.campaign_pages()
	site.dev_pages()
	site.write(set(filter(None, args.only.split(","))) or None)
	broken = site.broken_links()
	for page, target in broken:
		print("broken link: %s -> %s" % (page, target), file=sys.stderr)
	size = sum(f.stat().st_size for f in out.rglob("*") if f.is_file())
	print("Manual: %d pages, %.1f MB in %s" % (len(site.pages), size / 1e6, out))
	return 1 if broken else 0


if __name__ == "__main__":
	sys.exit(main())
