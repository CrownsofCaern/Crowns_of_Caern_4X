# Hero portraits

The 24 class portraits and 18 named campaign portraits are generated originals.
Each class portrait was conditioned on its corresponding existing `hero_<class>`
sprite. Named portraits used the corresponding class sprite, campaign character
descriptions, and existing campaign illustrations when available. Image generation
is not deterministic; these originals are retained as the source of truth.

Run `godot --headless --path . --script res://tools/art/build_hero_portraits.gd`
to rebuild the 256 × 256 runtime images. Campaign portraits are keyed by stable
hero ID, and the UI falls back to the class portrait when the class does not
match the named character's original class.
