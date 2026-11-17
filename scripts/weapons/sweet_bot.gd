class_name SweetBot
extends StaticBody3D
## Sweet Tooth's secondary weapon (round 18; the owner's design from round 16): a small walker robot
## the truck drops behind it, planted and waiting. The next press of the special's fire button (like a
## Remote's detonation) orders the barrage: WeaponData.BOT_MISSILES Zoomy-like missiles from the two
## shoulder pods, 4 each, homing on Sweet Tooth's target (or the nearest car it can see). They can hit
## Sweet Tooth too if he is in the line of fire. The idea: traps and nerves; Sweet Tooth rams you while
## the robot waits behind you.
## It takes hits (projectiles, blasts): BOT_HEALTH 59, a power missile and a fire missile, and a car
## that runs into it crushes it. Destroyed, it goes up like a Remote (it hurts whoever is near, Sweet
## Tooth included). Spent, left waiting BOT_WAIT seconds, or its owner dead: it blows itself apart,
## harmlessly. Costs two special charges (design 1.6). Model: tools/blender/build_sweet_bot.py.

const DROP_TIME := 0.35
const STAND_TIME := 0.4
const TURN_RATE := 3.2 # rad/s the upper body turns toward its target
const SPENT_DELAY := 1.4

var owner_car: Vehicle
var health := WeaponData.BOT_HEALTH
var state := "drop" # drop -> wait -> fire -> spent
var _t := 0.0
var _model: Node3D
var _upper: Node3D
var _tubes: Array = [] # tube mouths in the upper body's space, in firing order (left, right, left ...)
var _cone_fire: FoamFire
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


## Dropped out of the back of `car`, facing back the way the truck came (at whoever chases it).
static func deploy(car: Vehicle) -> SweetBot:
	var world := car.get_parent()
	var b := SweetBot.new()
	b.owner_car = car
	world.add_child(b)
	var size: Vector3 = car.stats.get("size", Vector3(2.5, 2.8, 6.6))
	var back := car.global_position - car.flat_forward() * (size.z * 0.5 + 2.2) + Vector3.UP
	b._ground = Specials.ground_below(world, back)
	b._drop_from = b._ground + Vector3.UP * 1.4
	b.global_position = b._drop_from
	b.rotation = Vector3(0.0, car.global_rotation.y + PI, 0.0)
	car.set_live_special(b, car.special_id)
	GameFeel.play("mine_drop", b._drop_from, world, -2.0, 0.8)
	if car.is_player:
		car.notice.emit(car, "SWEET BOT OUT - FIRE SPECIAL TO LAUNCH")
	return b


func _ready() -> void:
	collision_layer = BurningDriver.LAYER # projectiles hit it; cars are checked by hand (_check_cars)
	collision_mask = 0
	add_to_group(&"bots")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.9, 2.2, 1.0)
	shape.shape = box
	shape.position = Vector3(0, 1.1, 0)
	add_child(shape)
	_model = Node3D.new()
	add_child(_model)
	var marks := ModelLib.marks("sweet_bot")
	var waist: Vector3 = (marks.get("m_waist", Transform3D(Basis.IDENTITY, Vector3(0, 1.12, 0))) as Transform3D).origin
	var legs := ModelLib.instance("sweet_bot", "legs")
	_model.add_child(legs)
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
		_tubes = [Vector3(-0.86, 0.66, -0.42), Vector3(0.86, 0.66, -0.42)]
	_cone_fire = FoamFire.new() # the little burnt cone on top still burns, like the truck's
	_cone_fire.size = 0.32
	_cone_fire.rate = 16.0
	_cone_fire.life = 0.5
	_cone_fire.rise = 1.6
	_cone_fire.box = Vector3(0.05, 0.02, 0.05)
	var cone: Variant = marks.get("m_cone")
	_cone_fire.position = ((cone as Transform3D).origin - waist) if cone != null else Vector3(0, 1.35, 0.02)
	_upper.add_child(_cone_fire)
	_cone_fire.on = true
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func fire_again() -> void:
	if _dead:
		return
	match state:
		"drop":
			_queued = true
		"wait":
			_start_barrage()


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_t += delta
	if not is_instance_valid(owner_car) or owner_car.is_dead:
		_fold_up() # its owner is gone: it blows itself apart (harmless)
		return
	_hit_flash = maxf(0.0, _hit_flash - delta)
	match state:
		"drop": # falls out of the back, lands with a thump, stands up
			var k := clampf(_t / DROP_TIME, 0.0, 1.0)
			global_position = _drop_from.lerp(_ground, k * k)
			if k >= 1.0:
				_land()
		"wait":
			_stand(delta)
			_scan += delta
			var want := _pick_target()
			_turn_to(want, delta)
			if not owner_car.is_player and _t > 1.0: # an AI owner: it fires on its own once someone is in reach
				if (want and _sees(want) and global_position.distance_to(want.global_position) < 50.0) or _t > 8.0:
					_start_barrage()
			if _t > WeaponData.BOT_WAIT:
				_fold_up()
				return
		"fire":
			_stand(delta)
			if not is_instance_valid(_lock) or _lock.is_dead:
				_lock = _pick_target()
			_turn_to(_lock, delta)
			_gap -= delta
			if _gap <= 0.0:
				_gap = WeaponData.BOT_GAP
				_launch_one()
		"spent":
			_stand(delta)
			if _t > SPENT_DELAY:
				_fold_up()
				return
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
	var y := 0.72 + 0.28 * (1.0 - pow(1.0 - k, 3.0)) + 0.05 * sin(k * PI) # rises, overshoots a hair
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
		state = "spent"
		_t = 0.0
		if is_instance_valid(owner_car) and owner_car.live_special() == self:
			owner_car.set_live_special(null) # the special fires as normal again
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


## Spent, timed out or its owner gone: it blows itself apart in a small harmless pop.
func _fold_up() -> void:
	if _dead:
		return
	_dead = true
	var world := get_parent()
	FxKit.explosion(world, global_position + Vector3.UP * 1.3, 1.1, Color(1.0, 0.5, 0.15))
	for k in 3:
		FxKit.spark(world, global_position + Vector3.UP * 1.5, Vector3(randf_range(-1, 1), 1.0, randf_range(-1, 1)).normalized())
	_gone()


func _gone() -> void:
	if is_instance_valid(owner_car) and owner_car.live_special() == self:
		owner_car.set_live_special(null)
	queue_free()
