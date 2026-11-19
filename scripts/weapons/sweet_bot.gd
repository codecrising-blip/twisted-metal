class_name SweetBot
extends StaticBody3D
## Sweet Tooth's secondary weapon (round 18; the owner's design from rounds 16 and 19): a robot that slides
## down out of the truck's back door and stays planted. R L U again orders the barrage (round 19: so the
## Napalm Cone still fires while it stands): WeaponData.BOT_MISSILES Zoomy-like missiles from the two
## shoulder pods, 4 each, homing on Sweet Tooth's target (or the nearest car it can see). They can hit
## Sweet Tooth too if he is in the line of fire. The idea: traps and nerves; Sweet Tooth rams you while
## the robot waits behind you.
## It takes hits (projectiles, blasts): BOT_HEALTH 59, a power missile and a fire missile, and a car
## that runs into it crushes it. Destroyed, it goes up like a Remote (it hurts whoever is near, Sweet
## Tooth included). Round 19 (owner): it never goes on its own: after a barrage it reloads COOLDOWN 5 s and
## can fire again, until an opponent destroys it; if its truck is destroyed the next one takes it over.
## Costs two special charges to drop (design 1.6). Model: tools/blender/build_sweet_bot.py.

const DROP_TIME := 0.75 # sliding out of the box and down the tailgate
const DOOR_OPEN := 0.3 # the tailgate folding down
const DOOR_ANGLE := 1.955 # 112 degrees: folded down to the road, a ramp
const CROUCH := 0.88 # its height in the box (it rises on the road: _stand)
const SQUEEZE := 0.84 # and its width: arms in, wings folded, it fits the 1.78 m door
const RAMP := 1.75 # m from the hinge to where the tailgate's end touches the road
const COOLDOWN := 5.0 # owner, round 19: after a barrage it reloads this long, then fires again
const STAND_TIME := 0.4
const TURN_RATE := 3.2 # rad/s the upper body turns toward its target

var owner_car: Vehicle
var health := WeaponData.BOT_HEALTH
var state := "drop" # drop -> wait -> fire -> reload -> wait ... until an opponent destroys it
var _t := 0.0
var _model: Node3D
var _upper: Node3D
var _tubes: Array = [] # tube mouths in the upper body's space, in firing order (left, right, left ...)
var _lock: Vehicle
var _shots := 0
var _gap := 0.0
var _queued := false # ordered to fire while still landing
var _dead := false
var _drop_from := Vector3.ZERO
var _ground := Vector3.ZERO
var _recoil := 0.0
var _scan := 0.0
var _hit_flash := 0.0
var _waist := Vector3(0, 1.12, 0)
var _car_model: Node3D
var _hinge := Vector3.ZERO # the tailgate's hinge in the truck model's space
var _ramp_top := Vector3.ZERO # in the world, fixed once the robot is out of the box


## Out of the back of `car`, facing back the way the truck came (at whoever chases it).
static func deploy(car: Vehicle) -> SweetBot:
	var world := car.get_parent()
	var b := SweetBot.new()
	b.owner_car = car
	world.add_child(b)
	# Round 19 (owner): the truck's tailgate folds down into a ramp and the robot, crouched in the box, slides
	# out and down it onto the road behind; it stands up there. The path follows the truck while the robot is
	# still inside (the truck may be driving), then runs down the ramp from where the hinge was.
	b._car_model = car.model
	b._hinge = b._local_hinge(car)
	b._drop_from = car.model.to_global(b._hinge + Vector3(0, 0.02, -1.0))
	b.global_position = b._drop_from
	b.rotation = Vector3(0.0, car.global_rotation.y + PI, 0.0)
	b._model.scale = Vector3(SQUEEZE, CROUCH, 1.0)
	b._ramp_top = car.model.to_global(b._hinge)
	var back := car.model.global_basis.z
	back.y = 0.0
	b._ground = Specials.ground_below(world, b._ramp_top + back.normalized() * (RAMP + 0.7) + Vector3.UP)
	b._t = -DOOR_OPEN # waits in the box while the door comes down
	var door := car.model.get_meta("door") as Node3D if car.model.has_meta("door") else null
	if door:
		var tw := door.create_tween()
		tw.tween_property(door, "rotation:x", DOOR_ANGLE, DOOR_OPEN).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(func() -> void: GameFeel.play("land_thud", door.global_position, world, -6.0, 1.3))
		tw.tween_interval(DROP_TIME + 0.5)
		tw.tween_property(door, "rotation:x", 0.0, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_callback(func() -> void: GameFeel.play("metal_fall", door.global_position, world, -8.0, 1.2))
	car.bot = b
	GameFeel.play("mine_drop", b._drop_from, world, -2.0, 0.8)
	if car.is_player:
		car.notice.emit(car, "SWEET BOT OUT - R L U AGAIN TO LAUNCH")
	return b


func _ready() -> void:
	collision_layer = BurningDriver.LAYER # projectiles hit it; cars are checked by hand (_check_cars)
	collision_mask = 0
	add_to_group(&"bots")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.5, 1.75, 1.2) # mini TMB Sweet Bot (owner, after round 19): ~1.75 m tall, 1.5 m wide
	shape.shape = box
	shape.position = Vector3(0, 0.875, 0)
	add_child(shape)
	_model = Node3D.new()
	add_child(_model)
	_build_model()
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


## The tailgate's hinge in the truck model's space (m_door_hinge), or the back of the box.
func _local_hinge(car: Vehicle) -> Vector3:
	if car.model.has_meta("door"):
		return (car.model.get_meta("door") as Node3D).position
	var size: Vector3 = car.stats.get("size", Vector3(2.5, 2.8, 6.6))
	return Vector3(0, 0.74, size.z * 0.45)


## The owner's pick (round 19, look A of four, from the TMB clip; tools/blender/build_sweet_bot.py): legs
## (chassis, wheels, the truck's box) stand still, the upper body turns at m_waist; the missiles leave
## the tube mouths m_tube_l/r0..9, one pod and then the other.
func _build_model() -> void:
	var marks := ModelLib.marks("sweet_bot")
	var waist: Vector3 = (marks.get("m_waist", Transform3D(Basis.IDENTITY, Vector3(0, 1.2, 0))) as Transform3D).origin
	_model.add_child(ModelLib.instance("sweet_bot", "legs"))
	_waist = waist
	_upper = Node3D.new()
	_upper.position = waist
	_model.add_child(_upper)
	_upper.add_child(ModelLib.instance("sweet_bot", "upper"))
	for k in 10: # left and right in turn, bottom row first
		for side: String in ["l", "r"]:
			var m: Variant = marks.get("m_tube_%s%d" % [side, k])
			if m != null:
				_tubes.append((m as Transform3D).origin - waist)
	if _tubes.is_empty():
		_tubes = [Vector3(-0.8, 0.45, -0.4), Vector3(0.8, 0.45, -0.4)]


## Ordered to fire (its owner's R L U while it stands): only when it is ready (not mid-barrage, not reloading).
func fire_again() -> bool:
	if _dead:
		return false
	match state:
		"drop":
			_queued = true
			return true
		"wait":
			_start_barrage()
			return true
	return false


## Seconds until it can fire again (0 = ready).
func reload_left() -> float:
	match state:
		"reload":
			return maxf(0.0, COOLDOWN - _t)
		"fire":
			return COOLDOWN
	return 0.0


## Its truck was destroyed: the same driver's next truck takes it over.
func _adopt() -> void:
	var was := owner_car if is_instance_valid(owner_car) else null
	for node in get_tree().get_nodes_in_group("vehicles"):
		var o := node as Vehicle
		if o.is_dead or o == was:
			continue
		if (was == null or (o.car_id == was.car_id and o.is_player == was.is_player)) and not is_instance_valid(o.bot):
			owner_car = o
			o.bot = self
			return


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_t += delta
	if not is_instance_valid(owner_car) or owner_car.is_dead:
		_adopt() # its truck was destroyed: it waits for the next one (owner: only an opponent ends it)
	_hit_flash = maxf(0.0, _hit_flash - delta)
	match state:
		"drop": # slides out of the box and down the tailgate onto the road, lands with a thump, stands up
			_model.scale = Vector3(SQUEEZE, CROUCH, 1.0) # folded up to fit the box
			var k := clampf(_t / DROP_TIME, 0.0, 1.0)
			const OUT := 0.35 # share of the time it takes to reach the hinge
			if k < OUT and is_instance_valid(_car_model):
				var from := _car_model.to_global(_hinge + Vector3(0, 0.02, -1.0))
				_ramp_top = _car_model.to_global(_hinge)
				var back := _car_model.global_basis.z
				back.y = 0.0
				_ground = Specials.ground_below(get_parent(), _ramp_top + back.normalized() * (RAMP + 0.7) + Vector3.UP)
				global_position = from.lerp(_ramp_top, k / OUT)
				rotation.y = _car_model.global_rotation.y + PI
			elif k < 1.0:
				var d := (k - OUT) / (1.0 - OUT)
				global_position = _ramp_top.lerp(_ground, d * d) # gathering speed down the ramp
			else:
				_land()
		"wait":
			_stand(delta)
			_scan += delta
			var want := _pick_target()
			_turn_to(want, delta)
			var ai_owner := is_instance_valid(owner_car) and not owner_car.is_dead and not owner_car.is_player
			if ai_owner and _t > 1.0: # an AI owner: it fires on its own once someone is in reach
				if want and _sees(want) and global_position.distance_to(want.global_position) < 50.0:
					_start_barrage()
		"fire":
			_stand(delta)
			if not is_instance_valid(_lock) or _lock.is_dead:
				_lock = _pick_target()
			_turn_to(_lock, delta)
			_gap -= delta
			if _gap <= 0.0:
				_gap = WeaponData.BOT_GAP
				_launch_one()
		"reload":
			_stand(delta)
			_scan += delta
			_turn_to(_pick_target(), delta)
			if _t >= COOLDOWN:
				state = "wait"
				_t = STAND_TIME # already standing
				if is_instance_valid(owner_car) and owner_car.is_player:
					owner_car.notice.emit(owner_car, "SWEET BOT READY")
	_recoil = move_toward(_recoil, 0.0, delta * 0.6)
	_upper.position = _waist + _upper.basis.z * _recoil # kicked back a little per shot
	_check_cars()


func _land() -> void:
	state = "wait"
	_t = 0.0
	global_position = _ground
	var world := get_parent()
	GameFeel.play("land_thud", _ground, world, -2.0, 0.9, true)
	GameFeel.play("metal_fall", _ground, world, -8.0, 0.8)
	FxKit.dust_ring(world, _ground, 1.0)
	if _queued:
		_start_barrage()


## Stands up from the landing crouch with a little overshoot, then breathes on its hydraulics.
func _stand(_delta: float) -> void:
	var k := clampf((_t if state == "wait" else STAND_TIME) / STAND_TIME, 0.0, 1.0)
	var y := CROUCH + (1.0 - CROUCH) * (1.0 - pow(1.0 - k, 3.0)) + 0.04 * sin(k * PI) # rises, overshoots a hair
	if k >= 1.0:
		y = 1.0 + 0.008 * sin(Time.get_ticks_msec() * 0.004)
	_model.scale = Vector3(1.0, y, 1.0)


## Sweet Tooth's own target if it is in reach, else the nearest car it can see, else the nearest car.
func _pick_target() -> Vehicle:
	var mine := owner_car.target
	if is_instance_valid(mine) and not mine.is_dead and not mine.is_hidden() \
			and global_position.distance_to(mine.global_position) < WeaponData.BOT_RANGE:
		return mine
	var best: Vehicle = null
	var best_d := INF
	var seen := false
	for node in get_tree().get_nodes_in_group("vehicles"):
		var o := node as Vehicle
		if o == owner_car or o.is_dead or o.is_hidden():
			continue
		var d := global_position.distance_to(o.global_position)
		if d > WeaponData.BOT_RANGE:
			continue
		var s := _sees(o)
		if (s and not seen) or ((s == seen) and d < best_d):
			best = o
			best_d = d
			seen = s
	return best


func _sees(o: Vehicle) -> bool:
	var from := global_position + Vector3.UP * 1.8
	var q := PhysicsRayQueryParameters3D.create(from, o.aim_point(), 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Turns the upper body toward `o` (or scans slowly when there is nobody).
func _turn_to(o: Vehicle, delta: float) -> void:
	var want := sin(_scan * 0.7) * 0.4
	if is_instance_valid(o):
		var d := to_local(o.global_position)
		want = atan2(-d.x, -d.z)
	_upper.rotation.y = rotate_toward(_upper.rotation.y, want, TURN_RATE * delta)


func _start_barrage() -> void:
	state = "fire"
	_t = 0.0
	_shots = 0
	_gap = 0.15 # a breath to turn first
	_lock = _pick_target()
	GameFeel.play("sat_lock", global_position + Vector3.UP * 2.0, get_parent(), -6.0, 1.3)


func _launch_one() -> void:
	if _shots >= WeaponData.BOT_MISSILES:
		state = "reload"
		_t = 0.0
		return
	var tube: Vector3 = _tubes[_shots % _tubes.size()]
	var from := _upper.to_global(tube)
	var fwd := -_upper.global_basis.z
	fwd.y = 0.0
	fwd = (fwd.normalized() + Vector3.UP * 0.12 + Vector3(randf_range(-0.08, 0.08), randf_range(0.0, 0.06), randf_range(-0.08, 0.08))).normalized()
	if is_instance_valid(_lock) and not _lock.is_dead:
		var to := (_lock.aim_point() - from).normalized()
		if fwd.angle_to(to) < deg_to_rad(70.0):
			fwd = fwd.lerp(to, 0.5).normalized()
	var p := Projectile.spawn(get_parent(), "bot_missile", from, fwd, owner_car, _lock)
	if p:
		p.ignore.append(get_rid()) # never its own body
	_recoil = 0.05
	_shots += 1


## Hit by a projectile (Projectile calls this on anything with it).
func projectile_hit(damage: float, shooter: Vehicle) -> void:
	_take(damage, shooter)


## Caught in a blast (Specials.blast_props).
func blast_hit(damage: float, shooter: Vehicle) -> void:
	_take(damage, shooter)


func _take(damage: float, by: Vehicle) -> void:
	if _dead:
		return
	health -= damage
	_hit_flash = 0.12
	FxKit.spark(get_parent(), global_position + Vector3.UP * 1.5, Vector3.UP)
	if health <= 0.0:
		_destroyed(by)


## A car that runs into it crushes it (and gets the blast in its face); its own truck pushes past.
func _check_cars() -> void:
	for node in get_tree().get_nodes_in_group("vehicles"):
		var o := node as Vehicle
		if o == owner_car or o.is_dead:
			continue
		var rel := o.global_position - global_position
		if Vector2(rel.x, rel.z).length() < 1.6 and absf(rel.y) < 2.5 and o.linear_velocity.length() > 3.0:
			_destroyed(o)
			return


## Destroyed: it goes up like a Remote (owner, round 16), hurting whoever is near, Sweet Tooth too.
func _destroyed(by: Vehicle) -> void:
	if _dead:
		return
	_dead = true
	var world := get_parent()
	var m := Mine.new()
	m.def = WeaponData.get_def("remote")
	m.owner_car = by
	m._t = 99.0 # not its owner's fresh mine: no "own blast" kick
	world.add_child(m)
	m.global_position = global_position + Vector3.UP * 0.3
	m.detonate()
	FxKit.explosion(world, global_position + Vector3.UP * 1.4, 1.6, Color(1.0, 0.5, 0.15), false)
	_gone()


func _gone() -> void:
	if is_instance_valid(owner_car) and owner_car.bot == self:
		owner_car.bot = null
	queue_free()
