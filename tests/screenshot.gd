extends SceneTree
## Renders screenshots of the game for review (needs a display; use xvfb-run on servers).
##   godot --rendering-method gl_compatibility --path . -s tests/screenshot.gd -- <shot> <out.png>
## Shots:
##   gameplay   chase camera after a few seconds of driving and shooting
##   hero       close 3/4 view of the player's car
##   enemies    the four AI cars side by side
##   overview   high view over the whole stage
##   roof       on the tunnel roof, looking at the HOLLYWOOD sign
##   tunnel     inside the twin tunnels
##   cage       the caged super health on its deck, and the overpass
##   center     the fire pit, the burnt building and the power tower
##   pit        close view of the fire pit

func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var shot := args[0] if args.size() > 0 else "gameplay"
	var out := args[1] if args.size() > 1 else "screenshot.png"

	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _frames(5)
	var hud: CanvasLayer = main.hud
	var cam: ChaseCamera = main.camera
	var player: Vehicle = main.player

	if shot == "gameplay":
		Input.action_press("accelerate")
		await _frames(70)
		Input.action_press("fire_guns")
		await _frames(25)
	else:
		for v: Vehicle in [player] + main.enemies:
			v.controller = null
		hud.visible = false
		cam.target = null
		await _frames(30)
		match shot:
			"hero":
				_place(cam, player.global_position + Vector3(-6.5, 3.2, -7.5), player.global_position + Vector3(0, 1.6, 0), 50.0)
			"enemies":
				var base := player.global_position + Vector3(14, 0, -18)
				for i in main.enemies.size():
					var e: Vehicle = main.enemies[i]
					var x: float = -9.0 + i * 6.0
					e.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(180 - 12 * (i - 1.5))), LosAngelesArena.ground(base.x + x, base.z, 0.05))
				await _frames(10)
				_place(cam, base + Vector3(0, 3.6, 12.5), base + Vector3(0, 1.0, 0), 60.0)
			"overview":
				_place(cam, Vector3(150, 135, 185), Vector3(-5, 0, 5), 62.0)
			"roof":
				_place(cam, Vector3(-80, 13.5, 20), Vector3(-62, 12, -145), 65.0)
			"tunnel":
				_place(cam, Vector3(-79, 3.0, 45), Vector3(-80, 2.5, 0), 70.0)
			"cage":
				_place(cam, Vector3(85, 24, 20), Vector3(51, 4, -45), 60.0)
			"center":
				_place(cam, Vector3(40, 22, 60), Vector3(-5, 0, -10), 65.0)
			"pit":
				_place(cam, Vector3(0, 12, 34), Vector3(0, -1, 0), 60.0)
	await _frames(15)
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()


func _place(cam: Camera3D, pos: Vector3, look: Vector3, fov: float) -> void:
	cam.global_position = pos
	cam.look_at(look)
	cam.fov = fov
	cam.h_offset = 0.0
	cam.v_offset = 0.0
