extends SceneTree
## Scratch (round 19): the four Sweet Bot candidates (assets/models/sweet_bots.glb) in a row behind
## Sweet Tooth on the LA battleground, for the owner to pick. args: view(front|back|close_a..d|side) out.png


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var view := args[0]
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 5:
		await process_frame
	main.hud.visible = false
	var p: Vehicle = main.player
	p.controller = null
	p.invulnerable_time = 0.0
	p._visual.visible = true
	for e: Vehicle in main.enemies:
		e.controller = null
		e.global_position = Vector3(0, 80, 0)
		e.freeze = true
	var base := LosAngelesArena.ground(-40, 40)
	p.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(90)), base + Vector3(0, 0.1, 0)) # facing -X
	var bots: Array[Node3D] = []
	for k in 4:
		var tag: String = "abcd"[k]
		var b := Node3D.new()
		b.add_child(ModelLib.instance("sweet_bots", "bot_" + tag))
		main.add_child(b)
		var at := base + Vector3(7.5, 0, (k - 1.5) * 3.6)
		b.global_position = LosAngelesArena.ground(at.x, at.z)
		b.rotation.y = deg_to_rad(-90) # facing +X: away from the truck, like the real one
		for mi in b.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		bots.append(b)
	var cam: ChaseCamera = main.camera
	cam.target = null
	cam.fov = 50.0
	var mid := base + Vector3(7.5, 1.0, 0)
	match view:
		"front":
			cam.global_position = mid + Vector3(9.0, 1.6, 1.5)
			cam.look_at(mid + Vector3(0, 0.2, 0))
		"back":
			cam.global_position = mid + Vector3(-7.0, 2.2, -3.0)
			cam.look_at(mid + Vector3(0, 0.3, 0))
		"side":
			cam.global_position = mid + Vector3(6.0, 1.4, 11.0)
			cam.look_at(mid + Vector3(0, 0.2, 0))
		_:
			var k := "abcd".find(view.substr(6, 1))
			var b := bots[maxi(k, 0)]
			var c := b.global_position + Vector3(0, 1.55, 0)
			cam.fov = 40.0
			cam.global_position = c + Vector3(5.2, 0.5, 2.3)
			cam.look_at(c)
	for i in 60:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(args[1])
	quit()
