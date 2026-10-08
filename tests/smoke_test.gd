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


func _run() -> void:
	var main: Node = await _new_game()
	var player: Vehicle = main.player
	_check(player != null and player.car_id == "sweet_tooth", "Sweet Tooth spawned as the player")
	_check(main.enemies.size() == 2, "two AI enemies spawned")
	_check(get_nodes_in_group("pickups").size() >= 12, "weapon and health pickups placed")
	_check(player.is_on_floor(), "player rests on the ground")

	# Park the AI so it can't freeze or shoot the player during the input checks.
	var brains: Array = main.enemies.map(func(e: Vehicle): return e.controller)
	for e: Vehicle in main.enemies:
		e.controller = null

	# Driving.
	var start := player.global_position
	var enemy_starts: Array = main.enemies.map(func(e: Vehicle): return e.global_position)
	Input.action_press("accelerate")
	await _frames(120)
	Input.action_release("accelerate")
	var moved := player.global_position.distance_to(start)
	_check(moved > 8.0, "player drives forward (%.1f m in 2 s)" % moved)
	_check(player.global_position.z < start.z, "forward is toward the arena center")

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

	# Special weapon.
	var special := player.special_id
	var before: int = player.ammo[special]
	await _tap("fire_weapon")
	_check(player.ammo[special] == before - 1, "special weapon (Laughing Ghost) fires")

	# Weapon pickup.
	var had: int = player.ammo.get("homing", 0)
	player.add_ammo("homing", 3)
	_check(player.weapon_order.has("homing") and player.ammo["homing"] == had + 3, "picked-up weapon added to inventory")
	var sel := player.selected
	await _tap("weapon_next")
	_check(player.selected == wrapi(sel + 1, 0, player.weapon_order.size()), "weapon cycling selects the next weapon")

	# Energy jump.
	await _frames(30)
	var y0 := player.global_position.y
	var e0 := player.energy
	await _tap("energy_jump")
	await _frames(8)
	_check(player.global_position.y > y0 + 0.8, "energy jump lifts the car (%.2f m)" % (player.global_position.y - y0))
	_check(player.energy < e0, "jump costs energy")

	# Freeze.
	var victim: Vehicle = main.enemies[0]
	victim.freeze(1.0)
	_check(victim.frozen_time > 0.0, "freeze holds a car")

	# AI drives on its own.
	for i in main.enemies.size():
		(main.enemies[i] as Vehicle).controller = brains[i]
	await _frames(180)
	var ai_moved := false
	for i in main.enemies.size():
		if (main.enemies[i] as Vehicle).global_position.distance_to(enemy_starts[i]) > 6.0:
			ai_moved = true
	_check(ai_moved, "AI enemies drive around")

	# Damage, death, win.
	victim = main.enemies[0]
	var hp := victim.health
	victim.take_damage(10.0, player)
	_check(is_equal_approx(victim.health, hp - 10.0), "damage reduces health")
	for e: Vehicle in main.enemies:
		e.take_damage(9999.0, player)
	await _frames(5)
	_check(main.enemies.all(func(e: Vehicle): return e.is_dead), "enemies can be destroyed")
	_check(main.state == "won", "destroying every enemy wins the match")

	# Losing.
	main.queue_free()
	await _frames(3)
	main = await _new_game()
	main.player.take_damage(9999.0, main.enemies[0])
	await _frames(3)
	_check(main.state == "lost", "player death loses the match")

	print("")
	if _failures.is_empty():
		print("ALL TESTS PASSED")
	else:
		print("%d FAILED: %s" % [_failures.size(), ", ".join(_failures)])
	main.queue_free()
	await _frames(2)
	quit(0 if _failures.is_empty() else 1)
