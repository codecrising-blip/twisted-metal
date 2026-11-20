extends SceneTree
## Scratch (round 23): a car holding a charged special, filmed from the chase camera at a few hold times, then
## the release. args: out.png [car weapon frames release_frame]   (run with --fixed-fps 60)
## Defaults: Roadkill's charged missiles. Sweet Tooth: sweet_tooth napalm_cone 20,50,90,125,160,200,215,230 210
class Hold:
	extends RefCounted
	var on := true
	func drive(v: Vehicle, _delta: float) -> void:
		v.in_fire_weapon = on


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var car_id := args[1] if args.size() > 1 else "roadkill"
	var weapon := args[2] if args.size() > 2 else "charged_missiles"
	var frames: Array = [60, 150, 285, 300, 335, 345, 355, 370]
	if args.size() > 3:
		frames = Array(args[3].split(",")).map(func(x: String) -> int: return int(x))
	var release := int(args[4]) if args.size() > 4 else 290
	var main_script: GDScript = load("res://scripts/main.gd")
	main_script.player_car = car_id
	main_script.opponent_car = "outlaw"
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 5:
		await process_frame
	main.hud.visible = false
	var me: Vehicle = main.player
	var foe: Vehicle = main.enemies[0]
	foe.controller = null
	me.global_transform = Transform3D(Basis.IDENTITY, LosAngelesArena.ground(20, 30, 0.1))
	foe.global_transform = Transform3D(Basis(Vector3.UP, PI), LosAngelesArena.ground(21, -15, 0.1))
	me.velocity = Vector3.ZERO
	me.target = foe
	for i in 90:
		await physics_frame
	me.ammo[weapon] = 3
	me._refresh_slots()
	me.selected = me.weapon_order.find(weapon)
	var hold := Hold.new()
	me.controller = hold
	me.want_fire_weapon = true
	var shots: Array[Image] = []
	var k := 0
	for f: int in frames:
		while k < f:
			await physics_frame
			k += 1
			if k == release:
				hold.on = false # let go: the salvo
		await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_viewport().get_texture().get_image()
		var w := img.get_width()
		var h := img.get_height()
		img = img.get_region(Rect2i(int(w * 0.25), int(h * 0.15), int(w * 0.5), int(h * 0.6)))
		shots.append(img)
	var sw := shots[0].get_width()
	var sh := shots[0].get_height()
	var sheet := Image.create(sw * 4, sh * 2, false, shots[0].get_format())
	for i in shots.size():
		sheet.blit_rect(shots[i], Rect2i(0, 0, sw, sh), Vector2i((i % 4) * sw, (i / 4) * sh))
	sheet.resize(sheet.get_width() / 2, sheet.get_height() / 2)
	sheet.save_png(args[0])
	quit()
