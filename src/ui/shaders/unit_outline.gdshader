shader_type spatial;
// Inverted hull: a dark shell drawn behind each 3D battle unit, pushed out
// along the normals by a fixed width on screen, so figures keep the strong
// dark outline of the art bible (docs/ART_BIBLE.md) at any distance.
render_mode unshaded, cull_front, shadows_disabled, depth_draw_opaque;

uniform vec4 outline_color : source_color = vec4(0.071, 0.051, 0.043, 1.0);
// Width in normalised screen units (2.0 = the screen's height).
uniform float width = 0.002;
// Pushes the shell back in depth so it never covers the unit's own faces
// (Tripo meshes are single-sided); sign for Godot's reversed depth.
uniform float depth_push = 0.003;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	vec3 n = (MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	vec2 dir = (PROJECTION_MATRIX * vec4(n, 0.0)).xy;
	if (length(dir) > 0.0001) {
		clip.xy += normalize(dir) * width * clip.w;
	}
	clip.z -= depth_push * clip.w;
	POSITION = clip;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
