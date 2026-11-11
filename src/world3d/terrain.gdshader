shader_type spatial;
// Ground of the 3D map: grass, dirt (roads, yards), rock (mounds, slopes, mountains),
// forest floor and ash, blended from a splat map with the textures' own height
// (albedo alpha) so edges look worn rather than smeared. Textures: ambientCG (CC0).

uniform sampler2D grass_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D splat : filter_linear, repeat_disable;
uniform vec2 origin = vec2(0.0);
uniform vec2 size = vec2(1.0);
uniform sampler2D macro_noise : filter_linear, repeat_enable;
// Biomes: index 0 = base, 1 = west home, 2 = east home; biome_map R/G = west/east weight.
uniform sampler2D biome_map : filter_linear, repeat_disable;
uniform vec3 b_grass[3];
uniform vec3 b_lush[3];
uniform vec3 b_dry[3];
uniform vec3 b_dirt[3];
uniform vec3 b_rock[3];
uniform vec3 b_moss[3];
uniform vec3 b_ash[3];
uniform float b_snow[3];
uniform float grass_scale = 0.22;
uniform float dirt_scale = 0.35;
uniform float rock_scale = 0.12;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hblend(float w, float h) {
	// Height-aware blend: the higher texture pokes through first.
	return smoothstep(0.38, 0.62, w + (h - 0.5) * 0.45 * step(0.01, w) * step(w, 0.99));
}

void fragment() {
	vec2 xz = wpos.xz;
	vec4 sp = texture(splat, (xz - origin) / size);
	vec2 bm = texture(biome_map, (xz - origin) / size).rg;
	vec3 bw = vec3(max(0.0, 1.0 - bm.r - bm.g), bm.r, bm.g);
	vec3 grass_tint = b_grass[0] * bw.x + b_grass[1] * bw.y + b_grass[2] * bw.z;
	vec3 lush_tint = b_lush[0] * bw.x + b_lush[1] * bw.y + b_lush[2] * bw.z;
	vec3 dry_tint = b_dry[0] * bw.x + b_dry[1] * bw.y + b_dry[2] * bw.z;
	vec3 dirt_tint = b_dirt[0] * bw.x + b_dirt[1] * bw.y + b_dirt[2] * bw.z;
	vec3 rock_tint = b_rock[0] * bw.x + b_rock[1] * bw.y + b_rock[2] * bw.z;
	vec3 moss_tint = b_moss[0] * bw.x + b_moss[1] * bw.y + b_moss[2] * bw.z;
	vec3 ash_tint = b_ash[0] * bw.x + b_ash[1] * bw.y + b_ash[2] * bw.z;
	// Two scales of the same texture hide the repeat; large noise patches of dry
	// and lush grass and darker hollows keep open ground from looking like a carpet.
	vec4 g = mix(texture(grass_alb, xz * grass_scale), texture(grass_alb, xz * grass_scale * 0.37 + vec2(0.13, 0.61)), 0.4);
	float n1 = texture(macro_noise, xz * 0.012).r;
	float n2 = texture(macro_noise, xz * 0.05 + vec2(0.4, 0.2)).r;
	vec3 tint = mix(lush_tint, grass_tint, smoothstep(0.3, 0.55, n1));
	tint = mix(tint, dry_tint, smoothstep(0.58, 0.8, n1 * 0.7 + n2 * 0.3));
	float hollow = clamp(-wpos.y * 0.25, 0.0, 0.3);
	vec3 grass = g.rgb * tint * mix(0.8, 1.15, n2) * (1.0 - hollow);
	vec4 d = texture(rock_alb, xz * dirt_scale + vec2(0.5));
	vec3 dirt = d.rgb * dirt_tint;
	vec3 bl = pow(abs(wnrm), vec3(4.0));
	bl /= (bl.x + bl.y + bl.z);
	vec4 r = texture(rock_alb, wpos.zy * rock_scale) * bl.x + texture(rock_alb, xz * rock_scale) * bl.y
		+ texture(rock_alb, wpos.xy * rock_scale) * bl.z;
	vec3 rock = r.rgb * rock_tint;
	float slope = 1.0 - wnrm.y;
	float rock_w = clamp(max(sp.g, smoothstep(0.22, 0.42, slope)), 0.0, 1.0);

	vec3 col = mix(grass, grass * moss_tint / max(grass_tint, vec3(0.01)), sp.b * 0.8);
	col = mix(col, g.rgb * ash_tint, sp.a * 0.8);
	float dw = hblend(sp.r, d.a);
	col = mix(col, dirt, dw);
	float rw = hblend(rock_w, r.a);
	col = mix(col, rock, rw);
	// Snow: the ground texture's own light and shade in white, thinner on steep rock
	// and in trampled dirt, with the macro noise leaving a few bare patches.
	float snow = clamp(b_snow[0] * bw.x + b_snow[1] * bw.y + b_snow[2] * bw.z, 0.0, 1.0);
	float lum = dot(mix(g.rgb, r.rgb, rw), vec3(0.3, 0.59, 0.11));
	vec3 snow_col = vec3(0.5, 0.53, 0.6) * (0.65 + lum * 0.9) * mix(0.85, 1.05, n2);
	float cover = snow * (1.0 - rw * 0.55) * (1.0 - dw * 0.6) * smoothstep(0.2, 0.45, n1 * 0.8 + n2 * 0.4);
	col = mix(col, snow_col, cover);
	ALBEDO = col;

	vec3 ng = texture(grass_nrm, xz * grass_scale).rgb;
	vec3 nd = texture(rock_nrm, xz * dirt_scale + vec2(0.5)).rgb;
	vec3 nr = texture(rock_nrm, xz * rock_scale).rgb;
	vec3 n = mix(mix(ng, nd, dw), nr, rw);
	NORMAL_MAP = n;
	NORMAL_MAP_DEPTH = 1.0;
	ROUGHNESS = mix(0.95, 0.85, rw);
}
