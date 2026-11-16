extends SceneTree
## Scratch: put the player at a spot (x,y,z,yaw_deg) and shoot the chase camera. args: x,y,z,yaw out.png
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var p := (args[0] as String).split(",")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 5:
		await process_frame
	var player: Vehicle = main.player
	player.controller = null
	for e: Vehicle in main.enemies:
		e.controller = null
		e.global_position = Vector3(0, 80, 0)
		e.freeze = true
	player.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(float(p[3]))), Vector3(float(p[0]), float(p[1]), float(p[2])))
	for i in 120:
		await process_frame
	print("player at ", player.global_position)
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(args[1])
	quit()
