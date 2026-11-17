extends SceneTree
## Headless gameplay smoke test. Exit code 0 = all passed.
##   godot --headless --path . -s tests/smoke_test.gd

var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_failures.append(what)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _tap(action: String) -> void:
	Input.action_press(action)
	await _frames(2)
	Input.action_release(action)
	await _frames(1)


func _new_game() -> Node:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _frames(20)
	return main


## Put a car somewhere, facing yaw (0 = north, -90 = east), at rest.
func _place(v: Vehicle, x: float, z: float, yaw_deg: float) -> void:
	v.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), LosAngelesArena.ground(x, z, 0.1))
	v.velocity = Vector3.ZERO
	v.angular_velocity = Vector3.ZERO
	v.speed = 0.0
	v.flipped = false


func _park(main: Node) -> void:
	for e: Vehicle in main.enemies:
		e.controller = null


func _run() -> void:
	var main_script: GDScript = load("res://scripts/main.gd")
	main_script.full_roster = true # these checks fight all five cars
	var main: Node = await _new_game()
	var player: Vehicle = main.player
	_check(main.arena is LosAngelesArena, "stage 1 is Los Angeles")
	_check(player != null and player.car_id == "sweet_tooth", "Sweet Tooth spawned as the player")
	_check(main.enemies.size() == 4, "four AI enemies in stage 1 (%d)" % main.enemies.size())
	_check(get_nodes_in_group("pickups").size() >= 20, "weapon and health pickups placed (%d)" % get_nodes_in_group("pickups").size())
	_check(player.is_on_floor(), "player rests on the ground")
	_check(is_equal_approx(player.max_health, 328.0), "Sweet Tooth health from the stats (328)")
	var grimm: Vehicle = main.enemies.filter(func(e: Vehicle): return e.car_id == "mr_grimm")[0]
	_check(is_equal_approx(grimm.max_health, 216.0), "Mr. Grimm health from the stats (216)")
	# Sounds (owner's TM2 recordings): crash variants, aliases, engine loop by class.
	_check(GameFeel.streams("crash").size() == 4, "four crash variants load (%d)" % GameFeel.streams("crash").size())
	_check(not GameFeel.streams("launch_power").is_empty(), "power missile launch sound loads")
	_check(player._eng.size() == 3 and (player._eng["idle"] as AudioStreamPlayer3D).stream.get("loop"), "Sweet Tooth has its own looping engine layers (ice-cream truck)")
	_check(player._gun_snd != null and player._skid_snd != null, "gun and skid loops are ready")
	_check(AudioServer.get_bus_index("Music") >= 0 and main.music.bus == "Music", "music plays on its own bus (own volume, never ducked)")
	AudioSettings.change("sfx", -1)
	AudioSettings.change("sfx", 1)
	_check(is_equal_approx(AudioSettings.sfx, 0.8) and AudioServer.get_bus_index("SFX") >= 0, "effects volume steps and comes back (%.1f)" % AudioSettings.sfx)
	# Music: LA plays its own theme; M in the pause menu tries the next track (owner's music test).
	var la_theme: String = main.music.stream.resource_path if main.music and main.music.stream else ""
	_check(la_theme.ends_with("los_angeles.ogg"), "Los Angeles plays its own theme (%s)" % la_theme)
	_check(main.music_tracks().size() >= 14, "all picked and unpicked themes are playable (%d)" % main.music_tracks().size())
	main._cycle_music()
	var tried: String = main.music.stream.resource_path
	_check(main.music_pick != "" and tried.ends_with("paris.ogg") and main.music.playing, "M steps to the next theme in story order (%s)" % tried.get_file())
	main.music_pick = ""
	main._start_music()
	var brains: Array = main.enemies.map(func(e: Vehicle): return e.controller)
	_park(main)
	var enemy_starts: Array = main.enemies.map(func(e: Vehicle): return e.global_position)

	# Driving: the player starts on the south road facing east.
	var start := player.global_position
	Input.action_press("accelerate")
	await _frames(120)
	Input.action_release("accelerate")
	var moved := player.global_position.distance_to(start)
	_check(moved > 8.0, "player drives forward (%.1f m in 2 s)" % moved)
	_check(player.global_position.x > start.x + 5.0, "forward is east along the road")

	# Steering.
	var yaw := player.rotation.y
	Input.action_press("accelerate")
	Input.action_press("steer_right")
	await _frames(40)
	Input.action_release("steer_right")
	Input.action_release("accelerate")
	_check(player.rotation.y < yaw - 0.2, "steering right turns right")

	# Machine guns.
	var shots := Projectile.spawned_total
	Input.action_press("fire_guns")
	await _frames(60)
	Input.action_release("fire_guns")
	_check(Projectile.spawned_total - shots >= 10, "machine guns fire (%d rounds in 1 s)" % (Projectile.spawned_total - shots))

	# Special weapon: Napalm Cone.
	var special := player.special_id
	var before: int = player.ammo[special]
	await _tap("fire_weapon")
	_check(special == "napalm_cone" and player.ammo[special] == before - 1, "special weapon (Napalm Cone) fires")

	# Weapon pickup and cycling.
	var had: int = player.ammo.get("homing", 0)
	player.add_ammo("homing", 3)
	_check(player.weapon_order.has("homing") and player.ammo["homing"] == had + 3, "picked-up weapon added to inventory")
	var sel := player.selected
	await _tap("weapon_next")
	_check(player.selected == wrapi(sel + 1, 0, player.weapon_order.size()), "weapon cycling selects the next weapon")

	# Combos: right after a power missile, switching to another weapon fires at once;
	# the same weapon has to wait for its own reload.
	player.add_ammo("power", 2)
	player.add_ammo("fire", 3)
	player._weapon_cooldowns.clear()
	player.selected = player.weapon_order.find("power")
	player._fire_selected()
	var p_left: int = player.ammo["power"]
	player._fire_selected()
	_check(player.ammo["power"] == p_left, "the same weapon waits for its reload")
	player.selected = player.weapon_order.find("fire")
	var f_left: int = player.ammo["fire"]
	player._fire_selected()
	_check(player.ammo["fire"] == f_left - 1, "switching weapons fires instantly (combos)")

	# Energy jump, and the pause in energy regen after spending.
	_place(player, -60, 60, 0)
	await _frames(30)
	var y0 := player.global_position.y
	var e0 := player.energy
	await _tap("move_jump")
	await _frames(8)
	_check(player.global_position.y > y0 + 0.8, "energy jump lifts the car (%.2f m)" % (player.global_position.y - y0))
	_check(player.energy < e0, "jump costs energy")
	var e1 := player.energy
	await _frames(30)
	_check(is_equal_approx(player.energy, e1), "no energy regen for a moment after spending")

	# Energy combos (owner, play-test 1): quick taps on the D-pad / arrows set moves off.
	await _frames(60)
	player.energy = 100.0
	for d: String in ["dir_left", "dir_right", "dir_down"]:
		await _tap(d)
	await _frames(2)
	var rear_shots := get_nodes_in_group("projectiles").filter(func(p: Node) -> bool: return (p as Projectile).weapon_id == "rear_freeze")
	_check(rear_shots.size() == 1, "LEFT RIGHT DOWN throws a freeze out of the back")
	if rear_shots.size() == 1:
		_check((rear_shots[0] as Projectile).direction.dot(player.flat_forward()) < -0.5, "...backwards")
	player.energy = 100.0
	for d: String in ["dir_up", "dir_up", "dir_right"]:
		await _tap(d)
	await _frames(2)
	_check(player.shield_time > 0.0, "UP UP RIGHT raises the shield")
	var shield_hp := player.health
	player.take_damage(30.0, main.enemies[0])
	_check(is_equal_approx(player.health, shield_hp) and not player.freeze_for(2.0), "the shield stops damage and freezes")
	# Round 17: a green magnetic field around the whole car, wheels included; a blocked hit lights a
	# patch instead of the white flash.
	var wheel_meshes: Array = []
	for w: Node3D in player._wheels:
		wheel_meshes.append_array(w.find_children("*", "MeshInstance3D", true, false))
		if w is MeshInstance3D:
			wheel_meshes.append(w)
	var fielded := player._flash_meshes.filter(func(mi: Variant) -> bool: return is_instance_valid(mi) and (mi as MeshInstance3D).material_overlay == player._shield_mat)
	var wheels_in := not wheel_meshes.is_empty() and wheel_meshes.all(func(mi: Variant) -> bool: return (mi as MeshInstance3D).material_overlay == player._shield_mat)
	_check(not fielded.is_empty() and wheels_in, "the shield field covers the car, wheels included")
	player.hit_react(Vector3.BACK, 30.0)
	_check(player._shield_hit_age == 0.0 and player._flash_time <= 0.0, "a blocked hit lights the field where it landed (no white flash)")
	await _frames(170)
	_check(player.shield_time <= 0.0, "the shield drops after 2.5 s")
	player.energy = 100.0
	await _tap("move_mines")
	await _frames(2)
	_check(player._energy_mines.size() == 1, "mines: one mine dropped behind")
	for k in 3:
		player.energy = 100.0
		await _tap("move_mines")
		await _frames(2)
	_check(player._energy_mines.filter(func(m: Variant) -> bool: return is_instance_valid(m) and not (m as Mine)._done).size() == 3, "never more than 3 mines (the oldest goes off)")
	for m: Variant in player._energy_mines: # clear them: later tests drive here
		if is_instance_valid(m):
			(m as Node).queue_free()
	player._energy_mines.clear()
	player.energy = 100.0
	await _tap("move_rear_attack")
	await _frames(2)
	_check(get_nodes_in_group("projectiles").filter(func(p: Node) -> bool: return (p as Projectile).weapon_id == "rear_missile").size() == 2, "rear attack: two missiles out of the back")
	# Invisibility: no lock on you; headlights in the beam show you again.
	var watcher: Vehicle = main.enemies[1]
	_place(player, -60, 20, 0)
	_place(watcher, -60, 50, 0) # 30 m behind the player, facing it (north), both well inside the battleground
	await _frames(5)
	player.energy = 100.0
	await _tap("move_invisible")
	await _frames(3)
	_check(not player.is_hidden() and player.invisible_time > Vehicle.INVIS_TIME, "invisible: 0.8 s of sparks first, still seen (round 16, TM2)")
	var cloak_wait := 0
	while player.invisible_time > Vehicle.INVIS_TIME and cloak_wait < 240:
		await _frames(1)
		cloak_wait += 1
	await _frames(2)
	_check(player.is_hidden() and watcher.find_target() != player and not player.model.visible, "invisible: no lock on you, and the car is gone for its own driver too")
	watcher.toggle_headlights()
	await _frames(12)
	var to_p := player.aim_point() - (watcher.global_position + Vector3.UP)
	_check(not player.is_hidden(), "headlights in the beam reveal an invisible car (%.0f m, %.0f deg, lights %s, watcher %s)" % [to_p.length(), rad_to_deg(watcher.aim_forward().angle_to(to_p.normalized())), watcher.headlights_on, watcher.car_id])
	watcher.toggle_headlights()
	player.invisible_time = 0.0
	_place(watcher, 60, -40, 0) # out of the way of the driving tests
	# Camera modes: near, far, in the car.
	var cam: ChaseCamera = main.camera
	await _tap("camera_mode")
	_check(ChaseCamera.mode == "far", "camera button: far chase")
	await _tap("camera_mode")
	await _frames(2)
	_check(ChaseCamera.mode == "car" and cam.global_position.distance_to(player.global_position) < 4.0, "...then in the car")
	await _tap("camera_mode")
	_check(ChaseCamera.mode == "near", "...then back to near")
	await _frames(60)
	# PS5 layout (owner, round 7): R3 rear view toggles, Triangle reverses, the triggers swapped.
	await _tap("rear_view")
	_check(cam.looking_back(), "R3 turns the camera round and keeps it there")
	await _tap("rear_view")
	_check(not cam.looking_back(), "...R3 again looks forward")
	var pad_ok := func(action: String, button: int) -> bool:
		return InputMap.action_get_events(action).any(func(e: InputEvent): return e is InputEventJoypadButton and (e as InputEventJoypadButton).button_index == button)
	var axis_ok := func(action: String, axis: int) -> bool:
		return InputMap.action_get_events(action).any(func(e: InputEvent): return e is InputEventJoypadMotion and (e as InputEventJoypadMotion).axis == axis)
	_check(pad_ok.call("brake", JOY_BUTTON_Y) and pad_ok.call("handbrake", JOY_BUTTON_A) and pad_ok.call("handbrake", JOY_BUTTON_B)
		and pad_ok.call("headlights", JOY_BUTTON_LEFT_STICK) and pad_ok.call("camera_mode", JOY_BUTTON_BACK) and pad_ok.call("pause", JOY_BUTTON_TOUCHPAD)
		and axis_ok.call("fire_guns", JOY_AXIS_TRIGGER_RIGHT) and axis_ok.call("fire_weapon", JOY_AXIS_TRIGGER_LEFT),
		"pad: Triangle reverse, Cross/Circle drift, L3 lights, Create camera, touchpad pause, R2 guns, L2 weapon")
	# (Through the player's own controller in real frames: "just pressed" only counts inside a frame.)
	Input.action_press("brake")
	await _tap("pad_reverse")
	Input.action_press("pad_reverse")
	await _frames(2)
	_check(player.in_turbo and player.in_throttle < 0.0, "double-tap Triangle and hold: turbo in reverse")
	Input.action_release("pad_reverse")
	Input.action_release("brake")
	await _frames(2)
	_check(not player.in_turbo, "...let go: turbo off")

	# Freeze, ice breaking, Grit.
	var victim: Vehicle = main.enemies[0]
	_check(victim.freeze_for(2.0), "freeze holds a car")
	victim.take_damage(5.0, player)
	_check(victim.frozen_time > 0.0, "a small hit does not break the ice")
	victim.take_damage(20.0, player)
	_check(victim.frozen_time <= 0.0, "a hit of 15+ shatters the ice")
	_check(not victim.freeze_for(2.0), "Grit: can't be frozen again right away")

	# Health pickup: 30% of max health.
	player.health = 100.0
	var hp := Pickup.create(main, "health", player.global_position)
	await _frames(4)
	_check(absf(player.health - (100.0 + 328.0 * 0.3)) < 0.5, "health pickup heals 30%% of max (%.1f)" % (player.health - 100.0))
	if is_instance_valid(hp):
		hp.queue_free()
	await _frames(1)

	# Rams (owner, round 6): ram power and the part that takes the hit decide who wins.
	var outlaw: Vehicle = main.enemies.filter(func(e: Vehicle): return e.car_id == "outlaw")[0]
	var grimm_car: Vehicle = main.enemies.filter(func(e: Vehicle): return e.car_id == "mr_grimm")[0]
	var ram_at := Vector3(30, 0, 60)
	# Nose to nose: Sweet Tooth (7.5) beats Outlaw (5).
	player.global_transform = Transform3D(Basis.IDENTITY, LosAngelesArena.ground(ram_at.x, ram_at.z, 0.05)) # facing north
	outlaw.global_transform = Transform3D(Basis(Vector3.UP, PI), player.global_position + Vector3(0, 0, -6.5)) # facing south
	Vehicle._ram_pairs.clear()
	outlaw.linear_velocity = Vector3.ZERO
	outlaw._knock = 0.0
	player._ram(outlaw, Vector3(0, 0, -15), Vector3(0, 0, 1), player.global_position + Vector3(0, 1, -3.2))
	var r: Dictionary = player.last_ram
	_check(r.me == "front" and r.it == "front" and r.to_it > r.to_me, "nose to nose the stronger rammer wins (%.1f vs %.1f)" % [r.to_it, r.to_me])
	_check(outlaw.linear_velocity.z < -6.0 and outlaw._knock > 0.0, "...and the loser is thrown back, tyres sliding (round 7: %.1f m/s)" % -outlaw.linear_velocity.z)
	# Outlaw's nose into Sweet Tooth's side: the T-bone wins for Outlaw.
	outlaw.global_transform = Transform3D(Basis(Vector3.UP, PI * 0.5), player.global_position + Vector3(4.0, 0, 0)) # facing west
	Vehicle._ram_pairs.clear()
	player.angular_velocity = Vector3.ZERO
	outlaw._ram(player, Vector3(-15, 0, 0), Vector3(1, 0, 0), player.global_position + Vector3(1.1, 1, -1.5))
	r = outlaw.last_ram
	_check(r.me == "front" and r.it == "side" and r.to_it > r.to_me, "a nose into a stronger car's side wins (%.1f vs %.1f)" % [r.to_it, r.to_me])
	_check(absf(player.angular_velocity.y) > 0.5, "...and a hit on the side spins the car round (%.1f rad/s)" % player.angular_velocity.y)
	# Mr. Grimm (2.5) into Sweet Tooth's side: too weak, still loses (like Twister into Axel).
	grimm_car.global_transform = outlaw.global_transform
	outlaw.global_position += Vector3(0, 0, 30)
	Vehicle._ram_pairs.clear()
	grimm_car._ram(player, Vector3(-15, 0, 0), Vector3(1, 0, 0), player.global_position + Vector3(1.1, 1, 0))
	r = grimm_car.last_ram
	_check(r.it == "side" and r.to_it < r.to_me, "a much weaker car loses even hitting a side (%.1f vs %.1f)" % [r.to_it, r.to_me])
	player.health = player.max_health
	outlaw.health = outlaw.max_health
	grimm_car.health = grimm_car.max_health
	_place(grimm_car, -120, -100, 0)

	# Wall slide: 45 degrees into the south wall keeps most of the speed and turns along it.
	player.health = player.max_health
	player.global_transform = main.arena.spot("south_wall_45")
	player.velocity = Vector3.ZERO
	player.speed = 30.0
	Input.action_press("accelerate")
	await _frames(70)
	var fwd := player.flat_forward()
	Input.action_release("accelerate")
	_check(absf(player.speed) > 15.0, "a 45-degree wall hit keeps the car moving (%.1f m/s)" % player.speed)
	_check(fwd.x > 0.85, "...and turns it along the wall")
	# Square hit (owner, session 6): a slam. The car stops against the wall; scraping out along it
	# is slow, backing off works.
	player.global_transform = main.arena.spot("south_wall_90")
	player.velocity = Vector3.ZERO
	player.speed = 30.0
	var slammed := [0.0]
	var on_slam := func(_v: Vehicle, impact: float) -> void: slammed[0] = maxf(slammed[0], impact)
	player.wall_slammed.connect(on_slam)
	Input.action_press("accelerate")
	await _frames(90)
	_check(slammed[0] > 15.0 and Vector2(player.velocity.x, player.velocity.z).length() < 4.5, "a square wall hit slams the car to a stop (impact %.0f)" % slammed[0])
	Input.action_press("steer_right")
	await _frames(60)
	Input.action_release("steer_right")
	Input.action_release("accelerate")
	_check(Vector2(player.velocity.x, player.velocity.z).length() < 8.0, "...steering out along the wall is slow")
	player.wall_slammed.disconnect(on_slam)
	var stuck_at := player.global_position
	Input.action_press("brake")
	await _frames(60)
	Input.action_release("brake")
	_check(player.global_position.distance_to(stuck_at) > 3.0, "...backing off the wall works")

	# Brakes in a slide: the car skids on for a bit instead of stopping dead.
	_place(player, -60, 60, 0)
	player.velocity = Vector3(-14.0, 0, -20.0) # moving forward (north) and sliding left
	player.speed = 20.0
	await _frames(2)
	var slide_from := player.global_position
	Input.action_press("brake")
	await _frames(20)
	Input.action_release("brake")
	_check(player.global_position.distance_to(slide_from) > 6.0, "braking in a slide skids on (%.1f m)" % player.global_position.distance_to(slide_from))

	# Breakable hot dog stand drops a weapon.
	var stand: Breakable = null
	for c in main.arena.get_children():
		if c is Breakable and (c as Breakable).loot == "weapon" and not (c as Breakable).is_broken:
			stand = c
			break
	var pickups_before := get_nodes_in_group("pickups").size()
	stand.projectile_hit(30.0, player)
	await _frames(2)
	_check(stand.is_broken and stand.collision_layer == 0, "hot dog stand breaks")
	_check(get_nodes_in_group("pickups").size() == pickups_before + 1, "...and drops a weapon")

	# Teleporter on the tunnel roof sends you into the cage.
	var tp: Teleporter = null
	for c in main.arena.get_children():
		if c is Teleporter:
			tp = c
	player.global_position = tp.global_position + Vector3.UP * 0.2
	await _frames(6)
	_check(player.global_position.distance_to(tp.destination.origin) < 4.0, "teleporter on the roof leads to the cage")

	# Outlaw's taser: fire, mash, then drive away to break the link.
	var dog: Vehicle = main.enemies.filter(func(e: Vehicle): return e.car_id == "junkyard_dog")[0]
	_place(outlaw, 0, 40, 0)
	_place(dog, 0, 28, 0)
	await _frames(5)
	var d_hp := dog.health
	var dog_y := dog.global_position.y
	Specials.fire(outlaw, "omni_taser")
	_check(outlaw.has_live_special(), "taser links to a car in range")
	var jolt_link := outlaw.live_special() as TaserLink
	_check(jolt_link != null and jolt_link._siren != null and jolt_link._siren.playing and jolt_link._siren.stream.loop,
		"the siren loops for as long as the taser is on (round 10)")
	var dog_peak := dog_y
	for k in 14:
		await _frames(1)
		dog_peak = maxf(dog_peak, dog.global_position.y)
	_check(dog_peak - dog_y > 0.5, "the arc connecting throws the victim into a hop (%.2f m)" % (dog_peak - dog_y))
	# Parked cars have no controller, so press "fire" for them directly: mashing.
	for k in 10:
		if outlaw.has_live_special():
			outlaw.live_special().fire_again()
		await _frames(3)
	await _frames(30)
	_check(d_hp - dog.health > 12.0, "taser hurts while linked, mashing makes it stronger (%.1f)" % (d_hp - dog.health))
	_place(dog, 0, -10, 0)
	await _frames(3)
	_check(not outlaw.has_live_special(), "taser link breaks when the target gets too far")
	var charges: int = outlaw.ammo["omni_taser"]
	_place(dog, 60, 70, 0)
	await _frames(2)
	outlaw.ammo["omni_taser"] = 2
	outlaw.selected = 0
	outlaw._weapon_cooldowns.clear()
	outlaw._fire_selected()
	await _frames(3)
	_check(outlaw.ammo["omni_taser"] == 1 and outlaw.has_live_special(), "taser with nobody in range spends the charge and spins round the car searching (round 9)")
	await _frames(45)
	_check(outlaw.has_live_special(), "the search lasts the attack's duration, not 0.3 s")
	_place(dog, 0, 28, 0)
	var dog_hp := dog.health
	await _frames(12)
	var link := outlaw.live_special() as TaserLink
	_check(link != null and link.target == dog, "the spinning arc locks onto a car the moment it comes into range")
	await _frames(150)
	_check(not outlaw.has_live_special() and dog.health < dog_hp, "a late lock still deals damage, then the link ends (%.1f)" % (dog_hp - dog.health))
	# Line of sight (round 9): fences, glass and props don't break the link; a real wall does.
	var mid := (outlaw.aim_point() + dog.aim_point()) * 0.5
	var fence := MeshKit.solid_box(main, Vector3(8, 9, 0.3), mid, MatKit.plain(MeshKit.mat(Color.GRAY)))
	fence.add_to_group(&"see_through")
	await _frames(2)
	_check(TaserLink._can_see(outlaw, dog), "the taser sees through a fence")
	fence.remove_from_group(&"see_through")
	_check(not TaserLink._can_see(outlaw, dog), "a solid wall as tall as the cars hides the target")
	fence.queue_free()
	outlaw.ammo["omni_taser"] = charges

	# Junkyard Dog's chain bomb: hook a car, detonate by hand.
	_place(dog, 30, 40, 0)
	_place(outlaw, 30, 28, 0)
	await _frames(5)
	var o_hp2 := outlaw.health
	Specials.fire(dog, "chain_bomb")
	var bomb := dog.live_special() as ChainBomb
	_check(bomb != null, "chain bomb thrown")
	await _frames(30)
	_check(bomb != null and is_instance_valid(bomb) and bomb.state == ChainBomb.State.STUCK, "chain bomb hooks onto the car it hits")
	if dog.has_live_special():
		dog.live_special().fire_again()
	await _frames(3)
	_check(o_hp2 - outlaw.health >= 35.0, "detonating a hooked bomb hits hard (%.1f)" % (o_hp2 - outlaw.health))
	_check(not dog.has_live_special(), "bomb is gone after the blast")

	# Mr. Grimm's skull: the hardest single special hit (65).
	_place(outlaw, -20, 20, 0)
	await _frames(3)
	outlaw.health = outlaw.max_health
	outlaw.invulnerable_time = 0.0
	var o_hp3 := outlaw.health
	Projectile.spawn(main, "reaper_skull", outlaw.aim_point() + Vector3(0, 0, 8), Vector3(0, 0, -1), grimm, outlaw)
	await _frames(12)
	_check(absf((o_hp3 - outlaw.health) - 65.0) < 0.5, "Reaper Skull hits for 65")

	# Spectre's ghost missile flies through the burnt building's wall.
	var spectre: Vehicle = main.enemies.filter(func(e: Vehicle): return e.car_id == "spectre")[0]
	var bb := LosAngelesArena.BURNT_AT
	_place(spectre, bb.x - 22.0, bb.z, -90)
	_place(dog, bb.x - 2.0, bb.z, 90)
	await _frames(3)
	var g_hp := dog.health
	Projectile.spawn(main, "ghost_missile", spectre.aim_point() + Vector3(2, 0, 0), Vector3(1, 0, 0), spectre, dog)
	await _frames(40)
	_check(g_hp - dog.health >= 23.0, "ghost missile passes through walls")

	# Napalm Cone lands on a parked target and sets it on fire.
	_place(player, 40, 70, 90)
	_place(outlaw, 10, 70, 90)
	player.target = outlaw
	player.auto_target = false
	await _frames(3)
	var n_hp := outlaw.health
	player.ammo["napalm_cone"] = 2
	player.selected = 0
	player._weapon_cooldowns.clear()
	player._fire_selected()
	await _frames(60)
	_check(n_hp - outlaw.health >= 44.5, "Napalm Cone tap: homing cone hits for 45 (%.1f)" % (n_hp - outlaw.health))
	_check(outlaw.burn_time > 0.0, "...and sets it on fire")

	# Charged Napalm Cone: hold fire 2 s and let go = 90 + burning, flying straight.
	outlaw.health = outlaw.max_health
	outlaw.burn_time = 0.0
	player.ammo["napalm_cone"] = 2
	player.selected = 0
	player._weapon_cooldowns.clear()
	await _frames(2)
	n_hp = outlaw.health
	Input.action_press("fire_weapon")
	await _frames(130)
	_check(player.charge_ratio() >= 1.0, "holding fire charges the Napalm Cone")
	Input.action_release("fire_weapon")
	await _frames(2)
	var cones: Array = main.get_children().filter(func(n: Node): return n is Projectile and n.weapon_id == "napalm_cone")
	_check(not cones.is_empty() and float(cones[0].def.homing) == 0.0, "...the charged cone has no tracking")
	await _frames(45)
	_check(n_hp - outlaw.health >= 89.5, "charged Napalm Cone hits for 90 (%.1f)" % (n_hp - outlaw.health))
	_check(outlaw.burn_time > 0.0, "...and burns")
	# Meltdown (owner, rounds 10 + 17): held 2 s past the full charge (4 s in all) the charge is lost,
	# no ammo spent, weapon locked 3 s.
	player.ammo["napalm_cone"] = 2
	player._weapon_cooldowns.clear()
	player._special_timer = 0.0 # no special comes back during the hold (it would add one)
	var said: Array[String] = []
	var hear := func(_v: Vehicle, text: String) -> void: said.append(text)
	player.notice.connect(hear)
	await _frames(2)
	var melt_shots := Projectile.spawned_total
	Input.action_press("fire_weapon")
	await _frames(210)
	_check(player.charging_id == "napalm_cone", "a full charge can still be held for 2 s (3.5 s)")
	await _frames(40)
	_check(player.charging_id == "" and player.locked_left("napalm_cone") > 2.0 and player.ammo["napalm_cone"] == 2 and Projectile.spawned_total == melt_shots,
		"held 4 s the Napalm Cone melts down: no shot, no ammo lost, locked (%.1f s)" % player.locked_left("napalm_cone"))
	_check(said.has("NAPALM CONE MELTDOWN"), "...and the HUD says so")
	Input.action_release("fire_weapon")
	await _frames(2)
	Input.action_press("fire_weapon")
	await _frames(3)
	Input.action_release("fire_weapon")
	await _frames(3)
	_check(Projectile.spawned_total == melt_shots, "a melted-down weapon will not fire while locked")
	player.notice.disconnect(hear)
	player._locked.clear()
	player._weapon_cooldowns.clear()
	# Round 17: the white hit flash once covered every mesh of the car, the soft ground shadow too, and
	# only the body was cleared afterwards: a bright square stayed under the car for good.
	player.hit_react(Vector3.FORWARD, 30.0)
	await _frames(20)
	var lit_overrides := player._flash_meshes.filter(func(mi: Variant) -> bool:
		return is_instance_valid(mi) and (mi as MeshInstance3D).material_override != null and (mi as MeshInstance3D).material_overlay != null)
	_check(lit_overrides.is_empty() and player._flash_time <= 0.0, "a hit flash leaves no white square under the car")
	# Round 17: the top container of the stack was a ghost (cars drove up the stack and through it).
	var box_ray := PhysicsRayQueryParameters3D.create(Vector3(-73.0, 12.0, 46.4), Vector3(-73.0, 6.0, 46.4), 1)
	var box_hit: Dictionary = main.get_viewport().world_3d.direct_space_state.intersect_ray(box_ray)
	_check(not box_hit.is_empty() and float((box_hit.position as Vector3).y) > 9.0, "the top container is solid (%s)" % str(box_hit.get("position", "nothing")))

	# Napalm (gas can): thrown up and ahead, dropped on the car with a second press.
	_place(outlaw, 20, 70, 90)
	outlaw.health = outlaw.max_health
	outlaw.burn_time = 0.0
	await _frames(3)
	n_hp = outlaw.health
	player.add_ammo("napalm", 1)
	player.selected = player.weapon_order.find("napalm")
	player._weapon_cooldowns.clear()
	player._fire_selected()
	_check(player.has_live_special(), "napalm can thrown, waiting for the drop")
	for k in 90:
		await _frames(1)
		var can := player.live_special() as Node3D
		if can == null or absf(can.global_position.x - outlaw.global_position.x) < 2.0:
			player.want_fire_weapon = true
			break
	await _frames(50)
	_check(n_hp - outlaw.health >= 25.0 and outlaw.burn_time > 0.0, "napalm dropped on a car hits and burns (%.1f)" % (n_hp - outlaw.health))

	# Remote: a mine dropped behind; a car driving onto it sets it off and gets thrown up.
	_place(outlaw, 60, 70, 90)
	outlaw.health = outlaw.max_health
	outlaw.burn_time = 0.0
	await _frames(3)
	n_hp = outlaw.health
	player.add_ammo("remote", 1)
	player.selected = player.weapon_order.find("remote")
	player._weapon_cooldowns.clear()
	player._fire_selected()
	var mine := player.live_special() as Mine
	_check(mine != null and mine.global_position.x > player.global_position.x + 2.0, "remote drops a mine behind the car")
	await _frames(60)
	outlaw.global_position = mine.global_position + Vector3(0, 0.3, 0)
	await _frames(3)
	_check(not is_instance_valid(mine) or mine.is_queued_for_deletion(), "driving onto the armed mine sets it off")
	_check(n_hp - outlaw.health >= 45.0, "...for about 50 (%.1f)" % (n_hp - outlaw.health))
	_check(outlaw.velocity.y > 5.0 or outlaw.angular_velocity.length() > 1.5, "...and throws the car into the air")
	await _frames(90)
	# Friendly fire: your own mine hurts you too, and so does your own fire.
	_place(player, 40, 70, 90) # stand still on flat ground, well away from the first blast
	_place(outlaw, 0, 70, 90)
	await _frames(20)
	var own_hp := player.health
	player.add_ammo("remote", 1)
	player.selected = player.weapon_order.find("remote")
	player._weapon_cooldowns.clear()
	player._fire_selected()
	mine = player.live_special() as Mine
	await _frames(60)
	_check(is_instance_valid(mine), "a parked car's own mine waits behind it")
	player.global_position = mine.global_position + Vector3(0, 0.3, 0)
	await _frames(3)
	_check(own_hp - player.health >= 40.0, "friendly fire: your own mine hurts you (%.1f)" % (own_hp - player.health))
	_check(player.velocity.y > 8.0, "...and a heavy truck on top still flies (%.1f m/s up)" % player.velocity.y)
	await _frames(100) # land
	player.health = player.max_health
	_place(player, 40, 70, 90) # the mine may have left it tumbling: back on its wheels on flat ground
	await _frames(5)
	# Owner, round 7: blow your own Remote right after dropping it and it catches your tail, though the
	# car has already driven past its radius: you take damage, get kicked forward, lose grip.
	player.add_ammo("remote", 1)
	player.selected = player.weapon_order.find("remote")
	player._weapon_cooldowns.clear()
	player._fire_selected()
	mine = player.live_special() as Mine
	player.global_position = mine.global_position + player.flat_forward() * 13.0 + Vector3.UP * 0.4
	await _frames(15)
	own_hp = player.health
	var fwd_before := player.velocity.dot(player.flat_forward())
	mine.fire_again()
	var kick := player.velocity.dot(player.flat_forward()) - fwd_before
	_check(own_hp - player.health >= 20.0 and kick > 8.0 and player.velocity.y > 5.0 and player._knock > 0.0,
		"blowing your own Remote at once hurts you and kicks you forward out of control (%.1f hp, +%.1f m/s)" % [own_hp - player.health, kick])
	await _frames(100)
	player.health = player.max_health
	_place(player, 40, 70, 90)
	await _frames(5)
	FirePool.spawn(main, player.global_position, 3.0, 2.0, 3.0, player)
	await _frames(40)
	_check(player.burn_time > 0.0, "friendly fire: your own napalm fire burns you")
	player.burn_time = 0.0
	_place(player, 40, 70, 90)
	await _frames(30)

	# Zoomy: ten light missiles, 6 each; a parked car takes most of them.
	_place(outlaw, 0, 70, 90)
	outlaw.health = outlaw.max_health
	outlaw.burn_time = 0.0 # still burning from the napalm
	await _frames(3)
	n_hp = outlaw.health
	var shots_before := Projectile.spawned_total
	player.add_ammo("zoomy", 1)
	player.selected = player.weapon_order.find("zoomy")
	player._weapon_cooldowns.clear()
	player._fire_selected()
	await _frames(120)
	_check(Projectile.spawned_total - shots_before >= 10, "zoomy fires ten missiles")
	_check(n_hp - outlaw.health >= 40.0 and n_hp - outlaw.health <= 60.5, "...a car that sits still takes most of the 60 (%.1f)" % (n_hp - outlaw.health))

	# SAT: the strike zone sits in front of the shooter and moves with it; 4 s later, 112.
	_place(outlaw, 10, 40, 90)
	outlaw.health = outlaw.max_health
	outlaw.burn_time = 0.0
	await _frames(3)
	n_hp = outlaw.health
	player.add_ammo("sat", 1)
	player.selected = player.weapon_order.find("sat")
	await _frames(3)
	_check(player._sat_preview != null, "with SAT selected its zone shows ahead of the car (round 9)")
	player._weapon_cooldowns.clear()
	player._fire_selected()
	await _frames(60)
	_place(player, 34, 40, 90) # the enemy moved: we follow it, the zone comes along
	await _frames(140)
	_check(is_equal_approx(n_hp, outlaw.health), "SAT: nothing happens before the 4 s are up")
	await _frames(60)
	_check(absf((n_hp - outlaw.health) - 112.0) < 0.5, "SAT zone moves with you and hits for 112 (%.1f)" % (n_hp - outlaw.health))
	_check(player._sat_preview == null, "the preview is gone once the SAT is spent")
	# Remote (round 9): an electronic mine; a clean hit sets the car burning.
	outlaw.burn_time = 0.0
	var clean := Mine.new()
	clean.owner_car = player
	clean.def = WeaponData.get_def("remote")
	main.add_child(clean)
	clean.global_position = outlaw.global_position
	clean.detonate()
	_check(outlaw.burn_time > 0.0, "a clean Remote hit sets the car on fire")
	outlaw.burn_time = 0.0
	# Full health (round 9, the HOLLYWOOD prize): health and energy back to 100%.
	_place(player, 40, 60, 0)
	player.health = 20.0
	player.energy = 0.0
	Pickup.create(main, "full", player.global_position)
	await _frames(4)
	_check(is_equal_approx(player.health, player.max_health) and is_equal_approx(player.energy, 100.0), "full health restores health and energy to 100%")
	player.auto_target = true

	# Pickups say what you got; turbo never refills by itself, a turbo pickup fills it.
	var heard: Array[String] = []
	var listen := func(_v: Vehicle, text: String) -> void: heard.append(text)
	player.notice.connect(listen)
	Pickup.create(main, "fire", player.global_position)
	await _frames(4)
	_check(heard.has("FIRE MISSILE LOADED"), "weapon pickup says FIRE MISSILE LOADED")
	_place(player, -60, 60, 0)
	player.turbo = 100.0
	Input.action_press("accelerate")
	Input.action_press("turbo")
	await _frames(60)
	Input.action_release("turbo")
	Input.action_release("accelerate")
	var t_left := player.turbo
	await _frames(120)
	_check(t_left < 95.0 and is_equal_approx(player.turbo, t_left), "turbo drains and never refills by itself (%.0f)" % player.turbo)
	Pickup.create(main, "turbo", player.global_position)
	await _frames(4)
	_check(is_equal_approx(player.turbo, 100.0) and heard.has(Pickup.MSG_TURBO), "a turbo pickup fills the bar completely")
	player.notice.disconnect(listen)
	# Hills (round 5): a crest throws a fast car into the air (no more "magnet"), and it never flips it.
	var hill: Dictionary = LosAngelesArena.hills()[1]
	var hd: Vector2 = hill.d
	Input.action_press("accelerate")
	for hill_speed: float in [16.0, 24.0]:
		var hill_start := LosAngelesArena.ground(hill.p.x - hd.x * 30.0, hill.p.y - hd.y * 30.0, 0.05)
		player.global_transform = Transform3D(Basis.looking_at(Vector3(hd.x, 0, hd.y), Vector3.UP), hill_start)
		player.velocity = Vector3(hd.x, 0, hd.y) * hill_speed
		player.angular_velocity = Vector3.ZERO
		player.speed = hill_speed
		var over := 0.0
		var lowest_up := 1.0
		for i in 120:
			await physics_frame
			over = maxf(over, player.global_position.y - LosAngelesArena.ground(player.global_position.x, player.global_position.z).y)
			lowest_up = minf(lowest_up, player.global_basis.y.y)
		_check(not player.flipped and lowest_up > 0.6, "a hill crest at %.0f m/s does not flip the car (lowest up %.2f)" % [hill_speed, lowest_up])
		if hill_speed > 20.0:
			_check(over > 0.8, "...and a fast car leaves the ground over the crest (%.1f m)" % over)
	Input.action_release("accelerate")
	# HOLLYWOOD secret (owner, round 6): nose up on a tunnel-roof ramp, a missile clears the fence
	# and knocks a letter down; flat shots fly under the sign.
	var roof_ramp: Dictionary = main.arena.ramps.filter(func(rr): return absf((rr.top as Vector3).y - LosAngelesArena.ROOF_Y) < 0.1)[0]
	var ramp_mid: Vector3 = ((roof_ramp.foot as Vector3) + (roof_ramp.top as Vector3)) * 0.5
	var up_ramp := (roof_ramp.top as Vector3) - (roof_ramp.foot as Vector3)
	up_ramp.y = 0.0
	player.global_transform = Transform3D(Basis.looking_at(up_ramp.normalized(), Vector3.UP), ramp_mid + Vector3.UP)
	player.velocity = Vector3.ZERO
	player.angular_velocity = Vector3.ZERO
	await _frames(40)
	var letters_before: int = main.arena._letters_left
	player.launch("power", null)
	await _frames(150)
	_check(main.arena._letters_left == letters_before - 1, "a missile fired nose-up on the roof ramp knocks down a HOLLYWOOD letter")
	_place(player, 40, 70, 90)
	# Flips (round 5, real physics): dropped onto its roof the car lies there "flipped" and slides;
	# gas + left/right rolls it back onto its wheels.
	_place(player, 40, 70, 90)
	player.global_transform = Transform3D(Basis(Vector3.FORWARD, PI), player.global_position + Vector3.UP * 3.0)
	player.velocity = Vector3(-14, 0, 0)
	await _frames(50)
	_check(player.flipped, "a car dropped on its roof lies there flipped")
	var slid_from := player.global_position.x
	await _frames(10)
	_check(player.global_position.x < slid_from - 0.5, "...and slides on its roof instead of stopping dead")
	Input.action_press("accelerate")
	Input.action_press("steer_left")
	await _frames(90)
	Input.action_release("steer_left")
	Input.action_release("accelerate")
	await _frames(40)
	_check(not player.flipped and player.global_basis.y.y > 0.8, "gas + left/right rolls a flipped car back onto its wheels")
	# A slow car hanging most of its length over the battleground edge tips over onto its roof...
	var ex := 80.0
	while LosAngelesArena.edge_distance(ex, 45.0) > 0.0:
		ex += 0.1
	var psize: Vector3 = player.stats.size
	player.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(-90)), Vector3(ex + psize.z * 0.3, 5.1, 45.0))
	player.velocity = Vector3.ZERO
	player.angular_velocity = Vector3.ZERO
	player.speed = 0.0
	await _frames(150)
	_check(player.global_basis.y.y < 0.85 and player.global_position.y < 4.6, "a car hanging over the edge tips over it under gravity, nose first (up %.2f, y %.1f)" % [player.global_basis.y.y, player.global_position.y])
	player.angular_velocity = Vector3.ZERO
	# ...while one driving off it at speed flies and lands on its wheels.
	player.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(-90)), Vector3(ex - 4.0, 5.1, 45.0))
	player.velocity = Vector3(22, 0, 0)
	player.angular_velocity = Vector3.ZERO
	player.flipped = false
	player.speed = 22.0
	await _frames(120)
	_check(not player.flipped and player.global_position.y < 1.5, "driving off the edge fast lands on the wheels")
	# A power missile throws the car it hits up and rolls it over.
	_place(outlaw, 0, 70, 90)
	await _frames(3)
	Projectile.spawn(main, "power", outlaw.aim_point() + Vector3(-6, 0, 0), Vector3(1, 0, 0), player, outlaw)
	await _frames(8)
	_check(outlaw.angular_velocity.length() > 1.5 or outlaw.velocity.y > 3.0, "a power missile throws the car and rolls it")
	await _frames(90)
	_place(outlaw, 0, 70, 90)
	var st_car := Roster.get_car("sweet_tooth")
	_check(float(st_car.max_speed) < float(Roster.get_car("outlaw").max_speed) and float(st_car.max_speed) < 34.0 and float(st_car.max_speed) > 31.0, "Sweet Tooth is a heavy truck, 1.26x the round 5 speed (round 11: 10%% slower) (%.1f m/s)" % st_car.max_speed)
	# Remote side hit (owner, round 6): thrown sideways away from the blast, the near side lifted.
	_place(outlaw, 0, 70, 90)
	await _frames(10)
	var side_mine := Mine.new()
	side_mine.owner_car = player
	side_mine.def = WeaponData.get_def("remote")
	main.add_child(side_mine)
	side_mine.global_position = outlaw.global_position + Vector3(-4.5, 0.0, 0.0) # on its left
	var before_x := outlaw.global_position.x
	side_mine.detonate()
	await _frames(30)
	_check(outlaw.global_position.x > before_x + 3.0, "a remote going off beside a car throws it sideways away (%.1f m)" % (outlaw.global_position.x - before_x))
	await _frames(120)
	_place(outlaw, 0, 70, 90)
	# Walls hurt a little; nothing gets out of the stage.
	var wall_hp := player.health
	player.global_transform = main.arena.spot("south_wall_90") # the slam test's spot
	player.velocity = Vector3.ZERO
	player.angular_velocity = Vector3.ZERO
	player.speed = 30.0
	Input.action_press("accelerate")
	await _frames(90)
	Input.action_release("accelerate")
	_check(player.health < wall_hp and player.health > wall_hp - 15.0, "a square wall slam costs a little health (%.1f)" % (wall_hp - player.health))
	player.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 20, 145))
	player.velocity = Vector3(0, 8, 30)
	player.angular_velocity = Vector3.ZERO
	await _frames(90)
	_check(player.global_position.z < 155.0, "no flying out over the fence (z %.1f)" % player.global_position.z)
	_place(player, 40, 70, 90)
	_check(float(st_car.drift_grip) > float(Roster.get_car("spectre").drift_grip), "heavy cars slide less with the handbrake")

	# A car that falls out of the world is put back.
	dog.global_position = Vector3(0, -40, 0)
	await _frames(3)
	_check(dog.global_position.y > -5.0, "a car below the world is put back on the map")

	# AI drives on its own.
	var ai_starts: Array[Vector3] = []
	for i in main.enemies.size():
		(main.enemies[i] as Vehicle).controller = brains[i]
		var t: Transform3D = main.arena.spawn_points[i + 1]
		(main.enemies[i] as Vehicle).global_transform = t
		(main.enemies[i] as Vehicle).velocity = Vector3.ZERO
		ai_starts.append(t.origin)
	await _frames(180)
	var ai_moved := 0
	for i in main.enemies.size():
		if (main.enemies[i] as Vehicle).global_position.distance_to(ai_starts[i]) > 6.0:
			ai_moved += 1
	_check(ai_moved >= 3, "AI enemies drive around (%d of 4)" % ai_moved)

	# AI (owner, play-tests 1 and 2): Outlaw comes at you in attack runs from the front, swings
	# for your back and drifts round for the next run; never glued to you, never stuck.
	for e: Vehicle in main.enemies:
		e.controller = null
	var o_brain: AIDriver = brains[main.enemies.find(outlaw)]
	outlaw.controller = o_brain
	o_brain._retarget = 0.0
	o_brain.drifts = 0
	_place(player, -40, 40, -90)
	_place(outlaw, 10, 40, 90)
	outlaw.health = outlaw.max_health
	player.health = player.max_health
	var closest := INF
	var glued := 0
	var path := 0.0
	var last := outlaw.global_position
	var seen_attack := false
	for k in 720:
		await _frames(1)
		var gap := outlaw.global_position.distance_to(player.global_position)
		closest = minf(closest, gap)
		if gap < 6.0:
			glued += 1
		path += outlaw.global_position.distance_to(last)
		last = outlaw.global_position
		seen_attack = seen_attack or o_brain.mode == "attack"
	_check(seen_attack and closest < 20.0, "AI makes attack runs at you (closest %.1f m)" % closest)
	_check(o_brain.drifts >= 1, "...drifts round for the next run (%d drifts)" % o_brain.drifts)
	# A homing missile coming at it: it breaks to one side (always, at this test's aggression).
	var aggr := o_brain.aggression
	o_brain.aggression = 2.0
	o_brain._dodge_t = 0.0
	o_brain._dodge_scan = 0.0
	Projectile.spawn(main, "homing", outlaw.aim_point() + outlaw.flat_forward() * 22.0 + Vector3.UP, -outlaw.flat_forward(), player, outlaw)
	var dodged := false
	for k in 30:
		await _frames(1)
		dodged = dodged or o_brain._dodge_t > 0.0
	_check(dodged, "AI drifts out of the way of a homing missile")
	o_brain.aggression = aggr
	_check(glued < 180, "...without gluing itself to you (%d of 720 frames within 6 m)" % glued)
	_check(path > 60.0, "...and keeps moving, never stuck (%.0f m driven)" % path)
	# Stuck in the pocket beside a ramp, nose to the battleground wall, with you up top: it backs
	# out, lines up with a ramp (or jumps the wall) and gets up to you.
	var rp: Dictionary = LosAngelesArena.ramp_list()[1]
	var rtop: Vector3 = rp.top
	var pocket := Vector3(rtop.x, 0, rtop.z) + (rp.dir as Vector3) * 4.0 + (rp.side as Vector3) * (LosAngelesArena.RAMP_W * 0.5 + 3.5)
	_place(player, rtop.x - rp.dir.x * 30.0, rtop.z - rp.dir.z * 30.0, 0)
	outlaw.global_transform = Transform3D(Basis.looking_at(-(rp.dir as Vector3), Vector3.UP), LosAngelesArena.ground(pocket.x, pocket.z, 0.1))
	outlaw.velocity = Vector3.ZERO
	outlaw.angular_velocity = Vector3.ZERO
	outlaw.add_ammo("homing", 6) # armed: no detour for pickups
	outlaw.health = outlaw.max_health # healthy: no retreat for health
	outlaw.flipped = false
	o_brain._bad_ramps.clear() # a fresh start: earlier tests may have soured it on this ramp
	o_brain._ramp_goal = {}
	o_brain._ramp_fails = 0
	o_brain._no_jump = 0.0
	for e: Vehicle in main.enemies: # only you to chase: another car wandering by turns its head
		if e != outlaw and not e.is_dead:
			e.controller = null
			e.global_position = Vector3(0, 60, 0)
			e.freeze = true
	var climbed_at := -1
	for k in 2400: # round 7: 1.4x faster cars brake and line up; can tip at a ramp's side (real physics)
		await _frames(1)
		if outlaw.global_position.y > 4.0 and outlaw.is_on_floor():
			climbed_at = k
			break
	_check(climbed_at > 0, "AI stuck beside a ramp finds its way up (%.1f s; mode %s, at %s, ramp %s, target %s)" % [climbed_at / 60.0, o_brain.mode, Vector2(outlaw.global_position.x, outlaw.global_position.z).round(), o_brain._ramp_goal.get("foot", "-"), outlaw.target.car_id if is_instance_valid(outlaw.target) else "none"])
	outlaw.health = outlaw.max_health * 0.2
	await _frames(40)
	_check(o_brain.mode == "retreat", "badly hurt AI breaks away to look for health")
	outlaw.health = outlaw.max_health

	# Damage, death, win.
	victim = main.enemies[0]
	var vhp := victim.health
	victim.invulnerable_time = 0.0
	victim.take_damage(10.0, player)
	_check(is_equal_approx(victim.health, vhp - 10.0), "damage reduces health")
	for e: Vehicle in main.enemies:
		e.invulnerable_time = 0.0
		e.take_damage(9999.0, player)
	await _frames(5)
	_check(main.enemies.all(func(e: Vehicle): return e.is_dead), "enemies can be destroyed")
	_check(main.state == "won", "destroying every enemy wins the match")

	# Lives: two wrecks respawn you, the third is game over.
	main.queue_free()
	await _frames(3)
	main = await _new_game()
	_park(main)
	_check(main.lives == 3, "the player starts with 3 lives")
	for k in 2:
		var p: Vehicle = main.player
		p.invulnerable_time = 0.0
		p.take_damage(9999.0, main.enemies[0])
		await _frames(3)
		_check(main.state == "playing" and main.lives == 2 - k, "wreck %d costs a life, the fight goes on" % (k + 1))
		main._respawn_timer = 0.05
		await _frames(6)
		_check(main.player != p and not main.player.is_dead, "player respawns after a wreck")
		_check(main.player.invulnerable_time > 0.0, "...with a moment of protection")
	main.player.invulnerable_time = 0.0
	main.player.take_damage(9999.0, main.enemies[0])
	await _frames(3)
	_check(main.state == "lost", "losing the last life is game over")

	# Driver pick (pause menu): play as Outlaw, and Sweet Tooth joins the AI.
	main.queue_free()
	await _frames(3)
	main_script.player_car = "outlaw"
	main = await _new_game()
	_check(main.player.car_id == "outlaw" and main.enemies.any(func(e: Vehicle): return e.car_id == "sweet_tooth"), "pick a driver: play Outlaw, Sweet Tooth joins the AI")
	main_script.player_car = "sweet_tooth"

	# Quality preview: only the two detailed cars, one on one.
	main.queue_free()
	await _frames(3)
	main_script.full_roster = false
	main = await _new_game()
	_check(main.enemies.size() == 1 and main.enemies[0].car_id == "outlaw", "preview match: Sweet Tooth vs Outlaw only")
	var fx: VehicleFx = main.player.get_node("Fx")
	_check(fx != null and not (main.player.model.get_meta("gun_spinners", []) as Array).is_empty(), "Sweet Tooth has spinning gatlings")
	var spinner: Node3D = main.player.model.get_meta("gun_spinners")[0]
	var spin_before := spinner.transform.basis
	main.player._fire_guns()
	await _frames(5)
	_check(not spinner.transform.basis.is_equal_approx(spin_before), "firing the guns spins the gatling barrels")
	_check(not main.player.model.find_children("*", "CPUParticles3D", true, false).is_empty(), "the cone sign on Sweet Tooth's roof burns")
	var was_high := GraphicsSettings.high
	GraphicsSettings.high = true
	GraphicsSettings.apply(self)
	var beams := get_nodes_in_group(GraphicsSettings.HEADLIGHT_GROUP)
	_check(not beams.is_empty() and beams.all(func(n: Light3D): return not n.visible or n.get_meta("on", false)), "headlights stay a choice: graphics level doesn't switch them on")
	main.player.toggle_headlights()
	_check(main.player.model.find_children("*", "SpotLight3D", true, false).any(func(n: Light3D): return n.visible), "the headlights button lights them")
	main.player.toggle_headlights()
	GraphicsSettings.high = false
	GraphicsSettings.apply(self)
	_check(beams.all(func(n: Light3D): return not n.visible), "graphics LOW turns them off (owner's laptop)")
	main.player.toggle_headlights()
	var fake: Array = main.player.model.find_children("HeadlightFx", "Node3D", false, false)
	_check(beams.all(func(n: Light3D): return not n.visible) and fake.size() == 1 and (fake[0] as Node3D).visible and (fake[0].get_node("Pool") as Node3D).visible,
		"LOW headlights: no real light (it redraws the stage), a painted beam and ground pool instead")
	main.player.toggle_headlights()
	_check(not (fake[0] as Node3D).visible, "headlights off hides the painted beam")
	GraphicsSettings.high = was_high

	# Round 10: trees go down as real bodies, burning when a weapon did it, then are cleared away.
	var palms: Array = get_nodes_in_group("breakables").filter(func(n: Node): return (n as Breakable).kind == "palm" and not (n as Breakable).is_broken)
	var palm := palms[0] as Breakable
	palm.weapon_hit(50.0, main.player, palm.global_position + Vector3(4, 0, 0), true)
	await _frames(3)
	_check(palm.is_broken and is_instance_valid(palm._fall_body) and palm._fall_fires.size() >= 3, "a palm hit by a weapon falls as a rigid body, on fire")
	var fallen: RigidBody3D = palm._fall_body
	await _frames(70)
	_check(fallen.to_global(Vector3(0, palm.topple_height, 0)).y - palm.global_position.y < 2.5, "...and comes down flat")
	palm._fall_t = 100.0
	await _frames(70)
	_check(not is_instance_valid(fallen), "a fallen tree is cleared away after a few seconds")
	var lamps: Array = get_nodes_in_group("breakables").filter(func(n: Node): return (n as Breakable).kind == "metal" and (n as Breakable).style == Breakable.Style.TOPPLE and not (n as Breakable).is_broken and (n as Breakable).topple_height > 7.9)
	var lamp := lamps[0] as Breakable
	Specials.blast_props(main, lamp.global_position + Vector3(3, 0, 0), 8.0, 50.0, main.player)
	_check(lamp.is_broken and lamp._fall_fires.is_empty(), "a blast knocks down a street light (metal does not burn)")
	_check(is_equal_approx(float(Roster.get_car("sweet_tooth").reverse), 10.0 * Roster.SPEED_SCALE * 1.6 * 1.15), "reverse speed is 1.15x round 9's")
	# Kicker ends are ramps too: a car meeting a kicker end-on rides over it, no wall slam.
	var kick_slams := [0]
	var on_kick_slam := func(_a: Variant = null, _b: Variant = null) -> void: kick_slams[0] += 1
	main.player.wall_slammed.connect(on_kick_slam)
	main.player.health = main.player.max_health
	_place(main.player, -46, -22, 180)
	await _frames(20)
	main.player.speed = 24.0
	var kick_top: float = main.player.global_position.y
	for k in 70:
		await _frames(1)
		kick_top = maxf(kick_top, main.player.global_position.y)
	_check(kick_slams[0] == 0 and main.player.global_position.z > -2.0 and kick_top > LosAngelesArena.PLAT_H + 0.5,
		"a kicker met end-on is a ramp, not a wall (z %.1f, rose %.2f m, slams %d)" % [main.player.global_position.z, kick_top - LosAngelesArena.PLAT_H, kick_slams[0]])
	main.player.wall_slammed.disconnect(on_kick_slam)

	# Round 11: U-turn slides by class (owner): at speed, gas + handbrake + a direction held.
	var ut: Vehicle = main.player
	for e: Vehicle in main.enemies:
		e.controller = null
		e.global_position = Vector3(0, -300, 0)
	var turned := {}
	for run: Array in [["light", false], ["medium", false], ["medium", true], ["heavy", false], ["heavy", true]]:
		ut.stats["uturn"] = run[0]
		_place(ut, -40, 60, 0)
		ut.turbo = 100.0
		await _frames(10)
		Input.action_press("accelerate")
		await _frames(150)
		var f0 := -ut.global_basis.z
		Input.action_press("steer_right")
		Input.action_press("handbrake")
		if run[1]:
			await _frames(45)
			Input.action_press("turbo")
			await _frames(60)
			Input.action_release("turbo")
		else:
			await _frames(105)
		var f1 := -ut.global_basis.z
		turned["%s%s" % [run[0], "+turbo" if run[1] else ""]] = rad_to_deg(Vector2(f0.x, f0.z).angle_to(Vector2(f1.x, f1.z)))
		for a: String in ["accelerate", "steer_right", "handbrake"]:
			Input.action_release(a)
		await _frames(5)
	ut.stats.erase("uturn")
	var deg := func(k: String) -> float: return absf(float(turned[k]))
	_check(deg.call("light") > 165.0, "a light car U-turns about 180 degrees in one slide (%.0f)" % deg.call("light"))
	_check(absf(deg.call("medium") - 160.0) < 12.0, "a mid car stops near 160 (%.0f)" % deg.call("medium"))
	_check(deg.call("medium+turbo") > 168.0, "...and turbo carries it round to 180 (%.0f)" % deg.call("medium+turbo"))
	_check(absf(deg.call("heavy") - 140.0) < 12.0 and absf(deg.call("heavy+turbo") - 140.0) < 12.0,
		"a heavy car stops near 140 and turbo doesn't help (%.0f / %.0f)" % [deg.call("heavy"), deg.call("heavy+turbo")])
	_check(Roster.uturn(Roster.get_car("outlaw")).max == 180.0 and Roster.uturn(Roster.get_car("spectre")).max == 180.0 and Roster.uturn(Roster.get_car("sweet_tooth")).max == 140.0,
		"Outlaw and the light cars turn 180, Sweet Tooth (heavy) 140")
	# Outlaw's turbo tank is 1.4x: a second of boost costs her 20/1.4 of the bar.
	var ol: Vehicle = main.enemies.filter(func(e: Vehicle): return e.car_id == "outlaw")[0]
	ol.turbo = 100.0
	ol._turbo_rest = 0.0
	ol.in_turbo = true
	for k in 60:
		ol._turbo_step(1.0, 1.0 / 60.0)
	ol.in_turbo = false
	_check(absf((100.0 - ol.turbo) - 20.0 / 1.4) < 0.5, "Outlaw's turbo tank lasts 1.4x longer (%.1f used in 1 s)" % (100.0 - ol.turbo))
	# Health refills energy: 5 s of regen (mega 8 s).
	_place(ut, 40, 60, 0)
	ut.health = 50.0
	ut.energy = 0.0
	Pickup.create(main, "health", ut.global_position)
	await _frames(4)
	_check(absf(ut.energy - 5.0 * Vehicle.ENERGY_REGEN) < 1.0, "a health pickup gives 5 s of energy (%.1f)" % ut.energy)

	# ---- Round 12 (owner).
	# Seeker: a homing missile loses its lock for good once the target is past 45 degrees off its nose.
	_place(ut, 40, 60, 0)
	_place(ol, 40, 20, 0) # 40 m ahead (cars face -Z)
	await _frames(2)
	var from12 := ut.global_position + Vector3.UP * 1.5
	var locked := Projectile.spawn(main, "homing", from12, (ol.aim_point() - from12).normalized(), ut, ol)
	var side_dir := Vector3.RIGHT
	var lost := Projectile.spawn(main, "homing", from12, side_dir, ut, ol) # target 90 degrees off its nose
	await _frames(3)
	_check(is_instance_valid(locked) and locked.target == ol, "a homing missile keeps a target inside its seeker cone")
	_check(is_instance_valid(lost) and lost.target == null and lost.direction.angle_to(side_dir) < 0.01,
		"...and past 45 degrees it loses the lock and flies straight on (round 12)")
	for pr in [locked, lost]:
		if is_instance_valid(pr):
			pr.queue_free()
	_check(float(WeaponData.get_def("homing").life) == 2.5 and float(WeaponData.get_def("power").life) == 2.5 and float(WeaponData.get_def("fire").life) == 2.5 and float(WeaponData.get_def("zoomy").life) == 2.5,
		"missiles live 2.5 s, then burst in the air")
	_check(float(WeaponData.get_def("ghost_missile").seek) == 55.0 and not WeaponData.get_def("reaper_skull").has("seek"),
		"Spectre's ghost missile sees +-55 degrees; Grimm's skull is left as it was")
	# Power leaves along the nose even with a lock off to the side (it looked half-homing).
	_place(ol, 52, 30, 0) # ahead and to the right, ~20 degrees off
	await _frames(2)
	ut.launch("power", ol)
	await _frames(1)
	var pw: Projectile = null
	for n in main.get_tree().get_nodes_in_group("projectiles"):
		if n is Projectile and (n as Projectile).shooter == ut and String((n as Projectile).def.get("label", "")) == "Power Missile":
			pw = n
	_check(pw != null and pw.direction.angle_to(ut.aim_forward()) < 0.02, "a power missile leaves straight along the nose (round 12)")
	if pw:
		pw.queue_free()
	# Ammo caps and specials.
	ut.add_ammo("homing", 40)
	ut.add_ammo("power", 40)
	ut.add_ammo("sat", 40)
	_check(ut.ammo["homing"] == 10 and ut.ammo["power"] == 8 and ut.ammo["sat"] == 3, "ammo caps: homing 10, power 8, SAT 3 (%d/%d/%d)" % [ut.ammo["homing"], ut.ammo["power"], ut.ammo["sat"]])
	var fresh := Vehicle.new()
	fresh.setup("spectre", false)
	_check(fresh.ammo["ghost_missile"] == 2 and fresh.special_charges == 3 and Roster.special_max("outlaw") == 4 and Roster.special_max("mr_slam") == 5,
		"every car starts with 2 specials and builds up to its max (Spectre 3, Outlaw 4, Mr. Slam 5)")
	fresh.free()
	# Machine-gun rounds meet a car box 10% bigger than the body.
	var half := Vector3(1.0, 0.75, 2.5) * Projectile.BULLET_BOX
	_check(Projectile.segment_box(Vector3(-5, 0, 2.6), Vector3(5, 0, 2.6), half) >= 0.0 and Projectile.segment_box(Vector3(-5, 0, 2.8), Vector3(5, 0, 2.8), half) < 0.0,
		"a bullet 0.1 m past the body's end still hits (box x1.1)")
	_check(Breakable.MG_HEALTH_LIGHT < 1.1, "glass, stands and tower legs break in two rounds")
	# Pickups: the whole base goes with the item.
	_place(ut, 40, 60, 0)
	await _frames(2)
	var pk := Pickup.create(main, "turbo", ut.global_position + Vector3(0, 0, -12))
	await _frames(2)
	_check(pk._ring != null and pk._ring.visible, "a pickup has a coloured ring around its base")
	pk.global_position = ut.global_position
	await _frames(4)
	_check(not pk.active and not pk._ring.visible and (pk._pad == null or not pk._pad.visible), "picked up: no empty ring or plate is left behind")
	pk.queue_free()
	_check(String(main.arena.get("next_line")) == "Prepare for Paris", "a win reads CONGRATULATIONS / PREPARE FOR PARIS")

	# ---- Round 13 (owner): steering in the air, light cars much more than heavy ones; specials x2 slower.
	var air_turned := {}
	for cls: String in ["light", "heavy"]:
		ut.stats["uturn"] = cls
		ut.global_transform = Transform3D(Basis.IDENTITY, LosAngelesArena.ground(-40, 60, 70.0))
		ut.velocity = Vector3.ZERO
		ut.angular_velocity = Vector3.ZERO
		await _frames(3)
		var a0 := -ut.global_basis.z
		Input.action_press("steer_right")
		await _frames(40)
		Input.action_release("steer_right")
		var a1 := -ut.global_basis.z
		air_turned[cls] = absf(rad_to_deg(Vector2(a0.x, a0.z).angle_to(Vector2(a1.x, a1.z))))
		await _frames(2)
	ut.stats.erase("uturn")
	_place(ut, 40, 60, 0)
	_check(float(air_turned.light) > 40.0 and float(air_turned.heavy) > 12.0 and float(air_turned.heavy) < float(air_turned.light) * 0.7,
		"steering works in the air, light cars turn more than heavy ones (%.0f / %.0f deg in 0.67 s)" % [air_turned.light, air_turned.heavy])
	_check(is_equal_approx(Roster.special_recharge("spectre"), 18.0 * 2.0) and is_equal_approx(Roster.special_recharge("sweet_tooth"), 16.0 * 1.75)
		and is_equal_approx(Roster.special_recharge("outlaw"), 19.0 * 1.75),
		"specials recharge by slots: 3 slots x2, 4 slots x1.75, 5 slots x1.5 (round 14)")
	# Round 14: AI levels and weapon sense.
	_check(LosAngelesArena.level_of(Vector3(55, 11, -42)) == "deck" and LosAngelesArena.level_of(Vector3(0, 9, -128)) == "roof"
		and LosAngelesArena.level_of(Vector3(40, 5, 20)) == "battle" and LosAngelesArena.level_of(Vector3(0, 2.2, 5)) == "battle"
		and LosAngelesArena.level_of(Vector3(130, 0, 0)) == "road",
		"the AI tells road, battleground, tunnel roof and cage deck apart (not by height alone)")
	var brain := AIDriver.new()
	var tgt: Vehicle = ut
	_check(brain._weapon_value("power", 15.0, 0.05, tgt) > brain._weapon_value("homing", 15.0, 0.05, tgt)
		and brain._weapon_value("zoomy", 40.0, 0.3, tgt) > brain._weapon_value("homing", 40.0, 0.3, tgt),
		"AI picks the weapon worth most at the range (power close and dead ahead, zoomy at mid range)")
	# Round 15: driver perks from design chapter 1.
	var ol15: Vehicle = main.enemies.filter(func(e: Vehicle): return e.car_id == "outlaw")[0]
	ol15.energy = 100.0
	ol15.shield_time = 0.0
	ol15.energy_move("shield")
	_check(ol15.shield_time > 0.0 and absf(ol15.energy - 45.0) < 1.0, "Outlaw's Riot Shield costs 55 energy (left %.0f)" % ol15.energy)
	ol15.shield_time = 0.0
	var st15: Vehicle = main.player
	st15.ammo["napalm_cone"] = 0
	st15.health = st15.max_health * 0.2
	st15._special_timer = 0.0
	await _frames(40)
	var laugh_t := st15._special_timer
	var blue := st15._last_laugh
	st15.health = st15.max_health
	st15._special_timer = 0.0
	await _frames(40)
	var calm_t := st15._special_timer
	_check(blue and not st15._last_laugh and laugh_t > calm_t * 1.3,
		"Sweet Tooth's Last Laugh: under 30%% health the special recharges 1.5x faster, roof fire blue (%.2f vs %.2f)" % [laugh_t, calm_t])
	st15.ammo["napalm_cone"] = 2

	# Round 17: burning drivers (owner, from Twisted Metal: Black). Shot, they die and the shooter gets
	# energy; run down fast and head-on they go over the hood into the windshield and are thrown off;
	# run down slowly they are pressed under (the fire out, a black body); a car destroyed on the ground
	# lets its driver climb out burning once the wreck is down; destroyed in the air, it throws them out.
	var spot := LosAngelesArena.ground(-20, 20)
	var me: Vehicle = main.player
	me.shield_time = 0.0
	var dr := BurningDriver.new()
	dr.position = spot
	main.add_child(dr)
	await _frames(3)
	_check(dr.state == BurningDriver.RUN and dr.is_in_group(&"drivers"), "a burning driver runs")
	me.energy = 50.0
	dr.projectile_hit(1.0, me)
	_check(dr.state == BurningDriver.DEAD and is_equal_approx(me.energy, 50.0 + WeaponData.DRIVER_KILL_ENERGY),
		"shooting a burning driver kills them and pays %d energy (now %.0f)" % [int(WeaponData.DRIVER_KILL_ENERGY), me.energy])
	var size: Vector3 = me.stats.size
	var count_corpses := func() -> int: return main.get_children().filter(func(n: Variant) -> bool: return n is DriverCorpse).size()
	var dr2 := BurningDriver.new()
	dr2.position = spot
	main.add_child(dr2)
	await _frames(2)
	_place(me, -20, 24, 0) # 4 m south of them, facing north: they are right ahead
	me.speed = 15.0
	me.linear_velocity = Vector3(0, 0, -15)
	var bodies0: int = count_corpses.call()
	dr2._run_down(me, me.global_transform.affine_inverse() * (dr2.global_position + Vector3.UP * 0.6), size)
	await _frames(1)
	_check(count_corpses.call() == bodies0 + 1 and not is_instance_valid(dr2), "run down fast head-on: thrown into the windshield (a body flies)")
	_place(me, -60, 60, 0) # out of the way, or it runs the next one down before the test does
	var dr3 := BurningDriver.new()
	dr3.position = spot
	main.add_child(dr3)
	await _frames(2)
	_place(me, -20, 24, 0)
	me.speed = 5.0
	me.linear_velocity = Vector3(0, 0, -5)
	dr3._run_down(me, me.global_transform.affine_inverse() * (dr3.global_position + Vector3.UP * 0.6), size)
	_check(is_instance_valid(dr3) and dr3.state == BurningDriver.DEAD and dr3._heat == 0.0 and dr3._burn == 0.0,
		"run down slowly: pressed under, the fire out on a black body")
	_place(me, -60, 60, 0)
	var ol17: Vehicle = main.enemies.filter(func(e: Vehicle): return e.car_id == "outlaw")[0]
	ol17.shield_time = 0.0
	ol17.invulnerable_time = 0.0
	_place(ol17, -20, 60, 0)
	await _frames(20)
	var drivers_before := get_nodes_in_group(&"drivers").size()
	ol17.take_damage(99999.0, me)
	var climbed := false
	for k in 300:
		await physics_frame
		if get_nodes_in_group(&"drivers").size() > drivers_before:
			climbed = true
			break
	_check(climbed, "destroyed on the ground: the driver climbs out burning once the wreck is down")
	me.shield_time = 0.0
	me.invulnerable_time = 0.0
	_place(me, -20, 40, 0)
	me.global_position += Vector3.UP * 8.0
	await _frames(2)
	bodies0 = count_corpses.call()
	me.take_damage(99999.0, ol17)
	_check(me.is_dead and count_corpses.call() == bodies0 + 1, "destroyed in the air: the driver is thrown out of the car")

	print("")
	if _failures.is_empty():
		print("ALL TESTS PASSED")
	else:
		print("%d FAILED: %s" % [_failures.size(), ", ".join(_failures)])
	main.queue_free()
	await _frames(2)
	quit(0 if _failures.is_empty() else 1)
