extends SceneTree
## Scratch: frames of the shield field on Outlaw in ONE run (the shader's TIME runs on), for a GIF.
## Run with --fixed-fps 30 so every frame is 1/30 s. args: out_dir frames [hit_at]
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 5:
		await process_frame
	var player: Vehicle = main.player
	var e: Vehicle = main.enemies[0]
	var base := LosAngelesArena.ground(-40, 40)
	player.global_position = Vector3(0, -200, 0)
	player.freeze = true
	e.controller = null
	e.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(30)), base + Vector3(0, 0.05, 0))
	main.hud.visible = false
	var cam: ChaseCamera = main.camera
	cam.target = null
	for i in 5:
		await process_frame
	e.energy = 100.0
	e.energy_move("shield")
	cam.global_position = base + Vector3(-3.6, 2.4, 6.2)
	cam.look_at(base + Vector3(0, 1.0, 0))
	cam.fov = 60.0
	var cam_xf := cam.global_transform
	var n := int(args[1])
	var hit_at := int(args[2]) if args.size() > 2 else -1
	for i in n:
		e.shield_time = maxf(e.shield_time, 1.5) # hold it (no end blink) while recording
		cam.global_transform = cam_xf
		if i == hit_at:
			e.hit_react(e.global_basis * Vector3(0.6, 0, 0.8).normalized(), 30.0)
		await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png("%s/c%03d.png" % [args[0], i])
	quit()
