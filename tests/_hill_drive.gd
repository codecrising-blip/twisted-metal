extends SceneTree
## Scratch (round 21): drive a car over the west road hill (-135, -58) and log what happens.
class Pad:
	extends RefCounted
	var turbo := false
	var steer := 0.0
	func drive(v: Vehicle, _d: float) -> void:
		v.in_throttle = 1.0
		v.in_steer = steer
		v.in_turbo = turbo

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var id := args[0] if args.size() > 0 else "mr_grimm"
	var yaw := float(args[1]) if args.size() > 1 else 0.0
	var turbo := args.size() > 2 and args[2] == "turbo"
	var sx := float(args[3]) if args.size() > 3 else -133.6
	var sz := float(args[4]) if args.size() > 4 else -10.0
	var frames := int(args[5]) if args.size() > 5 else 300
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 20: await physics_frame
	for e: Vehicle in main.enemies: e.controller = null; e.global_position = Vector3(0, 30, 300)
	var v: Vehicle = main._spawn(id, Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), LosAngelesArena.ground(sx, sz, 0.2)), false)
	main.player.global_position = Vector3(50, 30, 50)
	var pad := Pad.new()
	pad.turbo = turbo
	v.controller = pad
	v.turbo = 100.0
	var worst := 0.0
	var log := []
	for i in frames:
		await physics_frame
		var up := v.global_basis.y
		var tilt := rad_to_deg(acos(clampf(up.y, -1, 1)))
		var roll := rad_to_deg(asin(clampf(v.global_basis.x.y, -1, 1)))
		worst = maxf(worst, tilt)
		if i % 6 == 0:
			log.append("%d z %.1f y %.2f v %.1f tilt %.0f roll %.0f ground %s flipped %s" % [i, v.global_position.z, v.global_position.y, v.speed, tilt, roll, v.is_on_floor(), v.flipped])
		if sx < -120.0 and v.global_position.z < -95.0:
			break
	for l in log: print(l)
	print("RESULT ", id, " yaw ", yaw, " turbo ", turbo, " worst tilt ", worst, " flipped ", v.flipped)
	quit()
