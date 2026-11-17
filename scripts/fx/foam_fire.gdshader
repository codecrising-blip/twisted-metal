// The game's fire (round 18, the owner's pick "hair strands", from his TMB clips): one puff of a fire made
// of many. A soft rounded blob with a frayed, bubbling edge, fuller at the root, filled with fine vertical
// strands racing up. Young puffs burn orange-hot, old ones deep red. Premultiplied blending: `glow` < 1
// adds a little light over dark ground. FoamFire builds the puffs (vertex COLOR: r = age 0..1, g = seed,
// a = fade); UV.y = 1 at the puff's root.
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform float glow = 0.55;
uniform float strands = 26.0;
uniform vec4 deep : source_color = vec4(0.6, 0.02, 0.0, 1.0);
uniform vec4 mid : source_color = vec4(0.95, 0.15, 0.03, 1.0);
uniform vec4 hot : source_color = vec4(1.0, 0.45, 0.1, 1.0);

varying vec4 col;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	col = COLOR;
}

void fragment() {
	float age = col.r;
	float seed = col.g * 97.0;
	float fade = col.a;
	float t = TIME;
	// The blob: centred a little low (a fuller root), taller than wide, its edge fraying and bubbling.
	vec2 uv = UV - vec2(0.5, 0.56);
	float r = length(uv * vec2(1.0, 0.8)) * 2.0;
	float fray = (vnoise(uv * 5.5 + vec2(seed, seed * 0.7 - t * 1.6)) - 0.5) * 0.5;
	float blob = 1.0 - smoothstep(0.45 + fray * 0.6, 1.0 + fray * 0.3, r);
	// Fine vertical strands racing up.
	float s1 = vnoise(vec2(UV.x * strands * 1.3 + seed, UV.y * 2.0 + t * 3.4));
	float s2 = vnoise(vec2(UV.x * strands * 2.7 - seed, UV.y * 3.6 + t * 5.0));
	float s = smoothstep(0.42, 0.84, s1 * 0.6 + s2 * 0.4);
	float body = blob * (0.3 + 0.7 * s);
	float heat = (1.0 - age * 0.85) * (0.5 + 0.5 * s) * (1.0 - r * 0.35);
	vec3 c = mix(deep.rgb, mid.rgb, smoothstep(0.12, 0.5, heat));
	c = mix(c, hot.rgb, smoothstep(0.55, 0.92, heat));
	float a = clamp(body * fade, 0.0, 1.0);
	ALBEDO = c * a;
	ALPHA = a * glow;
}
