extends SceneTree
## Scratch (round 18): film the secondary weapons. Run with --fixed-fps 30. args: scenario out_dir frames every
##   bot      Sweet Tooth drops Sweet Bot, Outlaw comes up behind, the special's fire button sends the barrage
##   botkill  Outlaw shoots the waiting robot (power + fire missile): it goes up like a Remote
##   clamp    Outlaw throws the wheel clamp at Sweet Tooth driving ahead of her: the steering drags aside


class Pad:
	extends RefCounted
	var steer := 0.0
	var throttle := 0.0
	var fire := false

	func drive(v: Vehicle, _delta: float) -> void:
		v.in_steer = steer
		v.in_throttle = throttle
		if fire:
			v.want_fire_weapon = true
			fire = false


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
	var cam: ChaseCamera = main.camera
	main.hud._help.visible = false
	var p: Vehicle = main.player
	var e: Vehicle = main.enemies[0]
	for v: Vehicle in [p] + main.enemies:
		v.invulnerable_time = 0.0
		v._visual.visible = true
	var pp := Pad.new()
	var ep := Pad.new()
	p.controller = pp
	e.controller = ep
	var base := LosAngelesArena.ground(-40, 40)
	var west := Basis(Vector3.UP, deg_to_rad(90)) # facing -X
	p.global_transform = Transform3D(west, base + Vector3(0, 0.1, 0))
	e.global_transform = Transform3D(west, base + Vector3(42 if scenario != "clamp" else 26, 0.1, 1.5))
	p.target = e
	e.target = p
	for i in 20:
		await physics_frame
	var bot: SweetBot = null
	var n := 0
	cam.target = null
	cam.fov = 55.0
	for i in frames:
		match scenario:
			"bot":
				ep.throttle = 0.32 if e.global_position.x - base.x > 30.0 else 0.0 # stops short, ~24 m from the robot
				if i == 15:
					p.ammo[p.special_id] = 3
					p.energy_move("secondary")
				if i == 70:
					p.selected = p.weapon_order.find(p.special_id)
					pp.fire = true
				var at := base + Vector3(5.7, 0, 0) # where the robot lands, behind the truck
				cam.global_position = at + Vector3(-5.5, 3.2, 7.5)
				cam.look_at(at + Vector3(5.0, 1.3, 0))
			"botlook": # the robot close up, from the front
				if i == 5:
					p.ammo[p.special_id] = 3
					p.energy_move("secondary")
				var at3 := base + Vector3(5.7, 0, 0)
				if args.size() > 4 and args[4] == "cone":
					cam.global_position = at3 + Vector3(2.2, 2.9, 1.6)
					cam.look_at(at3 + Vector3(0, 2.8, 0))
				else:
					cam.global_position = at3 + Vector3(3.6, 1.9, 2.4)
					cam.look_at(at3 + Vector3(0, 1.15, 0))
			"botkill":
				if i == 10:
					p.ammo[p.special_id] = 3
					p.energy_move("secondary")
				bot = p.live_special() as SweetBot
				if (i == 45 or i == 62) and is_instance_valid(bot):
					var from := e.launch_point()
					Projectile.spawn(main, "power" if i == 45 else "fire", from, (bot.global_position + Vector3.UP * 1.2 - from).normalized(), e, null)
				var at2 := base + Vector3(5.7, 0, 0)
				cam.global_position = at2 + Vector3(-6.5, 4.0, 10.0)
				cam.look_at(at2 + Vector3(4.0, 1.2, 0))
			"clamp":
				pp.throttle = 0.8
				ep.throttle = 0.8
				if i == 25:
					e.ammo[e.special_id] = 2
					e.energy_move("secondary")
				var fwd := -p.global_basis.z
				fwd.y = 0.0
				fwd = fwd.normalized()
				var side := p._clamp_side if p.clamped_time > 0.0 else 1.0 # beside the locked wheel
				var right := fwd.cross(Vector3.UP).normalized()
				var want := p.global_position + right * side * 6.5 + fwd * 1.5 + Vector3(0, 2.6, 0)
				if p.clamped_time <= 0.0:
					want = p.global_position - fwd * 10.0 + Vector3(0, 4.2, 0)
				cam.global_position = cam.global_position.lerp(want, 0.15) if i > 0 else want
				cam.look_at(p.global_position + fwd * 1.8 + Vector3.UP * 0.8)
		await RenderingServer.frame_post_draw
		if i % every == 0:
			root.get_viewport().get_texture().get_image().save_png("%s/f%03d.png" % [out, n])
			n += 1
		if i % 30 == 0:
			print("frame %d bot %s state %s shots %d | player hp %.0f clamped %.1f | spawned %d" % [i, is_instance_valid(p.live_special()), (p.live_special() as SweetBot).state if p.live_special() is SweetBot else "-", (p.live_special() as SweetBot)._shots if p.live_special() is SweetBot else 0, p.health, p.clamped_time, Projectile.spawned_total])
	quit()
