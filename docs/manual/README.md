# The Crowns of Caern manual

The player manual (lore, peoples, heroes, campaigns, how to play) and the developer docs, built as one static
website in the game's own style.

```sh
python3 tools/manual/build_manual.py            # writes export/manual/ (git-ignored)
open export/manual/index.html                   # macOS; any browser works
```

Only Pillow is needed, which the asset pipeline already uses. A build takes about ten seconds and the site is
about 30 MB, almost all of it artwork. It works from disk without a web server, so the folder can be zipped,
copied to a phone or uploaded to any static host.

## Where the content comes from

| Part | Source | How to change it |
|---|---|---|
| Hand-written pages (home, the world, how to play, heroes) | `docs/manual/pages/*.md` | Edit the Markdown. |
| Faction lore and play style | `docs/manual/data/factions.json` | Edit the JSON (Markdown inside the strings). |
| Hero epithets and bios | `docs/manual/data/heroes.json` | Edit the JSON. |
| Units, stats, abilities, hero classes, skills, spells, equipment | `data/*.json`, `data/creatures/*.json` | Change the game data; the manual follows. |
| Campaign chapters and briefings | `data/campaigns.json` | Change the game data. |
| Chapter paintings | `assets/campaign_art.json` | Add the painting through the art pipeline (`assets/specs/campaign_illustrations.json`). Until then the chapter shows a dashed frame naming the expected file. |
| Developer docs | `docs/*.md`, `tools/assets/README.md` | Edit those files; they are rendered unchanged. The list is `DEV_DOCS` in `tools/manual/build_manual.py`. |
| Look | `docs/manual/theme/manual.css`, `docs/manual/theme/page.html` | Fonts are the game's own Cinzel and Lora. |

Canon lives in [the story bible](../STORY.md) and [the faction guide](../FACTIONS.md). Keep the manual's lore
consistent with them, and never put spoilers outside the campaign pages' *Aftermath* toggles.

## Page format

Each page in `docs/manual/pages/` starts with front matter:

```
---
title: Armies and Battles
section: play          # begin, world, peoples, heroes, campaigns, play or dev
order: 4               # position in its section
nav: Short nav title   # optional
eyebrow: How to play   # small line above the title
lede: One sentence under the title.
banner: assets/battlefields/grass_border_ruins.png
toc: yes               # optional table of contents from the ## headings
description: One line for link previews.
---
```

The Markdown subset is documented at the top of `tools/manual/mdlite.py`: headings, lists, tables, links,
images, quotes, code, and boxes written as `::: tip "Title"` ... `:::` (kinds: `tip`, `aside`, `warning`,
`lore`). Link to another manual page with `page:<slug>`, for example `[Towns](page:play-towns)`. Images may
use repository paths such as `assets/illustrations/...`; the build resizes them.

A line holding only `{{name}}` inserts a generated block: `faction_crests`, `campaign_cards`, `world_map`,
`peoples_cards`, `battle_orders`, `hero_classes`, `skills_table`, `spells_table`, `equipment_tables`
(the `block_*` methods of `Site`).

## Hosting

The repository is private, so GitHub Pages is not available on the current plan. The built folder can be
opened locally, zipped and shared, or published as a Claude artifact. If the repository becomes public,
Pages can serve `export/manual` from a workflow that runs the build.
