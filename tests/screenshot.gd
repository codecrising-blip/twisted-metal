extends SceneTree
## Renders screenshots of the game for review (needs a display; use xvfb-run on servers).
##   godot --rendering-method gl_compatibility --path . -s tests/screenshot.gd -- <shot> <out.png>
## Shots:
##   gameplay   chase camera after a few seconds of driving and shooting
##   hero       close 3/4 view of the player's car
##   enemies    the four AI cars side by side
##   overview   high view over the whole stage
##   roof       on the tunnel roof, looking at the HOLLYWOOD sign
##   tunnel     inside the twin tunnels
##   cage       the caged super health on its deck, and the overpass
##   center     the fire pit, the burnt building and the power tower
##   pit        close view of the fire pit
##   hill       one of the three jump hills on the road
##   ramp       a ramp up to the raised battleground
##   duel       the player and the first AI car face to face (preview: Sweet Tooth vs Outlaw)
##   car:<id>:<angle>  one car model on its own; angle = front34 | rear34 | side | front | top | low

func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var shot := args[0] if args.size() > 0 else "gameplay"
	var out := args[1] if args.size() > 1 else "screenshot.png"

	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _frames(5)
	var hud: CanvasLayer = main.hud
	var cam: ChaseCamera = main.camera
	var player: Vehicle = main.player

	if shot == "gameplay":
		Input.action_press("accelerate")
		await _frames(70)
		Input.action_press("fire_guns")
		await _frames(25)
	else:
		for v: Vehicle in [player] + main.enemies:
			v.controller = null
		hud.visible = false
		cam.target = null
		await _frames(30)
		match shot:
			"hero":
				_place(cam, player.global_position + Vector3(-6.5, 3.2, -7.5), player.global_position + Vector3(0, 1.6, 0), 50.0)
			"enemies":
				var base := player.global_position + Vector3(14, 0, -18)
				for i in main.enemies.size():
					var e: Vehicle = main.enemies[i]
					var x: float = -9.0 + i * 6.0
					e.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(180 - 12 * (i - 1.5))), LosAngelesArena.ground(base.x + x, base.z, 0.05))
				await _frames(10)
				_place(cam, base + Vector3(0, 3.6, 12.5), base + Vector3(0, 1.0, 0), 60.0)
			"overview":
				# From up here the backdrop (baked at ground level) would look wrong: plain sky instead.
				for we in main.find_children("*", "WorldEnvironment", true, false):
					(we as WorldEnvironment).environment.sky.sky_material = LosAngelesArena.sky_material()
				_place(cam, Vector3(205, 170, 245), Vector3(-5, 0, 5), 62.0)
			"roof":
				_place(cam, Vector3(12, 13.5, -114), Vector3(-10, 22, -200), 65.0)
			"tunnel":
				_place(cam, Vector3(-46, 3.0, -121), Vector3(0, 2.5, -121), 70.0)
			"cage":
				_place(cam, Vector3(92, 28, 10), Vector3(55, 9, -42), 60.0)
			"center":
				_place(cam, Vector3(60, 30, 95), Vector3(-5, 5, -10), 65.0)
			"pit":
				_place(cam, Vector3(0, 17, 36), Vector3(0, 4, 0), 60.0)
			"hill":
				var hill: Dictionary = LosAngelesArena.hills()[1]
				var hp: Vector2 = hill.p
				var hd: Vector2 = hill.d
				var eye := Vector3(hp.x - hd.x * 38.0 - hd.y * 14.0, 6.0, hp.y - hd.y * 38.0 + hd.x * 14.0)
				_place(cam, eye, Vector3(hp.x, 1.5, hp.y), 60.0)
			"ramp":
				var rp: Dictionary = LosAngelesArena.ramp_list()[1]
				var foot: Vector3 = rp.foot
				var side: Vector3 = rp.side
				_place(cam, foot + side * 26.0 + (rp.dir as Vector3) * 14.0 + Vector3(0, 9, 0), (Vector3(rp.top.x, 2.5, rp.top.z) + foot) * 0.5, 62.0)
			"pickups": # every pickup kind in a row
				for v: Vehicle in [player] + main.enemies:
					v.global_position = Vector3(0, -200, 0)
				var kinds := ["homing", "fire", "power", "napalm", "remote", "zoomy", "sat", "turbo", "health", "mega"]
				var base := LosAngelesArena.ground(-60, 72)
				for i in kinds.size():
					Pickup.create(main, kinds[i], base + Vector3(-13.5 + i * 3.0, 0, 0)).monitoring = false
				await _frames(20)
				_place(cam, base + Vector3(0, 5.0, 17), base + Vector3(0, 1.0, 0), 62.0)
			"weapons": # trails of each missile, the taser arc, the SAT zone and a mine
				Engine.max_physics_steps_per_frame = 1 # one physics step per frame: trails sample smoothly
				var e: Vehicle = main.enemies[0]
				var base := LosAngelesArena.ground(-40, 40)
				player.global_transform = Transform3D(Basis.IDENTITY, base + Vector3(0, 0.05, 0))
				e.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(90)), base + Vector3(9, 0.05, 3))
				await _frames(5)
				Mine.drop(player, WeaponData.get_def("remote"))
				SatStrike.start(player, "sat", WeaponData.get_def("sat"))
				TaserLink.start(e, WeaponData.get_def("omni_taser"))
				var ids := ["fire", "homing", "power", "zoomy"]
				for i in ids.size():
					var from := base + Vector3(-26, 3.0 + i * 0.4, -4.0 - i * 4.5)
					Projectile.spawn(main, ids[i], from, Vector3(1, 0, 0.05), e, null)
				await _frames(16)
				_place(cam, base + Vector3(-12, 8, 17), base + Vector3(1, 1, -7), 64.0)
			"impact": # a power missile hitting Outlaw: flash, shockwave, debris, jolt
				var e: Vehicle = main.enemies[0]
				var base := LosAngelesArena.ground(-40, 40)
				player.global_position = Vector3(0, -200, 0)
				e.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(90)), base + Vector3(0, 0.05, 0))
				await _frames(5)
				Engine.max_physics_steps_per_frame = 1
				Projectile.spawn(main, "power", e.aim_point() + Vector3(-7, 0.3, 0), Vector3(1, 0, 0), player, e)
				var after := OS.get_cmdline_user_args()
				await _frames(int(after[2]) if after.size() > 2 else 9)
				_place(cam, base + Vector3(-9, 4.5, 11), base + Vector3(0, 1.5, 0), 60.0)
				await RenderingServer.frame_post_draw
				root.get_viewport().get_texture().get_image().save_png(out)
				quit()
				return
			"duel":
				var c := player.global_position
				var e: Vehicle = main.enemies[0]
				player.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(90.0)), LosAngelesArena.ground(c.x + 5.5, c.z, 0.05))
				e.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(-90.0)), LosAngelesArena.ground(c.x - 5.5, c.z + 0.8, 0.05))
				await _frames(10)
				_place(cam, c + Vector3(-1.5, 3.4, 12.5), c + Vector3(0, 1.4, 0), 55.0)
			_:
				if shot.begins_with("car:"):
					await _car_shot(main, cam, shot.split(":"))
				elif shot.begins_with("look:"): # look:x,y,z:tx,ty,tz = free camera
					var parts := shot.split(":")
					var a := parts[1].split_floats(",")
					var b := parts[2].split_floats(",")
					_place(cam, Vector3(a[0], a[1], a[2]), Vector3(b[0], b[1], b[2]), 62.0)
	await _frames(15)
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()


## Shows one car model alone on open ground (other cars moved far away) from a set angle.
func _car_shot(main: Node, cam: Camera3D, parts: PackedStringArray) -> void:
	var id := parts[1] if parts.size() > 1 else "sweet_tooth"
	var angle := parts[2] if parts.size() > 2 else "front34"
	var player: Vehicle = main.player
	var base := player.global_position
	for v: Vehicle in [player] + main.enemies:
		v.global_position += Vector3(0, -200, 0)
		v.visible = false
	var model := VehicleModels.build(id)
	main.add_child(model)
	model.global_position = LosAngelesArena.ground(base.x, base.z, 0.0)
	model.rotation.y = deg_to_rad(150.0)
	await _frames(10)
	var c := model.global_position
	var fwd := -model.global_basis.z
	var right := model.global_basis.x
	var look := c + Vector3(0, 1.2, 0)
	match angle:
		"front34":
			_place(cam, c + fwd * 6.8 + right * -5.2 + Vector3(0, 2.4, 0), look, 50.0)
		"rear34":
			_place(cam, c - fwd * 7.0 + right * 5.0 + Vector3(0, 3.0, 0), look, 50.0)
		"side":
			_place(cam, c + right * 9.5 + Vector3(0, 1.6, 0), look, 45.0)
		"front":
			_place(cam, c + fwd * 8.5 + Vector3(0, 1.8, 0), look, 45.0)
		"top":
			_place(cam, c + fwd * 3.0 + right * -4.0 + Vector3(0, 8.5, 0), c + Vector3(0, 1.5, 0), 55.0)
		"low":
			_place(cam, c + fwd * 4.6 + right * -2.8 + Vector3(0, 0.7, 0), c + Vector3(0, 1.4, 0), 60.0)


func _place(cam: Camera3D, pos: Vector3, look: Vector3, fov: float) -> void:
	cam.global_position = pos
	cam.look_at(look)
	cam.fov = fov
	cam.h_offset = 0.0
	cam.v_offset = 0.0
