shader_type spatial;
// Round 23 (owner's Head-On video): Mr. Grimm's spirit skull is a picture of a skull face that always looks at the
// viewer (assets/fx/spirit_skull.png, rendered from our own sculpt by tools/blender/build_spirit_skull.py). It
// wavers like heat over a fire, flickers, and glows a little past white so the glow pass catches it.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D face : source_color, filter_linear_mipmap;
uniform float fade = 1.0;
uniform float glow = 1.0;
uniform vec3 tint = vec3(1.0, 0.62, 0.62); // pulls the pink highlights back toward red (the tonemapper bleaches them)
uniform float seed = 0.0;
uniform float waver = 1.0;

void vertex() {
	// A billboard that keeps the node's scale (the same matrices Godot's own billboard mode builds).
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 uv = UV;
	float t = TIME * 7.0 + seed;
	uv.x += sin(uv.y * 11.0 + t) * 0.007 * waver;
	uv.y += sin(uv.x * 8.0 - t * 1.3) * 0.006 * waver;
	vec4 c = texture(face, uv);
	float flick = 0.86 + 0.14 * sin(TIME * 29.0 + seed) * sin(TIME * 13.0 + seed * 1.7);
	ALBEDO = c.rgb * tint * glow;
	ALPHA = clamp(c.a * fade * flick, 0.0, 1.0);
}
