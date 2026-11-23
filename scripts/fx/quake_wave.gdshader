// Thumper's Earthquake Slam (round 29): the sonic boom rolling out along the ground. Drawn on a flat disc
// (UV centre = the car): a hot blue-white front at radius `front` (0..1 of the disc), trailing ripples
// behind it, cracks of light breaking it up, everything fading with `fade`. `wall` = 1 draws the open cylinder
// band instead (UV.y up the wall): the front standing up off the ground, fading toward its top.
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform float front = 0.0;
uniform float fade = 1.0;
uniform float wall = 0.0;
uniform vec3 tint : source_color = vec3(0.18, 0.48, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec3 col;
	float a;
	if (wall > 0.5) {
		float ang = UV.x * 40.0;
		float n = noise(vec2(ang, UV.y * 3.0 - TIME * 6.0));
		float up = 1.0 - UV.y;
		a = pow(up, 2.2) * (0.35 + 0.35 * n) * fade;
		col = mix(tint, vec3(0.7, 0.88, 1.0), pow(up, 6.0));
	} else {
		vec2 d = UV * 2.0 - 1.0;
		float r = length(d);
		float ang = atan(d.y, d.x);
		float n = noise(vec2(ang * 6.0, r * 14.0 - TIME * 3.0));
		float band = exp(-pow((r - front) / 0.035, 2.0));                    // the front itself
		float trail = smoothstep(front, front - 0.35, r) * step(r, front);   // light behind it
		float ripples = (0.5 + 0.5 * sin((front - r) * 70.0)) * trail;
		float cracks = smoothstep(0.82, 0.95, noise(vec2(ang * 22.0, r * 5.0))) * trail;
		a = (band * (0.75 + 0.3 * n) + ripples * 0.16 + cracks * 0.45 + trail * 0.06) * fade * step(r, 1.0);
		col = mix(tint, vec3(0.75, 0.9, 1.0), clamp(band * 0.5 + cracks * 0.4, 0.0, 1.0));
	}
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0);
}
