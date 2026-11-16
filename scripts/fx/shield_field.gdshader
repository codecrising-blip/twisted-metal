// The energy shield (round 16 fix, the owner's TMB reference: the shield on Crazy 8's car, NOT his
// electric special). A pale blue magnetic field drawn over the car's own shape, a little outside it:
// thin field lines that run like a conveyor belt from the tail of the car over it to the nose, all
// the time the shield is up (owner: "they move from the back of the car to the tip front of it").
// Seen from behind they are horizontal lines climbing the tail and sliding forward over the roof.
// Used as the car meshes' material_overlay, so it hugs every panel, wheel and gun.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.34, 0.6, 1.0, 1.0);
uniform float strength = 1.0; // 0 = off; fades in, sputters at the end, flares on a hit
uniform float lines_per_m = 6.5;
uniform float speed = 2.2; // metres per second, tail to nose
uniform float grow = 0.05; // metres outside the body
uniform mat4 car_inv; // world -> the car's own space (it faces -Z, Y up)

varying float run; // distance along the belt: up the tail, then forward over the car

void vertex() {
	VERTEX += NORMAL * grow;
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 local = (car_inv * vec4(world, 1.0)).xyz;
	run = -local.z + local.y * 0.35;
}

void fragment() {
	float band = fract(run * lines_per_m - TIME * speed * lines_per_m);
	float line = smoothstep(0.0, 0.08, band) * (1.0 - smoothstep(0.18, 0.32, band));
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	ALBEDO = tint.rgb * (0.14 + line * 0.75 + rim * 0.7) * strength;
}
