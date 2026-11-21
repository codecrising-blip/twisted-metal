extends SceneTree
## Round 24: shots of every front-end screen (main, options, players, the world map on two stages, driver select
## before and after a pick, the title card).   args: out_dir   (xvfb, like screenshot.gd)
func _initialize() -> void:
	_run.call_deferred()


func _snap(dir: String, name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [dir, name])
	print("shot ", name)


func _wait(s: float) -> void:
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < s * 1000.0:
		await process_frame


func _run() -> void:
	var dir := OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(dir)
	var fe: FrontEnd = load("res://scenes/front_end.tscn").instantiate()
	root.add_child(fe)
	print("front end size ", fe.size)
	await _wait(0.6)
	await _snap(dir, "1_main")
	fe._show_options()
	await _wait(0.3)
	await _snap(dir, "2_options")
	fe._mode = "deathmatch"
	fe._players = 3
	fe._show_players()
	await _wait(0.3)
	await _snap(dir, "3_players")
	fe._show_stage()
	await _wait(0.4)
	await _snap(dir, "4_stage_la")
	fe._stage = 2
	fe._focus_stage(true)
	await _wait(0.7)
	await _snap(dir, "5_stage_chernobyl")
	fe._stage = 0
	fe._cars.clear()
	fe._foes.clear()
	fe._players = 1
	fe._picking = 0
	fe._picking_foes = false
	fe._show_cars()
	for i in fe.CARS.size():
		fe._car_i = i
		fe._show_car()
		await _wait(0.5)
		await _snap(dir, "6_car_%s" % fe.CARS[i])
	fe._car_i = 1
	fe._show_car()
	await _wait(0.3)
	fe._pick_car()
	await _wait(0.4)
	await _snap(dir, "7_picked_outlaw")
	await _wait(1.6)
	fe._car_i = 2
	fe._show_car()
	await _wait(0.4)
	await _snap(dir, "8_opponents")
	fe._show_loading()
	await _wait(0.6)
	await _snap(dir, "9_loading")
	quit()
