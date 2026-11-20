shader_type spatial;
// Round 22 (owner): Mr. Grimm's skull is a ghost, not bone: see-through, glowing red, brightest along its
// outline from every side, faint inside, with slow wisps drifting through it and a restless flicker. The
// deep sockets and the nose hole face the viewer, so they stay dark: the face still reads.
render_mode unshaded, blend_mix, depth_draw_never, cull_back;

uniform vec4 tint : source_color = vec4(1.0, 0.08, 0.04, 1.0);
uniform float fade = 1.0;      // afterimages draw fainter
uniform float glow = 1.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float rim = pow(1.0 - facing, 2.2);
	vec3 w = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float wisp = noise(vec2(w.x * 2.5 + w.z * 1.7, w.y * 3.0 - TIME * 4.0));
	float flicker = 0.85 + 0.15 * sin(TIME * 37.0) * sin(TIME * 23.0 + 1.3);
	float a = (rim * 1.3 + 0.3 + wisp * 0.25) * flicker * fade;
	ALBEDO = mix(tint.rgb, vec3(1.0, 0.45, 0.3), rim * rim * 0.45) * glow * (0.8 + rim);
	ALPHA = clamp(a, 0.0, 1.0);
}
