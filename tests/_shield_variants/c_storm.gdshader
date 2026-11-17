shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;
uniform vec4 field : source_color = vec4(0.11, 0.53, 0.2, 1.0);
uniform vec4 core : source_color = vec4(0.5, 1.0, 0.55, 1.0);
uniform vec4 hit_tint : source_color = vec4(0.95, 1.0, 0.3, 1.0);
uniform float strength = 1.0;
uniform mat4 car_inv;
uniform vec3 hit_pos = vec3(0.0, -100.0, 0.0);
uniform float hit_age = 9.0;
uniform float hit_radius = 1.4;
varying vec3 local;
float hash(vec3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float vnoise(vec3 x) { vec3 i = floor(x); vec3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z); }
float line(float phase, float width) { float b = fract(phase); return 1.0 - smoothstep(0.0, width, min(b, 1.0 - b)); }
float hit_spot(vec3 p) { float r = hit_radius * (0.55 + hit_age * 2.0); return (1.0 - smoothstep(r * 0.3, r, distance(p, hit_pos))) * exp(-hit_age * 4.0); }
void vertex() { VERTEX += NORMAL * 0.045; local = (car_inv * vec4((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz, 1.0)).xyz; }
void fragment() {
	float t = TIME; vec3 p = local;
	float n1 = vnoise(p * 1.6 + vec3(0.0, t * 0.9, -t * 1.4));
	float n2 = vnoise(p * 3.1 + vec3(t * 1.2, -t * 0.6, -t * 1.8) + 7.3);
	float run = -p.z + p.y * 0.35;
	float a = line((run + (n1 - 0.5) * 1.8) * 5.0 - t * 3.2 * 5.0, 0.06 + 0.06 * n2);
	float b = line((run + (n2 - 0.5) * 1.6 + p.x * 0.6) * 8.0 - t * 4.5 * 8.0, 0.05) * 0.6;
	float c = line((p.y * 0.8 + p.x * 0.5 + (n1 - 0.5) * 1.2) * 4.0 + t * 2.0 * 4.0, 0.05) * 0.4;
	float crackle = step(0.975, hash(floor(p * 16.0) + floor(t * 14.0))) * 1.5;
	float flicker = 0.25 + 0.75 * vnoise(p * 4.0 + vec3(0.0, 0.0, -t * 7.0));
	float lines = clamp((a + b + c) * flicker + crackle, 0.0, 1.6);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	float s = hit_spot(p); float on = clamp(strength, 0.0, 1.0); float flash = max(strength - 1.0, 0.0);
	vec3 col = mix(mix(field.rgb, core.rgb, clamp(lines * 0.75 + rim * 0.2, 0.0, 1.0)), hit_tint.rgb, clamp(s, 0.0, 1.0));
	ALBEDO = col * (1.0 + flash * 0.5);
	ALPHA = clamp((0.1 + rim * 0.4 + lines * 0.75) * on + s * 0.6 + flash * 0.25, 0.0, 1.0);
}
