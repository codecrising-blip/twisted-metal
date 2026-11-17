extends SceneTree
## Scratch (round 18): what the headlights cost. The player drives on in a chase view: frame times with
## the lights off, the frames right after switching them on (a build stall?), then with them on.
func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> Array:
	var times: Array = []
	var last := Time.get_ticks_usec()
	for i in n:
		await process_frame
		var now := Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		last = now
	return times


func _avg(a: Array) -> float:
	var s := 0.0
	for v: float in a:
		s += v
	return s / maxf(a.size(), 1)


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 30:
		await process_frame
	var p: Vehicle = main.player
	for e: Vehicle in main.enemies:
		e.controller = null
		e.global_position = Vector3(120, 60, 120)
		e.freeze = true
	p.controller = null
	p.global_transform = Transform3D(Basis.IDENTITY, LosAngelesArena.ground(-20, 60) + Vector3(0, 0.1, 0))
	for i in 120:
		await process_frame
	var off: Array = await _frames(150)
	p.toggle_headlights()
	var first: Array = await _frames(10)
	var on: Array = await _frames(150)
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: # a look at the beam
		if args.size() > 1 and args[1] == "top":
			var cam: ChaseCamera = main.camera
			cam.target = null
			cam.global_position = p.global_position + Vector3(6, 14, -6)
			cam.look_at(p.global_position + Vector3(0, 0, -14))
			for i in 3:
				await process_frame
		await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png(args[0])
	p.toggle_headlights()
	var off2: Array = await _frames(150)
	print("LIGHTS off %.2f ms | first frames after on %s | on %.2f ms | off again %.2f ms" % [_avg(off), str(first.map(func(v): return snappedf(v, 0.1))), _avg(on), _avg(off2)])
	quit()
