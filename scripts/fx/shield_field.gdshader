// The energy shield (round 17, owner): a forest-green MAGNETIC FIELD around the whole car, wheels
// included (Head-On leaving the tyres out was a flaw). Not a coat of paint: a faint green aura a few
// centimetres off the car with glowing field lines that never stop moving. The lines run roughly from
// the tail over the car to the nose like the round-16 stripes, but slow noise fields keep bending them,
// a second, finer set of lines overtakes the first, patches of lines brighten and dim, and surges roll
// along the car now and then, so it never looks the same twice. A blocked hit lights a hot yellow-lime
// patch where it landed (Vehicle._shield_hit also throws sparks there). Used as material_overlay;
// Vehicle drives `strength` (bright pulse on switch-on, blinks before it ends) and the hit uniforms.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;

uniform vec4 field : source_color = vec4(0.11, 0.53, 0.2, 1.0); // forest green (nudged blue for LA's warm light)
uniform vec4 core : source_color = vec4(0.5, 1.0, 0.55, 1.0); // the bright heart of a field line
uniform vec4 hit_tint : source_color = vec4(0.95, 1.0, 0.3, 1.0); // hot yellow-lime where a hit lands
uniform float strength = 1.0; // 0 = off, 1 = on, above 1 = a brighter flash (switch-on, blinks)
uniform float grow = 0.045; // metres the field floats off the car
uniform float lines_per_m = 3.0;
uniform float speed = 1.8; // metres per second, tail to nose
uniform float warp = 0.45; // metres the noise bends the lines
uniform mat4 car_inv; // world -> the car's own space (it faces -Z, Y up)
uniform vec3 hit_pos = vec3(0.0, -100.0, 0.0); // the last blocked hit, car space
uniform float hit_age = 9.0; // seconds since that hit
uniform float hit_radius = 1.4;

varying vec3 local;

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

// A thin glowing line on every whole number of `phase`.
float line(float phase, float width) {
	float b = fract(phase);
	return 1.0 - smoothstep(0.0, width, min(b, 1.0 - b));
}

void vertex() {
	VERTEX += NORMAL * grow;
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	local = (car_inv * vec4(world, 1.0)).xyz;
}

void fragment() {
	float t = TIME;
	vec3 p = local;
	float on = clamp(strength, 0.0, 1.0);
	float flash = max(strength - 1.0, 0.0);
	// Two slowly drifting noise fields bend the lines (bounded, so they wander but never tear apart).
	float n1 = vnoise(p * 0.9 + vec3(0.0, t * 0.35, -t * 0.6));
	float n2 = vnoise(p * 1.8 + vec3(t * 0.5, -t * 0.2, -t * 0.9) + 7.3);
	float run = -p.z + p.y * 0.35;
	// Main lines: tail to nose, bent and thickening/thinning as they go.
	float a = line((run + (n1 - 0.5) * 2.0 * warp) * lines_per_m - t * speed * lines_per_m, 0.07 + 0.07 * n2);
	// Finer, faster lines bent the other way: they overtake and cross the main ones.
	float b = line((run + (n2 - 0.5) * 2.0 * warp + p.x * 0.25) * lines_per_m * 1.7 - t * speed * 1.45 * lines_per_m * 1.7, 0.06) * 0.55;
	// Patches of the field brighten and dim, and now and then a surge rolls along the car.
	float flicker = 0.35 + 0.65 * vnoise(p * 2.4 + vec3(0.0, 0.0, -t * 3.0));
	float surge = smoothstep(0.7, 1.0, vnoise(vec3(p.z * 0.5 + t * 2.2, t * 0.6, 3.1)));
	float lines = clamp((a + b) * flicker * (1.0 + surge * 1.2), 0.0, 1.5);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	// The hit patch: grows from the impact point and cools back to green in about half a second.
	float r = hit_radius * (0.55 + hit_age * 2.0);
	float spot = (1.0 - smoothstep(r * 0.3, r, distance(p, hit_pos))) * exp(-hit_age * 4.0);
	vec3 col = mix(field.rgb, core.rgb, clamp(lines * 0.75 + rim * 0.2, 0.0, 1.0));
	col = mix(col, hit_tint.rgb, clamp(spot, 0.0, 1.0));
	ALBEDO = col * (1.0 + flash * 0.5);
	ALPHA = clamp((0.14 + rim * 0.45 + lines * 0.8 + surge * 0.08) * on + spot * 0.6 + flash * 0.25, 0.0, 1.0);
}
