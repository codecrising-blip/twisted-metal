extends SceneTree
## AI bridge check (round 13): reaching a target on another level (tunnel roof, cage deck, road) and coming
## back down. Run: godot --headless --fixed-fps 60 --path . -s tests/ai_bridge_check.gd   (6/6 in round 13)
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var cases := [
		["roof from battleground", Vector3(0, 9, -128), Vector3(-50, 0, -40)],
		["roof from far side", Vector3(0, 9, -128), Vector3(60, 0, 20)],
		["cage from battleground", LosAngelesArena.DECK_CENTER + Vector3(0, 6, -4), Vector3(-30, 0, 40)],
		["cage from road", LosAngelesArena.DECK_CENTER + Vector3(0, 6, -4), Vector3(120, 0, 60)],
		["road from cage deck", Vector3(125, 0, 40), LosAngelesArena.DECK_CENTER + Vector3(0, 0, -4)],
		["road from tunnel roof", Vector3(-40, 0, 125), Vector3(0, 0, -128)],
	]
	var ok := 0
	for c: Array in cases:
		seed(7)
		var main: Node = load("res://scenes/main.tscn").instantiate()
		root.add_child(main)
		for i in 5:
			await physics_frame
		var player: Vehicle = main.player
		player.controller = null
		var outlaw: Vehicle = main.enemies.filter(func(e: Vehicle): return e.car_id == "outlaw")[0]
		var pp: Vector3 = c[1]
		player.global_transform = Transform3D(Basis.IDENTITY, (LosAngelesArena.ground(pp.x, pp.z, 0.2) if pp.y == 0.0 else pp + Vector3.UP * 0.2))
		var st: Vector3 = c[2]
		var start_at := LosAngelesArena.ground(st.x, st.z, 0.1)
		if String(c[0]).ends_with("cage deck"):
			start_at = LosAngelesArena.DECK_CENTER + Vector3(0, LosAngelesArena.DECK_Y + 0.2, -4)
		elif String(c[0]).ends_with("tunnel roof"):
			start_at = Vector3(0, LosAngelesArena.ROOF_Y + 0.2, -128)
		outlaw.global_transform = Transform3D(Basis.IDENTITY, start_at)
		outlaw.add_ammo("homing", 6)
		var got := -1.0
		for k in 3600:
			await physics_frame
			outlaw.health = outlaw.max_health
			player.health = player.max_health
			if absf(outlaw.global_position.y - player.global_position.y) < 1.2 and outlaw.is_on_floor() and outlaw.global_position.distance_to(player.global_position) < 40.0:
				got = k / 60.0
				break
		ok += int(got > 0)
		print("BRIDGE %-24s %s  (player y %.1f, ai at %s)" % [c[0], ("%.1f s" % got) if got > 0 else "FAILED", player.global_position.y, outlaw.global_position.round()])
		main.queue_free()
		await process_frame
	print("BRIDGE ok %d/%d" % [ok, cases.size()])
	quit()
