# Cobolts concept v1

Generated 2026-11-09 with the built-in imagegen tool. Concept reference only; not integrated into the game or approved as production sprites.

`cobolts-concept-v1.png` shows T1 Pack Runner, T2 Caravan Spear, T3 Bolt Broker, T4 Cinder Alchemist and T5 Vault Warden above L1 Roadside Stall, L2 Caravan Yard and L3 Vault Exchange. Review the larger T5 proportions before final sprite production. Native sprite size, palette reduction, alpha and animation remain future work.

Design: [COBOLTS.md](../../../../docs/design/COBOLTS.md). Exact generation prompt: [prompt.txt](prompt.txt).

## Production still sprites

The eight isolated production sprites were generated with built-in imagegen using the approved concept and existing pike militia, shieldwarden and road trader as explicit style references. Exact prompts and reference paths are in `production-prompts.json`; raw transparent sources and provenance are retained in `assets/source/generated/*cobolt*`. Creatures use 128×128 native sprites at 0.5 map scale; posts use 160×144 at 0.5 scale. The standard pipeline preserves material ramps, fits alpha content and applies a one-pixel dark outline.

The original simplified pixel grids remain fallback assets. Animation groups are explicitly pending. Native-scale style comparison: `docs/art/production/cobolt-style-contact.png`.
