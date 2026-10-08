extends SceneTree
## Renders screenshots of the game for review (needs a display; use xvfb-run on servers).
##   godot --rendering-method gl_compatibility --path . -s tests/screenshot.gd -- <shot> <out.png>
## Shots:
##   gameplay   chase camera after a few seconds of driving and shooting
##   hero       close 3/4 view of the player's car
##   enemies    the two AI cars side by side
##   overview   high view over the yard

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

	match shot:
		"gameplay":
			Input.action_press("accelerate")
			await _frames(70)
			Input.action_press("fire_guns")
			await _frames(25)
		"hero", "enemies", "overview":
			for v: Vehicle in [player] + main.enemies:
				v.controller = null
			hud.visible = false
			cam.target = null
			await _frames(30)
			if shot == "hero":
				_place(cam, player.global_position + Vector3(-6.5, 3.2, -7.5), player.global_position + Vector3(0, 1.6, 0), 50.0)
			elif shot == "enemies":
				var a: Vehicle = main.enemies[0]
				var b: Vehicle = main.enemies[1]
				var base := player.global_position + Vector3(0, 0, -16)
				a.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(150)), base + Vector3(-3.5, 0.05, 0))
				b.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(-150)), base + Vector3(3.5, 0.05, 0))
				await _frames(10)
				_place(cam, base + Vector3(0, 3.0, 10.5), base + Vector3(0, 1.2, 0), 55.0)
			else:
				_place(cam, Vector3(55, 70, 95), Vector3(0, 0, 0), 60.0)
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
