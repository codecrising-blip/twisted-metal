extends SceneTree
## Scratch (round 20): one car model up close. args: id out.png fwd,right,up [fov]
## fwd/right/up = camera offset in the car's frame (metres); looks at the car's middle, 1 m up.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 5:
		await process_frame
	main.hud.visible = false
	var base := Vector3(20.0, 0.0, 30.0) # on the flat pavers of the battleground
	for v: Vehicle in [main.player] + main.enemies:
		v.global_position += Vector3(0, -200, 0)
		v.visible = false
	var model := VehicleModels.build(args[0])
	main.add_child(model)
	model.global_position = LosAngelesArena.ground(base.x, base.z, 0.0)
	model.rotation.y = deg_to_rad(150.0)
	for i in 10:
		await process_frame
	var o := args[2].split(",")
	var c := model.global_position
	var cam: Camera3D = main.camera
	cam.target = null
	cam.global_position = c - model.global_basis.z * float(o[0]) + model.global_basis.x * float(o[1]) + Vector3(0, float(o[2]), 0)
	cam.look_at(c + Vector3(0, 0.9, 0))
	cam.fov = float(args[3]) if args.size() > 3 else 40.0
	for i in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(args[1])
	quit()
