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
	v.speed = 0.0


func _park(main: Node) -> void:
	for e: Vehicle in main.enemies:
		e.controller = null


func _run() -> void:
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
	var brains: Array = main.enemies.map(func(e: Vehicle): return e.controller)
	_park(main)
	var enemy_starts: Array = main.enemies.map(func(e: Vehicle): return e.global_position)

	# Driving: the player starts on the south road facing east, toward the three humps.
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

	# Energy jump, and the pause in energy regen after spending.
	_place(player, -60, 60, 0)
	await _frames(30)
	var y0 := player.global_position.y
	var e0 := player.energy
	await _tap("energy_jump")
	await _frames(8)
	_check(player.global_position.y > y0 + 0.8, "energy jump lifts the car (%.2f m)" % (player.global_position.y - y0))
	_check(player.energy < e0, "jump costs energy")
	var e1 := player.energy
	await _frames(30)
	_check(is_equal_approx(player.energy, e1), "no energy regen for a moment after spending")

	# Freeze, ice breaking, Grit.
	var victim: Vehicle = main.enemies[0]
	_check(victim.freeze(2.0), "freeze holds a car")
	victim.take_damage(5.0, player)
	_check(victim.frozen_time > 0.0, "a small hit does not break the ice")
	victim.take_damage(20.0, player)
	_check(victim.frozen_time <= 0.0, "a hit of 15+ shatters the ice")
	_check(not victim.freeze(2.0), "Grit: can't be frozen again right away")

	# Health pickup: 30% of max health.
	player.health = 100.0
	var hp := Pickup.create(main, "health", player.global_position)
	await _frames(4)
	_check(absf(player.health - (100.0 + 328.0 * 0.3)) < 0.5, "health pickup heals 30%% of max (%.1f)" % (player.health - 100.0))
	if is_instance_valid(hp):
		hp.queue_free()
	await _frames(1)

	# Ram damage by weight: heavy Sweet Tooth into medium Outlaw at 30 m/s closing.
	var outlaw: Vehicle = main.enemies.filter(func(e: Vehicle): return e.car_id == "outlaw")[0]
	outlaw.velocity = Vector3.ZERO
	var o_hp := outlaw.health
	var p_hp := player.health
	player._ram(outlaw, Vector3(0, 0, -30), Vector3(0, 0, 1))
	var expected := (30.0 - 10.0) * 0.5 * sqrt(2.0 / 1.4)
	_check(absf((o_hp - outlaw.health) - expected) < 0.1, "ram damage follows the weight formula (%.1f)" % (o_hp - outlaw.health))
	_check(absf((p_hp - player.health) - expected * 0.1) < 0.1, "the heavier rammer takes 10%% back")

	# Wall slide: 45 degrees into the north wall keeps most of the speed and turns along it.
	player.health = player.max_health
	_place(player, -40, -112, -45)
	player.speed = 30.0
	Input.action_press("accelerate")
	await _frames(70)
	var fwd := player.flat_forward()
	Input.action_release("accelerate")
	_check(absf(player.speed) > 15.0, "a 45-degree wall hit keeps the car moving (%.1f m/s)" % player.speed)
	_check(fwd.x > 0.85, "...and turns it along the wall")
	# Square hit: bounces off and turns, never stops dead.
	_place(player, 10, -112, 0)
	player.speed = 30.0
	Input.action_press("accelerate")
	await _frames(90)
	fwd = player.flat_forward()
	Input.action_release("accelerate")
	_check(absf(fwd.x) > 0.3, "a square wall hit turns the nose toward the open side")
	_check(Vector2(player.velocity.x, player.velocity.z).length() > 6.0, "...and the car keeps going without reversing")

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
	Specials.fire(outlaw, "omni_taser")
	_check(outlaw.has_live_special(), "taser links to a car in range")
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
	_place(dog, 60, -60, 0)
	await _frames(2)
	outlaw.ammo["omni_taser"] = 2
	outlaw.selected = 0
	outlaw._weapon_cooldown = 0.0
	outlaw._fire_selected()
	await _frames(3)
	_check(outlaw.ammo["omni_taser"] == 1 and not outlaw.has_live_special(), "firing the taser with nobody in range wastes the charge")
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

	# Mr. Grimm's skull: three hits kill a medium car.
	_place(outlaw, -20, 20, 0)
	await _frames(3)
	outlaw.health = outlaw.max_health
	outlaw.invulnerable_time = 0.0
	var o_hp3 := outlaw.health
	Projectile.spawn(main, "reaper_skull", outlaw.aim_point() + Vector3(0, 0, 8), Vector3(0, 0, -1), grimm, outlaw)
	await _frames(12)
	_check(absf((o_hp3 - outlaw.health) - 94.0) < 0.5, "Reaper Skull hits for 94 (3 kill a medium car)")

	# Spectre's ghost missile flies through the burnt building's wall.
	var spectre: Vehicle = main.enemies.filter(func(e: Vehicle): return e.car_id == "spectre")[0]
	_place(spectre, -52, -45, -90)
	_place(dog, -32, -45, 90)
	await _frames(3)
	var g_hp := dog.health
	Projectile.spawn(main, "ghost_missile", spectre.aim_point() + Vector3(2, 0, 0), Vector3(1, 0, 0), spectre, dog)
	await _frames(40)
	_check(g_hp - dog.health >= 23.0, "ghost missile passes through walls")

	# Napalm Cone lands on a parked target and sets it on fire.
	_place(player, 60, 40, 90)
	_place(outlaw, 30, 40, 90)
	player.target = outlaw
	player.auto_target = false
	await _frames(3)
	var n_hp := outlaw.health
	player.ammo["napalm_cone"] = 2
	player.selected = 0
	player._weapon_cooldown = 0.0
	player._fire_selected()
	await _frames(100)
	_check(n_hp - outlaw.health >= 15.0, "Napalm Cone lands on the target (%.1f)" % (n_hp - outlaw.health))
	_check(outlaw.burn_time > 0.0 or n_hp - outlaw.health > 30.0, "...and sets it on fire")
	player.auto_target = true

	# A car that falls out of the world is put back.
	dog.global_position = Vector3(0, -40, 0)
	await _frames(3)
	_check(dog.global_position.y > -5.0, "a car below the world is put back on the map")

	# AI drives on its own.
	for i in main.enemies.size():
		(main.enemies[i] as Vehicle).controller = brains[i]
		_place(main.enemies[i], [88.0, 40.0, -79.0, -30.0][i], [40.0, -88.0, -60.0, 40.0][i], [0.0, 90.0, 180.0, 0.0][i])
	await _frames(180)
	var ai_moved := 0
	for i in main.enemies.size():
		if (main.enemies[i] as Vehicle).global_position.distance_to(Vector3([88.0, 40.0, -79.0, -30.0][i], 0, [40.0, -88.0, -60.0, 40.0][i])) > 6.0:
			ai_moved += 1
	_check(ai_moved >= 3, "AI enemies drive around (%d of 4)" % ai_moved)

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
	var main_script: GDScript = load("res://scripts/main.gd")
	main_script.player_car = "outlaw"
	main = await _new_game()
	_check(main.player.car_id == "outlaw" and main.enemies.any(func(e: Vehicle): return e.car_id == "sweet_tooth"), "pick a driver: play Outlaw, Sweet Tooth joins the AI")
	main_script.player_car = "sweet_tooth"

	print("")
	if _failures.is_empty():
		print("ALL TESTS PASSED")
	else:
		print("%d FAILED: %s" % [_failures.size(), ", ".join(_failures)])
	main.queue_free()
	await _frames(2)
	quit(0 if _failures.is_empty() else 1)
