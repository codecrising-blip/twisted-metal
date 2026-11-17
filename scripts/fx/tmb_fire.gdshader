// Fire the Twisted Metal: Black way (round 17, the owner's standard for the whole game, from his TMB
// clips): not soft round blobs but a sheet of long thin streaky licks, deep red at the roots, orange,
// yellow at the hottest strands, racing upwards and flickering fast, ragged at the top. Each sheet
// stands upright facing the camera (turning about the world's up axis) and leans away from the way
// its owner moves, so a running body trails its flames. TmbFire builds and drives the sheets.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, skip_vertex_transform, fog_disabled;

uniform float intensity = 1.0; // 0 = out .. 1 = full; it also shortens the flames
uniform float speed = 2.4; // how fast the streaks climb
uniform float seed = 0.0; // each sheet differs
uniform vec3 lean = vec3(0.0); // world metres the top is swept aside (against the motion)
uniform float forward = 0.28; // metres the sheet is pulled toward the camera
uniform vec4 deep : source_color = vec4(0.5, 0.025, 0.0, 1.0);
uniform vec4 mid : source_color = vec4(0.95, 0.26, 0.02, 1.0);
uniform vec4 hot : source_color = vec4(1.0, 0.66, 0.2, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	// Upright, facing the camera about world up, keeping the node's scale and position.
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	right = normalize(vec3(right.x, 0.0, right.z) + vec3(0.0001, 0.0, 0.0));
	float up = 1.0 - UV.y; // 0 at the base, 1 at the tip
	vec3 world = MODEL_MATRIX[3].xyz + right * VERTEX.x * sx + vec3(0.0, VERTEX.y * sy, 0.0) + lean * up * up;
	// Pulled toward the camera so it burns over the body it stands in, not hidden behind its front.
	world += normalize(INV_VIEW_MATRIX[3].xyz - world) * forward;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = (VIEW_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz;
}

void fragment() {
	float h = 1.0 - UV.y; // 0 base .. 1 top
	float t = TIME * speed;
	// Streaks: noise stretched along the height (fine across, coarse up), climbing.
	float n = vnoise(vec2(UV.x * 13.0 + seed, h * 2.3 - t)) * 0.5 + vnoise(vec2(UV.x * 31.0 - seed * 1.7, h * 5.0 - t * 1.7)) * 0.3
		+ vnoise(vec2(UV.x * 57.0 + seed * 2.3, h * 9.0 - t * 2.5)) * 0.2;
	// A tongue of fire: wide at the root, narrowing and wavering towards a ragged tip; the root fades
	// in softly (no hard bottom edge) and a dying fire is short.
	float waver = (vnoise(vec2(h * 3.0 - t * 0.8, seed)) - 0.5) * 0.22 * h;
	float half_w = 0.42 * (1.0 - 0.72 * h);
	float side = half_w - abs(UV.x - 0.5 + waver);
	float reach = mix(0.45, 1.0, clamp(intensity, 0.0, 1.0));
	float shape = smoothstep(0.0, 0.1, side) * smoothstep(0.0, 0.14, h) * (1.0 - smoothstep(reach * 0.45, reach, h));
	float f = n * shape * 1.5 - h * 0.3;
	float a = smoothstep(0.22, 0.46, f);
	float heat = clamp(f * 1.5 - h * 0.3, 0.0, 1.0);
	vec3 c = mix(deep.rgb, mid.rgb, smoothstep(0.15, 0.6, heat));
	c = mix(c, hot.rgb, smoothstep(0.78, 1.0, heat)); // only the hottest strands go yellow
	ALBEDO = c;
	ALPHA = clamp(a * min(intensity * 1.4, 1.0), 0.0, 1.0);
}
