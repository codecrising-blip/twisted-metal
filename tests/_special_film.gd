extends SceneTree
## Scratch (round 23): films a special from the player's chase camera as a frame sheet.
## args: car_id weapon_id out.png [frames comma list] [extra: "secondary" = fire the R L U move instead]
## Run with --fixed-fps 60 so every frame is one physics step.
## Holds whatever inputs the film sets (round 29: the Megafire is held, not fired).
class Hold:
	extends RefCounted
	func drive(_v: Vehicle, _d: float) -> void:
		pass


func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var car_id := args[0]
	var weapon := args[1]
	var out := args[2]
	var frames: Array = [2, 6, 12, 20, 30, 42]
	if args.size() > 3:
		frames = Array(args[3].split(",")).map(func(x: String) -> int: return int(x))
	var secondary := args.size() > 4 and args[4] == "secondary"
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
	me.controller = null
	me.global_transform = Transform3D(Basis.IDENTITY, LosAngelesArena.ground(20, 30, 0.1))
	var foe_at := OS.get_environment("FOE_AT")
	var fz := -8.0 if foe_at == "" else float(foe_at)
	var foe_x := OS.get_environment("FOE_X") # round 28: a foe beside the car (Drive-By)
	var fx := 21.0 if foe_x == "" else float(foe_x)
	foe.global_transform = Transform3D(Basis(Vector3.UP, PI), LosAngelesArena.ground(fx, fz, 0.1))
	for v: Vehicle in [me, foe]:
		v.velocity = Vector3.ZERO
		v.invulnerable_time = 0.0
		v.shield_time = 0.0
	me.target = foe
	for i in 90: # let the chase camera settle
		await physics_frame
	if secondary:
		me.ammo[me.special_id] = 5
		me.energy_move("secondary")
	elif weapon == "megafire":
		me.controller = Hold.new()
		me.selected = me.weapon_order.find("megafire")
		me.in_fire_weapon = true
	else:
		Specials.fire(me, weapon)
	if OS.get_environment("SIDE_CAM") != "": # round 29: a fixed camera off the car's side
		var cam := Camera3D.new()
		me.get_parent().add_child(cam)
		cam.global_position = me.global_position + Vector3(14, 6, -6)
		cam.look_at(me.global_position + Vector3(0, 0.5, -8))
		cam.make_current()
	var shots: Array[Image] = []
	var k := 0
	for f: int in frames:
		while k < f:
			await physics_frame
			k += 1
		await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_viewport().get_texture().get_image()
		img.resize(img.get_width() / 2, img.get_height() / 2)
		shots.append(img)
	var w := shots[0].get_width()
	var h := shots[0].get_height()
	var cols := 3
	var rows := int(ceil(shots.size() / float(cols)))
	var sheet := Image.create(w * cols, h * rows, false, shots[0].get_format())
	for i in shots.size():
		sheet.blit_rect(shots[i], Rect2i(0, 0, w, h), Vector2i((i % cols) * w, (i / cols) * h))
	sheet.save_png(out)
	quit()
