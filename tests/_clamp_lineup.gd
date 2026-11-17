extends SceneTree
## Scratch (round 19): the four wheel clamp candidates (assets/models/wheel_clamps.glb) on the front right
## wheel of four cars in a row. Run with `-- full`. args: view(row|close_a..d) out.png


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var view := args[0]
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 5:
		await process_frame
	main.hud.visible = false
	var cars: Array[Vehicle] = [main.player]
	for e: Vehicle in main.enemies:
		cars.append(e)
	var base := LosAngelesArena.ground(-40, 40)
	var west := Basis(Vector3.UP, deg_to_rad(90)) # facing -X: the right side looks at -Z
	for k in cars.size():
		var v := cars[k]
		v.controller = null
		v.invulnerable_time = 0.0
		v._visual.visible = true
		if k < 4:
			v.global_transform = Transform3D(west, LosAngelesArena.ground(base.x + (k - 1.5) * 8.0, base.z) + Vector3(0, 0.1, 0))
		else:
			v.global_position = Vector3(0, 80, 0)
			v.freeze = true
	for i in 40:
		for k in 4:
			cars[k].linear_velocity = Vector3.ZERO
			cars[k].angular_velocity = Vector3.ZERO
		await physics_frame
	for k in 4:
		cars[k].freeze = true # parked for the photo
		WheelClamp.style = "abcd"[k]
		cars[k].shield_time = 0.0
		cars[k].invulnerable_time = 0.0
		var ok := cars[k].clamp_for(5.0, cars[k].global_position + cars[k].global_basis.x * 2.0)
		var bt: Node3D = cars[k]._clamp_boot
		print(cars[k].car_id, " clamp ", ok, " boot ", bt.global_position if bt else Vector3.ZERO, " car ", cars[k].global_position, " vis ", bt.is_visible_in_tree() if bt else false, " scale ", bt.scale if bt else Vector3.ZERO)
	var cam: ChaseCamera = main.camera
	cam.target = null
	cam.fov = 50.0
	match view:
		"row":
			cam.global_position = base + Vector3(-2.0, 2.4, -14.0)
			cam.look_at(base + Vector3(-1.0, 0.6, 0))
		_:
			var k := "abcd".find(view.substr(6, 1))
			var v := cars[maxi(k, 0)]
			var boot := v._clamp_boot
			var c := boot.global_position
			cam.fov = 40.0
			cam.global_position = c + Vector3(-1.6, 0.9, -3.4)
			cam.look_at(c + Vector3(0, -0.05, 0))
	for i in 25:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(args[1])
	quit()
