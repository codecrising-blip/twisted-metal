// Foam fire (round 18, from the owner's TMB clips): one puff of a fire made of many. Each puff is a soft
// rounded blob with a frayed, bubbling edge, filled with thin flame strands racing up: crossed diagonal
// strands like woven straw (pattern 0, the TMB pyre) or fine vertical hair (pattern 1, a burning TMB car).
// Young puffs burn hot, old ones deep red. Premultiplied blending: `glow` < 1 adds light over dark ground.
// FoamFire builds the puffs on the CPU (vertex COLOR: r = age 0..1, g = seed, a = fade). Smoke puffs
// (`smoke` 1) are dark, soft and strandless.
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform int pattern = 0;
uniform float glow = 0.6;
uniform float smoke = 0.0;
uniform float strands = 26.0;
uniform vec4 deep : source_color = vec4(0.55, 0.03, 0.0, 1.0);
uniform vec4 mid : source_color = vec4(0.95, 0.22, 0.03, 1.0);
uniform vec4 hot : source_color = vec4(1.0, 0.6, 0.15, 1.0);
uniform vec4 soot : source_color = vec4(0.08, 0.075, 0.07, 1.0);

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
	vec2 uv = UV - 0.5;
	float t = TIME;
	// A rounded blob whose edge frays and bubbles (foam), a little taller than wide.
	float r = length(uv * vec2(1.0, 0.82)) * 2.0;
	float fray = (vnoise(uv * 5.5 + vec2(seed, seed * 0.7 - t * 1.6)) - 0.5) * 0.5;
	float blob = 1.0 - smoothstep(0.45 + fray * 0.6, 1.0 + fray * 0.3, r);
	if (smoke > 0.5) {
		float puff = blob * (0.7 + 0.3 * vnoise(uv * 4.0 + seed));
		float a = clamp(puff * fade * 0.6, 0.0, 1.0);
		ALBEDO = soot.rgb * a;
		ALPHA = a;
	} else {
		float s;
		if (pattern == 0) {
			// Crossed diagonal strands climbing (the TMB pyre's woven look).
			float s1 = vnoise(vec2((UV.x + UV.y * 0.42) * strands + seed, UV.y * 2.2 + t * 3.1));
			float s2 = vnoise(vec2((UV.x - UV.y * 0.42) * strands - seed, UV.y * 2.2 + t * 3.6));
			s = max(smoothstep(0.56, 0.86, s1), smoothstep(0.56, 0.86, s2));
		} else {
			// Fine vertical hair racing up (a burning TMB car).
			float s1 = vnoise(vec2(UV.x * strands * 1.3 + seed, UV.y * 2.0 + t * 3.4));
			float s2 = vnoise(vec2(UV.x * strands * 2.7 - seed, UV.y * 3.6 + t * 5.0));
			s = smoothstep(0.42, 0.84, s1 * 0.6 + s2 * 0.4);
		}
		float body = blob * (0.3 + 0.7 * s);
		float heat = (1.0 - age * 0.85) * (0.5 + 0.5 * s) * (1.0 - r * 0.35);
		vec3 c = mix(deep.rgb, mid.rgb, smoothstep(0.12, 0.5, heat));
		c = mix(c, hot.rgb, smoothstep(0.55, 0.92, heat));
		float a = clamp(body * fade, 0.0, 1.0);
		ALBEDO = c * a;
		ALPHA = a * glow;
	}
}
