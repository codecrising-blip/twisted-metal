extends SceneTree
## Scratch (round 23): one projectile in flight filmed up close from beside, ahead and behind, as one sheet.
## args: weapon_id out.png [charged]   (run with --fixed-fps 60)
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var id := args[0]
	var over := {}
	if args.size() > 2 and args[2] == "charged":
		var d := WeaponData.get_def(id)
		over = {"charged": true, "damage": float(d.get("charged_damage", 90.0)), "homing": 0.0}
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 5:
		await process_frame
	main.hud.visible = false
	for v: Vehicle in [main.player] + main.enemies:
		v.global_position += Vector3(0, -200, 0)
		v.visible = false
	var shooter: Vehicle = main.player
	var cam: Camera3D = main.camera
	cam.target = null
	var shots := [Vector3(6, 0.8, 0), Vector3(3.5, 1.2, -7), Vector3(-1.5, 2.0, 8)]
	var imgs: Array[Image] = []
	for off: Vector3 in shots:
		var start := LosAngelesArena.ground(20, 20, 2.2)
		var p := Projectile.spawn(main, id, start, Vector3(0, 0, -1), shooter, null, over)
		p._life = 99.0
		for i in 18:
			await physics_frame
		var at := p.global_position
		cam.global_position = at + off
		cam.look_at(at)
		cam.fov = 40.0
		await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_viewport().get_texture().get_image()
		img.resize(img.get_width() / 2, img.get_height() / 2)
		imgs.append(img)
		p.queue_free()
		for i in 6:
			await process_frame
	var w := imgs[0].get_width()
	var h := imgs[0].get_height()
	var sheet := Image.create(w * imgs.size(), h, false, imgs[0].get_format())
	for i in imgs.size():
		sheet.blit_rect(imgs[i], Rect2i(0, 0, w, h), Vector2i(i * w, 0))
	sheet.save_png(args[1])
	quit()
