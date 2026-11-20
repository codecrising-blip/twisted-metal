extends SceneTree
## Scratch (round 21): Grimm's skull in flight, filmed from beside and from ahead. args: out_prefix
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 5:
		await process_frame
	main.hud.visible = false
	for v: Vehicle in [main.player] + main.enemies:
		v.global_position += Vector3(0, -200, 0)
		v.visible = false
	var grimm: Vehicle = main.player
	var cam: Camera3D = main.camera
	cam.target = null
	var shots := [["side", Vector3(7, 0.6, 0), 0.45], ["front", Vector3(3.5, 1.0, -7), 0.45], ["chase", Vector3(-1.5, 1.8, 7), 0.45]]
	for s in shots:
		var start := LosAngelesArena.ground(20, 0, 2.2)
		var p := Projectile.spawn(main, "reaper_skull", start, Vector3(0, 0, -1), grimm, null)
		p._life = 99.0
		var t := float(s[2])
		var n := int(t * 60.0)
		for i in n:
			await physics_frame
		var at := p.global_position
		cam.global_position = at + s[1]
		cam.look_at(at)
		cam.fov = 38.0
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png("%s_%s.png" % [args[0], s[0]])
		p.queue_free()
		for i in 10:
			await process_frame
	quit()
