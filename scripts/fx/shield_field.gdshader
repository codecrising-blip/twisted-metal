// The energy shield (round 16, the owner's TMB reference: the shield on Crazy 8's car, NOT his
// electric special). A magnetic field drawn over the car's own shape, a little outside it: thin
// darkish royal-blue field lines that run like a conveyor belt from the tail of the car over it to
// the nose, all the time the shield is up. They are not ruler-straight: one side runs a little ahead
// of the other and that slowly swaps over, with the faintest bow (owner: "6 on a scale where 0 is
// straight and 100 is a U-shaped zigzag"). Seen from behind they are near-horizontal lines climbing
// the tail and sliding forward over the roof. Used as the car meshes' material_overlay (alpha
// blended, so the lines keep their own dark blue instead of washing out to white).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.1, 0.2, 0.62, 1.0); // darkish royal blue
uniform vec4 rim_tint : source_color = vec4(0.22, 0.38, 0.95, 1.0);
uniform float strength = 1.0; // 0 = off; fades in, sputters at the end, flares on a hit
uniform float lines_per_m = 6.5;
uniform float speed = 2.2; // metres per second, tail to nose
uniform float grow = 0.05; // metres outside the body
uniform float half_width = 1.1; // the car's half width (metres)
uniform float tilt = 0.08; // metres one side runs ahead of the middle at the most
uniform float bow = 0.03; // metres of curve across the width at the most
uniform mat4 car_inv; // world -> the car's own space (it faces -Z, Y up)

varying float run; // distance along the belt: up the tail, then forward over the car

void vertex() {
	VERTEX += NORMAL * grow;
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 local = (car_inv * vec4(world, 1.0)).xyz;
	float across = clamp(local.x / half_width, -1.0, 1.0);
	run = -local.z + local.y * 0.35
		+ tilt * across * sin(TIME * 1.3)
		+ bow * across * across * sin(TIME * 0.9 + 1.0);
}

void fragment() {
	float band = fract(run * lines_per_m - TIME * speed * lines_per_m);
	float line = smoothstep(0.0, 0.08, band) * (1.0 - smoothstep(0.18, 0.32, band));
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	ALBEDO = mix(tint.rgb, rim_tint.rgb, rim * 0.6);
	ALPHA = clamp((0.1 + line * 0.75 + rim * 0.35) * strength, 0.0, 1.0);
}
