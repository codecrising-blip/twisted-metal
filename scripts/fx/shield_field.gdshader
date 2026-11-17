// The energy shield (round 17, owner's pick "D" of four: "PERFECT, 20/10"): a forest-green force
// field hovering about 17 cm off the car, wheels included. The car's own meshes are drawn again a little
// bigger, scaled about the car's centre in car space (not pushed along normals, which would crack the
// shell at hard edges), so it reads as a glowing hull around the car: bright edges, a faint body, slow
// broad waves rolling tail to nose with finer lines inside, bent by drifting noise. A blocked hit lights
// a hot yellow-lime patch where it landed (Vehicle._shield_hit also throws sparks there). Used as
// material_overlay; Vehicle drives `strength` (bright pulse on switch-on, blinks before it ends), the
// car's frame (`car_inv`) and the hit uniforms.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;

uniform vec4 field : source_color = vec4(0.11, 0.53, 0.2, 1.0); // forest green (nudged blue for LA's warm light)
uniform vec4 core : source_color = vec4(0.5, 1.0, 0.55, 1.0); // the bright heart of the waves and edges
uniform vec4 hit_tint : source_color = vec4(0.95, 1.0, 0.3, 1.0); // hot yellow-lime where a hit lands
uniform float strength = 1.0; // 0 = off, 1 = on, above 1 = a brighter flash (switch-on, blinks)
uniform float gap = 0.17; // metres the shell floats off the car
uniform vec3 half_size = vec3(1.1, 0.9, 2.5); // the car's half extents (Vehicle sets them)
uniform mat4 car_inv; // world -> the car's own space (it faces -Z, Y up)
uniform vec3 hit_pos = vec3(0.0, -100.0, 0.0); // the last blocked hit, car space
uniform float hit_age = 9.0; // seconds since that hit
uniform float hit_radius = 1.4;

varying vec3 local;

float hash(vec3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float vnoise(vec3 x) { vec3 i = floor(x); vec3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z); }
float line(float phase, float width) { float b = fract(phase); return 1.0 - smoothstep(0.0, width, min(b, 1.0 - b)); }
float hit_spot(vec3 p) { float r = hit_radius * (0.55 + hit_age * 2.0); return (1.0 - smoothstep(r * 0.3, r, distance(p, hit_pos))) * exp(-hit_age * 4.0); }

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 l = (car_inv * vec4(w, 1.0)).xyz;
	vec3 c = vec3(0.0, half_size.y, 0.0);
	l = c + (l - c) * (vec3(1.0) + vec3(gap) / half_size);
	local = l;
	VERTEX = (inverse(MODEL_MATRIX) * (inverse(car_inv) * vec4(l, 1.0))).xyz;
}
void fragment() {
	float t = TIME; vec3 p = local;
	float n1 = vnoise(p * 0.8 + vec3(0.0, t * 0.3, -t * 0.5));
	float run = -p.z + p.y * 0.35 + (n1 - 0.5) * 0.8;
	float wave = line(run * 1.1 - t * 1.4 * 1.1, 0.22) * 0.7;
	float fine = line((run + p.x * 0.3) * 4.0 - t * 2.2 * 4.0, 0.05) * 0.35;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	float lines = (wave + fine) * (0.5 + 0.5 * vnoise(p * 2.0 + vec3(0.0, 0.0, -t * 2.5)));
	float s = hit_spot(p); float on = clamp(strength, 0.0, 1.0); float flash = max(strength - 1.0, 0.0);
	vec3 col = mix(mix(field.rgb, core.rgb, clamp(lines * 0.7 + rim * 0.5, 0.0, 1.0)), hit_tint.rgb, clamp(s, 0.0, 1.0));
	ALBEDO = col * (1.0 + flash * 0.5);
	ALPHA = clamp((0.1 + rim * 0.8 + lines * 0.6) * on + s * 0.6 + flash * 0.25, 0.0, 1.0);
}
