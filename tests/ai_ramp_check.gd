extends SceneTree
## AI ramp check (round 7): from the pocket beside each ramp (both sides), how often and how fast the AI
## gets up onto the battleground. Run: godot --headless --fixed-fps 60 --path . -s tests/ai_ramp_check.gd -- full
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var results := []
	var ok := 0
	for trial in 12:
		seed(trial * 7919 + 13)
		var main: Node = load("res://scenes/main.tscn").instantiate()
		root.add_child(main)
		for i in 5:
			await physics_frame
		var player: Vehicle = main.player
		player.controller = null
		var outlaw: Vehicle = main.enemies.filter(func(e: Vehicle): return e.car_id == "outlaw")[0]
		for e: Vehicle in main.enemies:
			if e != outlaw:
				e.controller = null
				e.global_position = Vector3(0, 60, 0)
				e.freeze = true
		var o_brain: AIDriver = outlaw.controller
		var ri: int = [1, 0, 2, 3][trial % 4]
		var rp: Dictionary = LosAngelesArena.ramp_list()[ri]
		var rtop: Vector3 = rp.top
		var side := 1.0 if (trial / 4) % 2 == 0 else -1.0
		var pocket := Vector3(rtop.x, 0, rtop.z) + (rp.dir as Vector3) * 4.0 + (rp.side as Vector3) * side * (LosAngelesArena.RAMP_W * 0.5 + 3.5)
		# 14 m in from the edge (round 13: 30 m in put ramp 3's player inside the cage deck; it fell
		# through the floor and the AI was chasing a car on the road)
		player.global_transform = Transform3D(Basis.IDENTITY, LosAngelesArena.ground(rtop.x - rp.dir.x * 14.0, rtop.z - rp.dir.z * 14.0, 0.1))
		outlaw.global_transform = Transform3D(Basis.looking_at(-(rp.dir as Vector3), Vector3.UP), LosAngelesArena.ground(pocket.x, pocket.z, 0.1))
		outlaw.add_ammo("homing", 6)
		var climbed := -1.0
		for k in 2400:
			await physics_frame
			outlaw.health = outlaw.max_health
			if outlaw.global_position.y > 4.0 and outlaw.is_on_floor():
				climbed = k / 60.0
				break
		ok += int(climbed > 0)
		results.append("ramp %d side %+d: %s (end %s)" % [ri, side, ("%.1f s" % climbed) if climbed > 0 else "FAILED", Vector2(outlaw.global_position.x, outlaw.global_position.z).round()])
		main.queue_free()
		await process_frame
	for r: String in results:
		print("RAMP ", r)
	print("RAMP ok %d/12" % ok)
	quit()
