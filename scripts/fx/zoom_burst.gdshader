// Darkside Slam (round 29, owner, from TMB's ram clips): the screen "shrinks" as the truck tears off: a radial
// zoom blur from the centre, the edges dragged in and darkened, fading out over the burst.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float strength = 0.0;

void fragment() {
	vec2 c = vec2(0.5, 0.52);
	vec2 d = SCREEN_UV - c;
	vec3 acc = vec3(0.0);
	for (int i = 0; i < 12; i++) {
		float t = float(i) / 11.0;
		acc += texture(screen_tex, c + d * (1.0 - strength * 0.22 * t)).rgb;
	}
	acc /= 12.0;
	float r = length(d * vec2(1.6, 1.0));
	acc *= 1.0 - strength * 0.45 * smoothstep(0.15, 0.75, r);
	COLOR = vec4(acc, clamp(strength * 1.6, 0.0, 1.0) * smoothstep(0.02, 0.25, r));
}
