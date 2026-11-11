# Repository guide

Crowns of Caern is a Godot 4 turn-based strategy game. The GitHub repository is still named `Reignem`; a local clone may have any directory name. Godot opens `project.godot` at the repository root. The old name also appears in historical artwork, save migration and the `REIGNEM_IMAGE_MODEL` environment variable; these are not evidence that the game is still named Reignem.

## Start here

- [README](../README.md): installation, controls and common commands.
- [Agent and contributor rules](../CLAUDE.md): determinism, headless logic, save compatibility, art and tests. [AGENTS.md](../AGENTS.md) is the agent entry point.
- [Design and architecture](DESIGN.md): game systems and data models. [Faction guide](FACTIONS.md): faction identities. [Story bible](STORY.md): world, timeline, cast and every campaign's beats. [Art bible](ART_BIBLE.md): visual direction; older sheets linked there are historical references, not necessarily current production art.
- [Game manual](manual/README.md): the player manual (lore, peoples, heroes, campaigns, rules) and the developer docs as one illustrated website, generated from `data/` and the artwork by `tools/manual/build_manual.py`.
- [iOS guide](IOS.md): export and signing. Reports under `docs/art/` document individual art batches and are historical snapshots, not necessarily current instructions.

## Code and data

| Location | Purpose / useful entry points |
| --- | --- |
| `project.godot`, `scenes/main.tscn`, `src/app/` | Godot configuration, startup and application entry. |
| `src/game/game_session.gd` | Commands and orchestration between UI and game rules. `game_setup.gd` prepares new games. |
| `src/core/` | Data loading and validation (`game_data.gd`), state and save migration (`game_state.gd`), deterministic RNG. |
| `src/world/` | Adventure map, movement and procedural generation. |
| `src/heroes/`, `src/armies/`, `src/economy/`, `src/combat/`, `src/ai/` | Rules for heroes, armies, towns, battles and computer players. |
| `src/ui/` | Menus, map and screens; `art.gd` resolves sprite assets. UI calls `GameSession` rather than changing rules directly. |
| `src/audio/`, `data/audio.json` | Audio catalog and playback. |
| `data/` | Game definitions, including factions, buildings, classes, spells and rules. `creatures/` contains faction rosters; `maps/` contains authored maps; `map_templates.json` configures generated maps. |
| `tests/unit/`, `tests/run_tests.gd` | Headless tests and runner. `./run_tests.sh [--slow] [filter]` imports the project, runs the tests in one Godot process per CPU core (each with its own empty user data folder) and, without a filter, checks the asset pipeline when Python dependencies are available. `--slow` adds the tests that files list in `const SLOW`. |
| `tools/` | Map, balance, screenshot, art and audio tools. See `tools/assets/README.md` for asset commands and dependencies. |

## Artwork and generated files

`assets/specs/` defines pipeline inputs; `assets/source/` holds source images, production batches, prompts and concepts. `assets/atlases/` and `assets/manifest.json` are generated runtime outputs. Other runtime art includes `assets/towns/`, `assets/menus/`, `assets/hero_portraits/`, `assets/artifacts/` and `assets/battlefields/`; their specific pipelines and manifests are described in [the asset pipeline guide](../tools/assets/README.md). `assets/build/` contains per-sprite review output, and `docs/art/production/` contains review sheets and reports.

A picture can be unused by the game and still be an input to a generator, a fallback, a provenance record or a documentation illustration. Before removing or moving it, search code, JSON manifests, specs, tests and documentation, including dynamically constructed paths; run the relevant pipeline validation and rebuild checks. Preserve source files needed to reproduce committed outputs. Old concepts and batch reports should be identified as historical rather than assumed to be disposable.

The Python pipeline lives at `tools/assets/crowns_of_cinder_assets/`. Use `python3 tools/assets/pipeline.py validate` and `python3 tools/assets/pipeline.py check`, with Pillow and NumPy installed. `build` regenerates outputs; review its diff. The pipeline still accepts `REIGNEM_IMAGE_MODEL` for compatibility.
