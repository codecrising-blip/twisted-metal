extends SceneTree
## Scratch (round 18): does a CPUParticles3D leave a stuck dark puff at its emitter? Four smoke emitters in a
## row over a light floor: 0 added emitting, 1 switched on later, 2 local_coords, 3 switched on later + local.
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := OS.get_cmdline_user_args()[0]
	var w := Node3D.new()
	root.add_child(w)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.8, 0.75, 0.65)
	w.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	w.add_child(sun)
	var cam := Camera3D.new()
	w.add_child(cam)
	cam.position = Vector3(0, 2.5, 9)
	cam.look_at(Vector3(0, 2, 0))
	var late: Array = []
	# 0 as built, 1 preprocess, 2 no billboard, 3 shader that drops never-emitted particles (opaque black)
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform sampler2D tex : source_color, filter_linear;
void vertex() {
	mat4 mat_world = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	mat_world = mat_world * mat4(vec4(cos(INSTANCE_CUSTOM.x), -sin(INSTANCE_CUSTOM.x), 0.0, 0.0), vec4(sin(INSTANCE_CUSTOM.x), cos(INSTANCE_CUSTOM.x), 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat_world;
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	if (COLOR.a > 0.999 && COLOR.r + COLOR.g + COLOR.b < 0.002) {
		VERTEX = vec3(0.0); // a never-emitted particle (Compatibility draws them opaque black): collapse it
	}
}
void fragment() {
	vec4 t = texture(tex, UV);
	ALBEDO = t.rgb * COLOR.rgb;
	ALPHA = t.a * COLOR.a;
}
"""
	# 0 off and never started, 1 off + preprocess then started, 2 one-shot explosiveness 0.8, 3 one-shot 1.0
	for k in 4:
		var p := FxKit.smoke(1.0, 20)
		if k <= 1:
			p.emitting = false
		if k == 1:
			p.preprocess = p.lifetime
			late.append(p)
		if k >= 2:
			p.one_shot = true
			p.explosiveness = 0.8 if k == 2 else 1.0
			p.lifetime = 4.0
		p.position = Vector3(-4.5 + k * 3.0, 1.0, 0)
		w.add_child(p)
	for i in 10:
		await process_frame
	for p: CPUParticles3D in late:
		p.emitting = true
	for i in 40:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(out)
	quit()
