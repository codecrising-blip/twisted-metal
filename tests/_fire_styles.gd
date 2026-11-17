extends SceneTree
## Scratch (round 18): film the four foam-fire looks (FoamFire.LOOKS) for the owner to pick from.
## Run with --fixed-fps 30. args: look(0-3) scene out_dir frames every
##   park   Sweet Tooth parked, seen from the front three-quarter, fire on the engine cover
##   drive  Outlaw driving an S-curve, seen from behind (the TMB view): the fire swings through the turns
##   spot   the fire left on the ground where a car blew apart
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var look := int(args[0])
	var scene := args[1]
	var out := args[2]
	var frames := int(args[3])
	var every := int(args[4]) if args.size() > 4 else 1
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 5:
		await process_frame
	main.hud.visible = false
	var cam: ChaseCamera = main.camera
	cam.target = null
	var player: Vehicle = main.player
	var e: Vehicle = main.enemies[0]
	var car: Vehicle = player if scene == "park" else e
	for v: Vehicle in [player] + main.enemies:
		v.controller = null
		v.invulnerable_time = 0.0 # no spawn-protection blinking
		if v != car or scene == "spot":
			v.global_position = Vector3(30, 80, 30)
			v.freeze = true
	var base := LosAngelesArena.ground(-40, 40)
	var start := base if scene != "drive" else base + Vector3(40, 0, 0)
	if scene != "spot":
		car.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(90)), start + Vector3(0, 0.05, 0)) # faces -X
	for i in 20:
		await physics_frame
	car._visual.visible = true # it may have been caught in a spawn-protection blink
	var fire: FoamFire
	if scene == "spot":
		fire = FoamFire.spot(main, base, Vector3(2.2, 1.6, 5.0), look)
	else:
		fire = FoamFire.on_hood(car, look)
	fire.on = true
	var clock := [0.0]
	if scene == "drive":
		var drive := func() -> void:
			if not is_instance_valid(car):
				return
			clock[0] += 1.0 / 30.0
			var yaw := deg_to_rad(90) + 0.75 * sin(clock[0] * 1.4) # an S-curve
			var basis := Basis(Vector3.UP, yaw)
			var dir := -basis.z
			car.global_basis = basis
			car.linear_velocity = Vector3(dir.x * 14.0, car.linear_velocity.y, dir.z * 14.0)
			car.angular_velocity = Vector3.ZERO
		physics_frame.connect(drive)
	var layer := CanvasLayer.new()
	var label := Label.new()
	label.text = FoamFire.LOOKS[look].name
	label.position = Vector2(24, 18)
	label.add_theme_font_size_override("font_size", 40)
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 10)
	layer.add_child(label)
	root.add_child(layer)
	cam.fov = 55.0
	for i in 24: # let it flare up
		await physics_frame
	var n := 0
	var cam_at := Vector3.INF
	for i in frames:
		var p := car.global_position
		if scene == "park":
			cam.global_position = p + Vector3(-7.5, 3.0, 5.5)
			cam.look_at(p + Vector3(-1.2, 1.8, 0))
		elif scene == "spot":
			cam.global_position = base + Vector3(-6, 3.2, 9)
			cam.look_at(base + Vector3(0, 1.6, 0))
		else:
			var fwd := -car.global_basis.z
			fwd.y = 0.0
			var want := p - fwd.normalized() * 9.0 + Vector3(0, 3.6, 0)
			cam_at = want if cam_at == Vector3.INF else cam_at.lerp(want, 0.12)
			cam.global_position = cam_at
			cam.look_at(p + fwd.normalized() * 3.0 + Vector3(0, 1.4, 0))
		await RenderingServer.frame_post_draw
		if i % every == 0:
			root.get_viewport().get_texture().get_image().save_png("%s/f%03d.png" % [out, n])
			n += 1
	quit()
