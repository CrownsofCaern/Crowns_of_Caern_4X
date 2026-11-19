class_name MapPaint
extends RefCounted
## The painted adventure-map surface: one shaded quad draws the ground with
## rounded, brushed terrain borders, shorelines and the realm borders; a second
## quad draws a calm fog. Purely visual: reads the map, never changes rules or
## state. MapView falls back to its tile layers where the atlas has no painted
## fields (or with CC_MAP_PAINT=0).

const FIELD_CELLS := 12

const GROUND_SHADER := "
shader_type canvas_item;
uniform sampler2DArray fields : repeat_enable, filter_linear_mipmap;
uniform sampler2D idmap : filter_nearest;
uniform sampler2D owner_map : filter_linear;
uniform vec2 map_size;
uniform float field_tiles = 12.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 p = UV * map_size;
	vec2 w1 = vec2(vnoise(p * 0.8), vnoise(p * 0.8 + vec2(31.7, 11.3))) - 0.5;
	vec2 w2 = vec2(vnoise(p * 2.6 + 5.0), vnoise(p * 2.6 + vec2(7.1, 43.0))) - 0.5;
	vec2 q = p + w1 * 0.7 + w2 * 0.24;
	ivec2 c = ivec2(floor(q));
	ivec2 hi = ivec2(map_size) - ivec2(1);
	float pres[12];
	for (int i = 0; i < 12; i++) { pres[i] = 0.0; }
	float total = 0.0;
	for (int dy = -1; dy <= 1; dy++) {
		for (int dx = -1; dx <= 1; dx++) {
			ivec2 n = clamp(c + ivec2(dx, dy), ivec2(0), hi);
			int id = int(texelFetch(idmap, n, 0).r * 255.0 + 0.5);
			vec2 d = (vec2(c + ivec2(dx, dy)) + 0.5) - q;
			float g = exp(-dot(d, d) / 0.62);
			pres[id] += g;
			total += g;
		}
	}
	vec2 fuv = p / field_tiles;
	vec2 gx = dFdx(fuv); vec2 gy = dFdy(fuv);
	vec3 col = vec3(0.0);
	float ws = 0.0;
	float top = 0.0;
	for (int i = 0; i < 12; i++) {
		float pr = pres[i] / total;
		if (pr > 0.02) {
			float dab = 0.72 + 0.56 * vnoise(p * 7.0 + float(i) * 3.1);
			float k = pow(pr * dab, 7.0);
			col += k * textureGrad(fields, vec3(fuv, float(i)), gx, gy).rgb;
			ws += k;
			top = max(top, pr);
		}
	}
	col /= max(ws, 1e-6);
	// A faint dark seam where two grounds meet keeps the border readable.
	col *= 1.0 - 0.16 * (1.0 - smoothstep(0.5, 0.64, top));
	// Shore: wet, darker land beside water and a thin pale line at the waterline.
	float wp = (pres[0] + pres[1]) / total;
	float wet = smoothstep(0.06, 0.46, wp) * (1.0 - smoothstep(0.5, 0.58, wp));
	col *= 1.0 - 0.34 * wet;
	float foam = smoothstep(0.5, 0.55, wp) * (1.0 - smoothstep(0.56, 0.7, wp));
	col += foam * 0.14 * vec3(0.75, 0.88, 1.0) * (0.6 + 0.8 * vnoise(p * 5.0));
	// Territory: a rounded line in the owner's colour with a glow fading inwards.
	// Presence counts only the nearest owner's cells, so two realms that touch
	// each keep their own line.
	{
		vec2 tq = p + w1 * 0.18;
		ivec2 tc = ivec2(floor(tq));
		vec3 oc = vec3(0.0); float best = 0.0;
		for (int dy = -1; dy <= 1; dy++) {
			for (int dx = -1; dx <= 1; dx++) {
				vec4 o = texelFetch(owner_map, clamp(tc + ivec2(dx, dy), ivec2(0), hi), 0);
				vec2 d = (vec2(tc + ivec2(dx, dy)) + 0.5) - tq;
				float g = exp(-dot(d, d) / 0.5) * o.a;
				if (g > best) { best = g; oc = o.rgb; }
			}
		}
		float oa = 0.0; float ot = 0.0;
		for (int dy = -1; dy <= 1; dy++) {
			for (int dx = -1; dx <= 1; dx++) {
				vec4 o = texelFetch(owner_map, clamp(tc + ivec2(dx, dy), ivec2(0), hi), 0);
				vec2 d = (vec2(tc + ivec2(dx, dy)) + 0.5) - tq;
				float g = exp(-dot(d, d) / 0.5);
				vec3 dc = o.rgb - oc;
				oa += g * o.a * step(dot(dc, dc), 0.0004); ot += g;
			}
		}
		oa /= ot;
		float dist = abs(oa - 0.5) / max(fwidth(oa), 1e-5);
		float line = 1.0 - smoothstep(0.9, 2.1, dist);
		float halo = 1.0 - smoothstep(2.4, 4.6, dist);
		float inner = smoothstep(0.5, 0.52, oa) * (1.0 - smoothstep(0.5, 0.95, oa));
		col = mix(col, oc, inner * 0.3);
		col = mix(col, vec3(0.0), halo * 0.45);
		col = mix(col, mix(oc, vec3(1.0), 0.18), line * 0.92);
	}
	COLOR = vec4(col, 1.0);
}
"

const FOG_SHADER := "
shader_type canvas_item;
uniform sampler2D explored : filter_linear;
uniform sampler2D fog_field : repeat_enable, filter_linear_mipmap;
uniform vec2 map_size;
uniform float field_tiles = 12.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 p = UV * map_size;
	vec2 w1 = vec2(vnoise(p * 0.7 + 3.0), vnoise(p * 0.7 + vec2(13.7, 71.3))) - 0.5;
	vec2 w2 = vec2(vnoise(p * 2.2 + 9.0), vnoise(p * 2.2 + vec2(47.1, 3.0))) - 0.5;
	vec2 q = p + w1 * 0.9 + w2 * 0.3;
	float e = texture(explored, q / map_size).r;
	float a = 1.0 - smoothstep(0.3, 0.72, e);
	vec3 f = texture(fog_field, p / field_tiles + vec2(TIME * 0.004, TIME * 0.0015)).rgb;
	float lum = dot(f, vec3(0.3, 0.59, 0.11));
	// Calm and dark: half the colour, a third of the contrast, so the land leads.
	f = mix(vec3(lum), f, 0.55);
	f = vec3(0.045, 0.055, 0.08) + (f - 0.25) * 0.3 + 0.07;
	float shade = (1.0 - smoothstep(0.55, 1.0, e)) * 0.4;
	float alpha = a + shade * (1.0 - a);
	COLOR = vec4(f * (a / max(alpha, 1e-4)), alpha);
}
"


## True when the terrain atlas carries a painted field for every ground and the fog.
static func supported(info: Dictionary) -> bool:
	if OS.get_environment("CC_MAP_PAINT") == "0":
		return false
	if not info.get("fog", {}).has("field") or info.get("order", []).is_empty() or info["order"].size() > 12:
		return false
	for tid in info["order"]:
		if not info["terrains"].get(tid, {}).has("field"):
			return false
	return true


## A map-sized quad at `tile` pixels a cell with the given shader.
static func _quad(name: String, map: AdventureMap, tile: int, code: String) -> ColorRect:
	var rect := ColorRect.new()
	rect.name = name
	rect.size = Vector2(map.width, map.height) * tile
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var sh := Shader.new()
	sh.code = code
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("map_size", Vector2(map.width, map.height))
	mat.set_shader_parameter("field_tiles", float(FIELD_CELLS))
	rect.material = mat
	return rect


## The 12 x 12 cell painted field of one atlas row as a single tileable image.
static func _field_image(atlas: Image, info: Dictionary, row: int) -> Image:
	var ts := int(info["tile_size"])
	var column := int(info["fog"]["field"]["column"])
	var img := Image.create(FIELD_CELLS * ts, FIELD_CELLS * ts, true, Image.FORMAT_RGBA8)
	for y in FIELD_CELLS:
		for x in FIELD_CELLS:
			img.blit_rect(atlas, Rect2i((column + y * FIELD_CELLS + x) * ts, row * ts, ts, ts), Vector2i(x * ts, y * ts))
	img.generate_mipmaps()
	return img


static func _atlas_image(info: Dictionary) -> Image:
	var img := (load(String(info["atlas"])) as Texture2D).get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img


static func build_ground(map: AdventureMap, tiles: TerrainTiles, tile: int, visual: Callable) -> ColorRect:
	var rect := _quad("PaintedGround", map, tile, GROUND_SHADER)
	var atlas := _atlas_image(tiles.info)
	var order: Array = tiles.info["order"]
	var layers: Array[Image] = []
	for tid in order:
		layers.append(_field_image(atlas, tiles.info, tiles.terrain_row(String(tid))))
	while layers.size() < 12:
		layers.append(layers[0])
	var arr := Texture2DArray.new()
	arr.create_from_images(layers)
	var ids := id_image(map, order, visual)
	rect.set_meta("ids", ids)
	var mat: ShaderMaterial = rect.material
	mat.set_shader_parameter("fields", arr)
	mat.set_shader_parameter("idmap", ImageTexture.create_from_image(ids))
	mat.set_shader_parameter("owner_map", ImageTexture.create_from_image(Image.create(map.width, map.height, false, Image.FORMAT_RGBA8)))
	return rect


## One pixel per cell: the index of the cell's visual terrain in `order`.
static func id_image(map: AdventureMap, order: Array, visual: Callable) -> Image:
	var ids := Image.create(map.width, map.height, false, Image.FORMAT_R8)
	for y in map.height:
		for x in map.width:
			ids.set_pixel(x, y, Color(maxi(order.find(String(visual.call(Vector2i(x, y)))), 0) / 255.0, 0, 0))
	return ids


## Repaint the ground of `cells` after a terrain edit (the map editor's preview).
static func update_ground(rect: ColorRect, order: Array, visual: Callable, cells: Array) -> void:
	var ids: Image = rect.get_meta("ids")
	for t in cells:
		ids.set_pixel(t.x, t.y, Color(maxi(order.find(String(visual.call(t))), 0) / 255.0, 0, 0))
	(rect.material as ShaderMaterial).set_shader_parameter("idmap", ImageTexture.create_from_image(ids))


static func build_fog(map: AdventureMap, tiles: TerrainTiles, tile: int) -> ColorRect:
	var rect := _quad("PaintedFog", map, tile, FOG_SHADER)
	var field := _field_image(_atlas_image(tiles.info), tiles.info, int(tiles.info["fog"]["row"]))
	(rect.material as ShaderMaterial).set_shader_parameter("fog_field", ImageTexture.create_from_image(field))
	return rect


static func sync_fog(rect: ColorRect, map: AdventureMap, fog: FogOfWar) -> void:
	var img := Image.create(map.width, map.height, false, Image.FORMAT_R8)
	for y in map.height:
		for x in map.width:
			if fog.is_explored(Vector2i(x, y)):
				img.set_pixel(x, y, Color(1, 0, 0))
	(rect.material as ShaderMaterial).set_shader_parameter("explored", ImageTexture.create_from_image(img))


static func sync_territory(rect: ColorRect, map: AdventureMap, cells: Dictionary) -> void:
	(rect.material as ShaderMaterial).set_shader_parameter("owner_map", ImageTexture.create_from_image(territory_image(map, cells)))


## `cells`: tile -> Color of the owner whose influence covers it. Colour bleeds
## one cell outwards with no alpha, so the rim keeps its hue.
static func territory_image(map: AdventureMap, cells: Dictionary) -> Image:
	var img := Image.create(map.width, map.height, false, Image.FORMAT_RGBA8)
	for p in cells:
		var c: Color = cells[p]
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var n: Vector2i = p + Vector2i(dx, dy)
				if map.in_bounds(n) and not cells.has(n):
					img.set_pixel(n.x, n.y, Color(c.r, c.g, c.b, 0.0))
	for p in cells:
		var c: Color = cells[p]
		img.set_pixel(p.x, p.y, Color(c.r, c.g, c.b, 1.0))
	return img
