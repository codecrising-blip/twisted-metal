extends SceneTree
## Paris draw calls at fixed spots (round 27): xvfb-run ... -s tests/_perf_paris.gd -- paris
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
	var spots := {
		"etoile": [Vector3(-150, 6, -110), Vector3(-150, 4, -168)],
		"quarter_street": [Vector3(-118, 3, -10), Vector3(-150, 8, -40)],
		"roofs": [Vector3(-120, 16, -60), Vector3(-60, 13, -80)],
		"seine_bridge": [Vector3(-30, 9, 8), Vector3(10, -2, 50)],
		"concorde": [Vector3(82, 4, -60), Vector3(82, 3, -100)],
		"st_germain": [Vector3(160, 4, 180), Vector3(160, 4, 120)],
		"champ_de_mars": [Vector3(-190, 6, 200), Vector3(-190, 10, 120)],
		"quay_east": [Vector3(120, 5, 20), Vector3(-60, 3, 30)],
		"high_view": [Vector3(0, 40, 150), Vector3(0, 0, -50)],
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
