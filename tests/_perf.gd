extends SceneTree
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 5:
		await process_frame
	for v: Vehicle in [main.player] + main.enemies:
		v.controller = null
	main.hud.visible = false
	var cam: ChaseCamera = main.camera
	cam.target = null
	var T: Vector3 = LosAngelesArena.TOWER_AT
	var spots := {
		"tower_cables": [T + Vector3(-14, 9, 14), T + Vector3(0, 18, 0)],
		"wall_powerline": [Vector3(80, 6, -135), Vector3(80, 9, -150)],
		"center": [Vector3(0, 12, 50), Vector3(0, 4, 0)],
		"road_south": [Vector3(-10, 4, 150), Vector3(30, 2, 120)],
		"tunnel": [Vector3(-46, 3, -121), Vector3(0, 2.5, -121)],
		"far_corner": [Vector3(-140, 5, 140), Vector3(0, 5, 0)],
	}
	var counts := {"MeshInstance3D": 0, "OmniLight3D": 0, "SpotLight3D": 0, "CPUParticles3D": 0, "Label3D": 0}
	for k in counts.keys():
		counts[k] = main.find_children("*", k, true, false).size()
	print("NODES ", counts)
	for name: String in spots:
		cam.global_position = spots[name][0]
		cam.look_at(spots[name][1])
		for i in 3:
			await process_frame
		var t0 := Time.get_ticks_usec()
		for i in 10:
			await process_frame
		var ms := (Time.get_ticks_usec() - t0) / 10000.0
		var dc := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		var ob := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
		var pr := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		print("SPOT %-15s draw_calls %5d objects %5d primitives %8d frame %.1f ms" % [name, dc, ob, pr, ms])
	quit()
