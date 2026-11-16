// The energy shield (round 17, the owner's Head-On reference, shield_headon_pick.mp4): not lines and
// not a bubble. The car's body is coated in a solid, glossy forest-green layer that hugs its shape,
// with the car's own details (dirt, panel lines) faintly showing through. A blocked hit lights a hot
// yellow-lime patch where it landed that spreads a little and fades back to green (the car also
// throws sparks there, Vehicle._shield_hit). Used as the body meshes' material_overlay; Vehicle
// drives `strength` (fade in with a bright pulse, blink before it ends) and the hit uniforms.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, shadows_disabled;

uniform vec4 coat : source_color = vec4(0.11, 0.53, 0.2, 1.0); // forest green (#228B22), nudged blue: LA's warm light turned it olive
uniform vec4 hit_tint : source_color = vec4(0.95, 1.0, 0.3, 1.0); // hot yellow-lime where a hit lands
uniform float strength = 1.0; // 0 = off, 1 = on, above 1 = a brighter flash (switch-on, blinks)
uniform float cover = 0.8; // how much of the paint it hides: the car's details faintly show through
uniform float grow = 0.012; // metres outside the body (keeps it off the paint)
uniform mat4 car_inv; // world -> the car's own space (it faces -Z, Y up)
uniform vec3 hit_pos = vec3(0.0, -100.0, 0.0); // the last blocked hit, car space
uniform float hit_age = 9.0; // seconds since that hit
uniform float hit_radius = 1.4;

varying vec3 local;

void vertex() {
	VERTEX += NORMAL * grow;
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	local = (car_inv * vec4(world, 1.0)).xyz;
}

void fragment() {
	float on = clamp(strength, 0.0, 1.0);
	float flash = max(strength - 1.0, 0.0);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	// The hit patch: grows from the impact point and cools back to green in about half a second.
	float r = hit_radius * (0.55 + hit_age * 2.0);
	float spot = (1.0 - smoothstep(r * 0.3, r, distance(local, hit_pos))) * exp(-hit_age * 4.0);
	vec3 col = mix(coat.rgb, coat.rgb * 1.5 + 0.03, fres); // lighter green at the grazing edges
	col = mix(col, hit_tint.rgb, clamp(spot, 0.0, 1.0));
	ALBEDO = col;
	ROUGHNESS = 0.22; // glossy
	SPECULAR = 0.7;
	EMISSION = coat.rgb * (0.14 + flash * 1.2) + hit_tint.rgb * spot * 1.3;
	ALPHA = clamp(cover * on + spot * 0.3 + flash * 0.1, 0.0, 1.0);
}
