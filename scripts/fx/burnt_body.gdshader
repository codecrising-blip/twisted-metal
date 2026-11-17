// A driver burnt beyond recognition (round 17): blackened, cracked skin with embers glowing in the
// cracks while the fire is on them (`heat` 1), cooling to plain charcoal when it goes out (0).
shader_type spatial;
render_mode cull_back;

uniform float heat = 1.0; // 1 = burning, embers glowing; 0 = burnt out
uniform vec4 ember : source_color = vec4(1.0, 0.36, 0.06, 1.0);

varying vec3 opos;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	opos = VERTEX;
}

void fragment() {
	float n = vnoise(opos * 9.0) * 0.6 + vnoise(opos * 23.0) * 0.4;
	ALBEDO = mix(vec3(0.025, 0.02, 0.018), vec3(0.12, 0.075, 0.05), n); // charcoal with burnt-brown patches
	ROUGHNESS = 0.92;
	SPECULAR = 0.2;
	float cracks = smoothstep(0.6, 0.7, vnoise(opos * 15.0 + vec3(0.0, TIME * 0.25, 0.0)));
	float flicker = 0.55 + 0.45 * sin(TIME * 13.0 + opos.y * 21.0 + opos.x * 9.0);
	EMISSION = ember.rgb * cracks * heat * flicker * 2.6;
}
