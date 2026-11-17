extends SceneTree
## Scratch (round 17): film the burning-driver deaths in one run each, for a look.
## Run with --fixed-fps 30. args: scenario out_dir frames every
##   ground      Outlaw destroyed on the ground: the driver climbs out burning, runs, kneels, crawls, dies
##   air         Outlaw destroyed in the air: the driver is blasted out and lands dead
##   windshield  the player runs a burning driver down head-on at speed
##   under       the player runs a burning driver down slowly
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var scenario := args[0]
	var out := args[1]
	var frames := int(args[2])
	var every := int(args[3]) if args.size() > 3 else 1
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 5:
		await process_frame
	var player: Vehicle = main.player
	var e: Vehicle = main.enemies[0]
	main.hud.visible = false
	var cam: ChaseCamera = main.camera
	cam.target = null
	var base := LosAngelesArena.ground(-40, 40)
	for v: Vehicle in main.enemies:
		if v != e:
			v.controller = null
			v.global_position = Vector3(0, 80, 0)
			v.freeze = true
	e.controller = null
	player.controller = null
	player.global_position = Vector3(30, 60, 30)
	player.freeze = true
	e.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(90)), base + Vector3(0, 0.05, 0))
	var cam_at := base + Vector3(-9, 5, 14)
	var look := base + Vector3(-4, 0.8, 0)
	for i in 20:
		await physics_frame
	match scenario:
		"ground", "close":
			e.last_attacker = player
			e.take_damage(9999.0, player)
			cam_at = base + Vector3(2, 6, 16)
			look = base + Vector3(-6, 0.5, 0)
		"air":
			e.global_position = base + Vector3(0, 6, 0)
			for i in 3:
				await physics_frame
			e.take_damage(9999.0, null)
			cam_at = base + Vector3(-2, 5, 18)
			look = base + Vector3(0, 2, 0)
		"windshield", "under":
			e.global_position = Vector3(0, -300, 0)
			e.freeze = true
			var d := BurningDriver.new()
			d.position = base + Vector3(0, 0, -6)
			d._heading = Vector3.BACK
			main.add_child(d)
			d._enter(BurningDriver.KNEEL) # on the knees: a still target, so the car surely meets them
			player.freeze = false
			var spd := 20.0 if scenario == "windshield" else 5.5
			var start := base + Vector3(0.3, 0.1, -6 - (34.0 if scenario == "windshield" else 9.0))
			player.global_transform = Transform3D(Basis(Vector3.UP, PI), start) # facing +Z, towards the driver
			player.linear_velocity = Vector3(0, 0, spd)
			player.speed = spd
			var keep := func() -> void:
				if is_instance_valid(player) and player.linear_velocity.z < spd * 0.9:
					player.linear_velocity.z = spd
			physics_frame.connect(keep)
			cam_at = base + Vector3(-9, 3.5, -3)
			look = base + Vector3(0, 1.0, -5)
	cam.global_position = cam_at
	cam.look_at(look)
	cam.fov = 55.0
	var n := 0
	var follow: Node3D = null
	for i in frames:
		if scenario in ["close", "windshield", "under", "air"]:
			if follow == null or not is_instance_valid(follow) or (follow is BurningDriver and (follow as BurningDriver).state == BurningDriver.DEAD and scenario == "windshield"):
				var ds := get_nodes_in_group(&"drivers")
				for c in main.get_children():
					if c is DriverCorpse:
						ds = [c]
				follow = ds[0] if not ds.is_empty() else follow
			if follow:
				var p: Vector3 = follow.global_position
				cam_at = cam_at.lerp(p + Vector3(-3.2, 2.2, 3.2), 0.2) if i > 0 else p + Vector3(-3.2, 2.2, 3.2)
				look = p + Vector3(0, 0.8, 0)
		cam.global_position = cam_at
		cam.look_at(look)
		await RenderingServer.frame_post_draw
		if i % every == 0:
			root.get_viewport().get_texture().get_image().save_png("%s/f%03d.png" % [out, n])
			n += 1
	quit()
