extends SceneTree
## Scratch (round 21): Axel's sphere blast. args: out_prefix
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
	var ax: Vehicle = main._spawn("axel", Transform3D(Basis.IDENTITY, LosAngelesArena.ground(20, 0, 0.1)), false)
	var ol: Vehicle = main._spawn("outlaw", Transform3D(Basis(Vector3.UP, 1.2), LosAngelesArena.ground(27, -3, 0.1)), false)
	for i in 30:
		await physics_frame
	var cam: Camera3D = main.camera
	cam.target = null
	cam.global_position = ax.global_position + Vector3(-14, 7, 16)
	cam.look_at(ax.global_position + Vector3(2, 1.5, -1))
	cam.fov = 50.0
	Specials.fire(ax, "crowd_controller")
	var k := 0
	for f in [4, 9, 16]:
		while k < f:
			await physics_frame
			k += 1
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png("%s_%d.png" % [args[0], f])
	quit()
