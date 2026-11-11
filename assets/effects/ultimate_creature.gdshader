shader_type canvas_item;

// Faction ultimate upgrade treatment, applied to the existing creature art.
// Keeps the source alpha and dark outline; adds a faction-coloured highlight
// (the base treatment) plus a small animated accent per faction (style):
//   0 Concord     holy: a slow golden glint sweeping across the armour
//   1 Ashen       hellbrand: flickering heat and sparks rising through the body
//   2 Hollow      deathless: a slow sickly pulse and a ghost-green rim
//   3 Thornwood   thornblood: green sap veins creeping through the bark
//   4 Forge       runeplate: rune pixels kindling and fading on the plate
//   5 Frostmarch  wintersblood: frost on the highlights and cold twinkles
//   6 Dark elves  eclipse arms: restrained amethyst veil glints
//   7 Fish men    tidal arms: soft cyan caustics across shell and scales
// Set per faction through UltimateCreatureArt; no atlas is rewritten.
uniform vec4 accent : source_color = vec4(1.0, 0.78, 0.36, 1.0);
uniform float strength : hint_range(0.0, 1.0) = 0.30;
uniform float glint_strength : hint_range(0.0, 1.0) = 0.18;
uniform int style = 0;
uniform float edge_strength : hint_range(0.0, 1.0) = 0.55;
uniform float effect_strength : hint_range(0.0, 1.0) = 0.7;
uniform float phase = 0.0;

varying vec4 vertex_tint;
varying vec2 local_px;

void vertex() {
	vertex_tint = COLOR;
	local_px = VERTEX;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec4 original = texture(TEXTURE, UV) * vertex_tint;
	float light = dot(original.rgb, vec3(0.299, 0.587, 0.114));
	// Leave dark outlines intact and keep the source material visible.
	float highlight = smoothstep(0.18, 0.72, light);
	float glint = smoothstep(0.72, 0.96, light);
	vec3 treated = mix(original.rgb, original.rgb * accent.rgb * 1.35, strength * highlight);
	treated = mix(treated, accent.rgb, glint * glint_strength);

	// Rim: opaque pixels next to transparency (two texels out) catch the light.
	vec2 px = TEXTURE_PIXEL_SIZE * 2.0;
	float around = min(min(texture(TEXTURE, UV + vec2(px.x, 0.0)).a, texture(TEXTURE, UV - vec2(px.x, 0.0)).a),
		min(texture(TEXTURE, UV + vec2(0.0, px.y)).a, texture(TEXTURE, UV - vec2(0.0, px.y)).a));
	float rim = step(0.5, original.a) * (1.0 - step(0.5, around));

	float t = TIME + phase;
	vec2 p = floor(local_px);
	vec3 col = accent.rgb;
	float fx = 0.0;
	float pulse = 0.5 + 0.5 * sin(t * 2.0);
	if (style == 0) {
		float sweep = sin((p.x + p.y) * 0.05 - t * 1.6);
		fx = smoothstep(0.9, 1.0, sweep) * (0.35 + highlight);
		col = mix(accent.rgb, vec3(1.0, 0.97, 0.85), 0.5);
	} else if (style == 1) {
		vec2 cell = floor(vec2(p.x / 3.0, (p.y + t * 26.0) / 3.0));
		float spark = step(0.965, hash(cell));
		float flicker = 0.55 + 0.45 * sin(t * 11.0 + hash(floor(p / 4.0)) * 6.283);
		fx = spark + 0.25 * flicker * highlight;
		pulse = flicker;
	} else if (style == 2) {
		pulse = 0.5 + 0.5 * sin(t * 1.3);
		treated = mix(treated, treated * vec3(0.8, 0.95, 0.8), 0.35 * pulse);
		fx = 0.18 * pulse * (1.0 - highlight);
	} else if (style == 3) {
		float vein = sin(p.x * 0.35 + sin(p.y * 0.18 + t * 0.9) * 2.5);
		fx = smoothstep(0.92, 1.0, vein) * (0.4 + 0.6 * (0.5 + 0.5 * sin(t * 1.7 + p.y * 0.05)));
	} else if (style == 4) {
		// Small cross-shaped runes kindle on the plate, glow and fade.
		vec2 cell = floor(p / 5.0);
		vec2 in_cell = mod(p, 5.0);
		float cross = max(step(abs(in_cell.x - 2.0), 0.5), step(abs(in_cell.y - 2.0), 0.5))
			* step(abs(in_cell.x - 2.0), 1.5) * step(abs(in_cell.y - 2.0), 1.5);
		float cycle = t * 0.8 + hash(cell) * 7.0;
		float lit = step(0.86, hash(cell + floor(cycle)));
		float glow = sin(fract(cycle) * 3.14159);
		fx = lit * cross * glow * smoothstep(0.04, 0.2, light);
		col = vec3(1.0, 0.72, 0.32);
	} else if (style == 5) {
		treated = mix(treated, treated * vec3(0.85, 0.95, 1.1) + vec3(0.04, 0.06, 0.1), 0.45 * highlight);
		float h = hash(floor(p / 2.0));
		float twinkle = step(0.985, h) * max(0.0, sin(t * 3.0 + h * 40.0));
		fx = twinkle;
		col = vec3(0.92, 0.98, 1.0);
	} else if (style == 6) {
		float veil = sin(p.x * 0.075 - p.y * 0.04 - t * 1.1);
		fx = smoothstep(0.94, 1.0, veil) * highlight * 0.55;
		pulse = 0.5 + 0.5 * sin(t * 1.4);
		col = mix(accent.rgb, vec3(0.89, 0.79, 1.0), 0.35);
	} else if (style == 7) {
		float wave = sin(p.x * 0.13 + t * 1.2) * sin(p.y * 0.10 - t * 0.8);
		fx = smoothstep(0.82, 1.0, wave) * (0.15 + highlight * 0.45);
		pulse = 0.5 + 0.5 * sin(t * 1.1);
		col = mix(accent.rgb, vec3(0.80, 1.0, 0.94), 0.25);
	}
	fx *= step(0.5, original.a) * effect_strength;
	treated = mix(treated, col, clamp(fx, 0.0, 1.0));
	treated = mix(treated, accent.rgb, rim * edge_strength * (0.55 + 0.45 * pulse));
	COLOR = vec4(treated, original.a);
}
