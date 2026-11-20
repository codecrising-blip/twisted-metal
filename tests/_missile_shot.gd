extends SceneTree
## Scratch (round 22): missiles side by side in flight, filmed from beside: homing, fire, charged, charged red.
## args: out.png
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
	var car: Vehicle = main.player
	var cam: Camera3D = main.camera
	cam.target = null
	var def := WeaponData.get_def("charged_missiles")
	var rc: Color = def.get("red_color", Color(0.86, 0.04, 0.2))
	var red := {"color": rc, "trail": rc.lerp(Color.WHITE, 0.15), "speed": float(def.get("red_speed", 70.0))}
	var rows := [["homing", {}], ["fire", {}], ["charged_missiles", {}], ["charged_missiles", red]]
	var ps: Array[Projectile] = []
	for i in rows.size():
		var start := LosAngelesArena.ground(20, 30, 2.0) + Vector3(i * 1.6, 0, 0)
		var p := Projectile.spawn(main, rows[i][0], start, Vector3(0, 0, -1), car, null, rows[i][1])
		p._life = 99.0
		p.def["speed"] = 30.0 # same speed so they stay in a row
		ps.append(p)
	for i in 24:
		await physics_frame
	var mid := Vector3.ZERO
	for p in ps:
		mid += p.global_position
	mid /= ps.size()
	cam.global_position = mid + Vector3(9.0, 2.2, 3.0)
	cam.look_at(mid + Vector3(0, 0, 1.0))
	cam.fov = 40.0
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(args[0])
	quit()
