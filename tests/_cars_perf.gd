extends SceneTree
## Round 25 (owner: "it lagged with too many cars at once"): the CPU and draw cost of a match with N cars all
## fighting near the player.   args: n (2..5) [cluster]   Run headless for CPU, with xvfb for draw calls.
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var n := int(args[0]) if args.size() > 0 else 5
	var cluster := "cluster" in args
	var noai := "noai" in args
	var main_script: GDScript = load("res://scripts/main.gd")
	var picks := ["outlaw", "mr_grimm", "roadkill", "axel"]
	main_script.menu_mode = "deathmatch"
	main_script.player_car = "sweet_tooth"
	main_script.menu_cars = ["sweet_tooth"]
	main_script.menu_foes = picks.slice(0, n - 1)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 30:
		await physics_frame
	var player: Vehicle = main.player
	player.controller = null # the player sits still in the middle of it
	player.protect(9999.0)
	if cluster:
		for i in main.enemies.size():
			var e: Vehicle = main.enemies[i]
			var a: float = TAU * i / main.enemies.size()
			e.global_position = player.global_position + Vector3(cos(a), 0.0, sin(a)) * 25.0 + Vector3.UP
	if noai:
		for e: Vehicle in main.enemies:
			e.controller = null
	var phys := 0.0
	var proc := 0.0
	var frames := 0
	var t0 := Time.get_ticks_usec()
	var dc_max := 0
	var dc_sum := 0
	var tri_sum := 0
	for k in (180 if "render" in args else 600):
		await process_frame
		phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		proc += Performance.get_monitor(Performance.TIME_PROCESS)
		frames += 1
		var dc := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		dc_max = maxi(dc_max, dc)
		dc_sum += dc
		tri_sum += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		player.health = player.max_health
	var wall := (Time.get_ticks_usec() - t0) / 1000.0 / frames
	frames = maxi(frames, 1)
	var nodes := main.find_children("*", "", true, false).size()
	print("RENDER draws avg %d max %d  triangles avg %dk" % [dc_sum / frames, dc_max, tri_sum / frames / 1000])
	print("CARS %d cluster %s  physics %.2f ms  process %.2f ms  wall %.2f ms/frame  draws max %d  nodes %d  projectiles %d" % [
		n, cluster, phys / frames * 1000.0, proc / frames * 1000.0, wall, dc_max, nodes, main.get_tree().get_nodes_in_group("projectiles").size()])
	quit()
