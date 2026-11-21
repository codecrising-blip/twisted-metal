extends SceneTree
## Round 25: a long 5-car fight (the player driven by an AI brain too); prints the slowest frames and what was
## alive in them, to find what costs when many cars fight at once.   args: seconds [n]
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var secs := float(args[0]) if args.size() > 0 else 40.0
	var n := int(args[1]) if args.size() > 1 else 5
	var main_script: GDScript = load("res://scripts/main.gd")
	main_script.menu_mode = "deathmatch"
	main_script.player_car = "sweet_tooth"
	main_script.menu_cars = ["sweet_tooth"]
	main_script.menu_foes = ["outlaw", "mr_grimm", "roadkill", "axel"].slice(0, n - 1)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 20:
		await physics_frame
	var brain := AIDriver.new()
	brain.arena = main.arena
	main.player.controller = brain
	var worst: Array = []
	var total := 0.0
	var frames := int(secs * 60.0)
	var last := Time.get_ticks_usec()
	for k in frames:
		await process_frame
		var mode := args[2] if args.size() > 2 else ""
		var audio := main.find_children("*", "AudioStreamPlayer3D", true, false)
		var parts := main.find_children("*", "CPUParticles3D", true, false)
		if mode == "noaudio":
			for a: AudioStreamPlayer3D in audio:
				if a.playing:
					a.stop()
		if mode == "noparticles":
			for c: CPUParticles3D in parts:
				c.process_mode = Node.PROCESS_MODE_DISABLED
				c.emitting = false
		var now := Time.get_ticks_usec()
		var ms := (now - last) / 1000.0
		last = now
		total += ms
		if is_instance_valid(main.player) and main.player.health < main.player.max_health * 0.5:
			main.player.health = main.player.max_health # keep the fight going
		var info := "proj %d  nodes %d  foam %d  drivers %d  particles %d  audio %d" % [
			get_nodes_in_group("projectiles").size(), main.find_children("*", "", true, false).size(),
			main.find_children("*", "FoamFire", true, false).size(), get_nodes_in_group("drivers").size(),
			main.find_children("*", "CPUParticles3D", true, false).size(),
			main.find_children("*", "AudioStreamPlayer3D", true, false).size()] if k % 30 == 0 or ms > 12.0 else ""
		worst.append([ms, k, info])
	worst.sort_custom(func(a, b): return a[0] > b[0])
	print("FIGHT %d cars, %d frames, avg %.2f ms" % [n, frames, total / frames])
	for i in 12:
		print("  %.1f ms at frame %d  %s" % worst[i])
	var census := {}
	for c: CPUParticles3D in main.find_children("*", "CPUParticles3D", true, false):
		var key := "%s/%s emit=%s amt=%d" % [c.get_parent().name, c.name, c.emitting, c.amount]
		census[key] = int(census.get(key, 0)) + 1
	for k in census:
		print("  PART %3d x %s" % [census[k], k])
	var acensus := {}
	for a: AudioStreamPlayer3D in main.find_children("*", "AudioStreamPlayer3D", true, false):
		var key := "%s playing=%s" % [a.stream.resource_path.get_file() if a.stream else "-", a.playing]
		acensus[key] = int(acensus.get(key, 0)) + 1
	for k in acensus:
		print("  SND %3d x %s" % [acensus[k], k])
	var fcensus := {}
	for f: FoamFire in main.find_children("*", "FoamFire", true, false):
		var key := "%s on=%s puffs=%d" % [f.get_parent().name, f.on, f._pos.size()]
		fcensus[key] = int(fcensus.get(key, 0)) + 1
	for k in fcensus:
		print("  FIRE %3d x %s" % [fcensus[k], k])
	var kills := 0
	for e: Vehicle in main.enemies:
		kills += 1 if e.is_dead else 0
	quit()
