// Thumper's Megafire (round 29, owner: "a mid ground between a laser beam and an ordinary fire", TM4's Super
// Thumper): drawn on three crossed ribbons along the beam (UV.x across, UV.y from the grille to the tip).
// A white-hot core line, a yellow-orange glazing body streaming forward fast, red ragged edges and a torn tip.
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform float intensity = 1.0;
uniform float flow = 11.0;       // how fast the streaks run toward the tip (metres a second, roughly)
uniform float length_m = 16.0;   // the beam's length now (the tip is cut short at walls)
uniform float ignite = 1.0;      // 0 -> 1 while the beam shoots out: the tip runs from the grille to the end
uniform float slice = 0.0;       // 1 = the cross-section quads (UV2.x = their place along the beam): seen from behind

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int k = 0; k < 4; k++) {
		s += a * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return s;
}

void fragment() {
	vec3 outc;
	float outa;
	float tt = TIME * flow;
	if (slice > 0.5) {
		// a cross-section of the fire, facing back at the car: an oval of flame torn at its rim, hot inside
		float sv = UV2.x;
		vec2 d = UV * 2.0 - 1.0;
		float r = length(d);
		float ang = atan(d.y, d.x);
		float sn = fbm(vec2(ang * 2.2 + sv * 9.0, r * 3.0 - tt * 0.5 + sv * 4.0));
		float sh = smoothstep(1.0, 0.35, r + (sn - 0.5) * 0.7);
		float shot = clamp(ignite, 0.0, 1.0);
		float there = 1.0 - smoothstep(0.75 * shot, shot, sv);
		float hot = smoothstep(0.55, 0.0, r) * (1.0 - sv * 0.7);
		vec3 sc = mix(vec3(0.95, 0.22, 0.04), vec3(1.0, 0.56, 0.12), smoothstep(0.2, 0.75, sh));
		outc = mix(sc, vec3(1.0, 0.9, 0.6), hot);
		outa = sh * there * (0.38 + 0.3 * sn) * (1.0 - sv * 0.4);
	} else {
		float v = UV.y;
		float u = UV.x * 2.0 - 1.0;
		float m = v * length_m;
		float n = fbm(vec2(UV.x * 3.5, m * 0.42 - tt * 0.42));            // broad licks
		float n2 = fbm(vec2(UV.x * 9.0 + 3.1, m * 1.3 - tt * 1.25));      // fine streaks, faster
		float edge = 1.0 - abs(u);
		// ragged sides, more ragged toward the tip
		float body = smoothstep(0.0, 0.22 + 0.2 * v, edge + (n - 0.5) * (0.35 + 0.55 * v));
		// the tip tears off in tongues; while igniting it runs out from the grille
		float reach = clamp(ignite, 0.0, 1.0);
		float tip = 1.0 - smoothstep(0.72 * reach, reach, v + (n2 - 0.5) * 0.28);
		float root = smoothstep(0.0, 0.05, v);
		// the laser-like core: a hot line down the middle, flickering in the fine streaks
		float core = pow(clamp(edge, 0.0, 1.0), 6.0) * (1.0 - v * 0.55) * (0.75 + 0.5 * n2);
		float heat = clamp(body * (0.5 + 0.7 * n2) + (1.0 - v) * 0.15, 0.0, 1.0);
		vec3 cool = vec3(0.95, 0.24, 0.04);
		vec3 mid = vec3(1.0, 0.55, 0.1);
		vec3 hotc = vec3(1.0, 0.86, 0.45);
		vec3 white = vec3(1.0, 0.97, 0.88);
		vec3 col = mix(cool, mid, smoothstep(0.15, 0.55, heat * (0.6 + edge)));
		col = mix(col, hotc, smoothstep(0.55, 0.95, heat * edge * 1.4));
		outc = mix(col, white, clamp(core * 1.4, 0.0, 1.0));
		outa = body * tip * root * (0.6 + 0.4 * n) * 0.9;
	}
	ALBEDO = outc * (0.75 + 0.35 * intensity);
	ALPHA = clamp(outa * intensity, 0.0, 1.0); // blended, not added: the flame keeps its colour over bright ground
}
