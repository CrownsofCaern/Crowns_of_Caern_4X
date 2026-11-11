shader_type canvas_item;
render_mode unshaded;

uniform float loop_phase = 0.0;
uniform float offset = 0.0;
uniform vec3 light_color = vec3(1.0, 0.58, 0.18);
// A hand-placed fabric region in normalized source-image coordinates.
uniform vec4 banner = vec4(0.0);
varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec2 uv = UV;
	float tau = 6.28318530718;
	if (banner.z > 0.0 && banner.w > 0.0) {
		vec2 local = (uv - banner.xy) / banner.zw;
		if (local.x > 0.0 && local.x < 1.0 && local.y > 0.0 && local.y < 1.0) {
			float edge = sin(local.x * 3.14159265);
			uv.x += sin(tau * (loop_phase * 2.0 - local.y * 0.35 + offset)) * local.y * edge * 0.006;
		}
	}
	vec4 tex = texture(TEXTURE, uv);
	float high = max(tex.r, max(tex.g, tex.b));
	float low = min(tex.r, min(tex.g, tex.b));
	float saturation = (high - low) / max(high, 0.001);
	vec3 hue = tex.rgb / max(high, 0.001);
	vec3 target = light_color / max(max(light_color.r, light_color.g), light_color.b);
	float matching = 1.0 - smoothstep(0.26, 0.65, distance(hue, target));
	float emission = matching * smoothstep(0.35, 0.75, high) * smoothstep(0.25, 0.65, saturation);
	float flicker = 0.5 + 0.30 * sin(tau * (loop_phase * 5.0 + offset)) + 0.20 * sin(tau * (loop_phase * 13.0 + offset * 2.0));
	tex.rgb += light_color * emission * flicker * 0.16;
	COLOR = tex * tint;
}
