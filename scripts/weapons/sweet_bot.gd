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

const DROP_TIME := 0.6 # sliding down out of the back door
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
	# Round 19 (owner): it slides down out of the truck's back door: from the floor of the box at the
	# back, down and out onto the road behind.
	var back := car.global_position - car.flat_forward() * (size.z * 0.5 + 2.6) + Vector3.UP
	b._ground = Specials.ground_below(world, back)
	b._drop_from = car.global_position - car.flat_forward() * (size.z * 0.5 - 0.6) + Vector3.UP * 0.65
	b.global_position = b._drop_from
	b.rotation = Vector3(0.0, car.global_rotation.y + PI, 0.0)
	car.bot = b
	GameFeel.play("mine_drop", b._drop_from, world, -2.0, 0.8)
	GameFeel.play("metal_fall", b._drop_from, world, -6.0, 0.7)
	if car.is_player:
		car.notice.emit(car, "SWEET BOT OUT - R L U AGAIN TO LAUNCH")
	return b


func _ready() -> void:
	collision_layer = BurningDriver.LAYER # projectiles hit it; cars are checked by hand (_check_cars)
	collision_mask = 0
	add_to_group(&"bots")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 2.6, 1.2)
	shape.shape = box
	shape.position = Vector3(0, 1.3, 0)
	add_child(shape)
	_model = Node3D.new()
	add_child(_model)
	if ModelLib.has("sweet_bots") and POD.has(style):
		_build_candidate()
	else:
		_build_v1()
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


## Round 19: the four TMB-style candidates (tools/blender/build_sweet_bots.py), until the owner picks one.
## The whole robot turns to aim; the missiles leave its pods. POD = for each look, the centre of each pod
## (Godot space, robot facing -Z), columns x rows, the spacing, and which way the pod faces (y tilt).
static var style := "a"
const POD := {
	"a": [[Vector3(-0.98, 1.98, -0.42), Vector3(0.98, 1.98, -0.42)], 2, 5, 0.095],
	"b": [[Vector3(-0.82, 1.85, -0.53), Vector3(0.82, 1.85, -0.53)], 2, 5, 0.09],
	"c": [[Vector3(0.0, 2.27, -0.23)], 5, 4, 0.12],
	"d": [[Vector3(-0.72, 2.33, -0.1), Vector3(0.72, 2.33, -0.1)], 2, 5, 0.1],
}


func _build_candidate() -> void:
	_waist = Vector3.ZERO
	_upper = Node3D.new()
	_model.add_child(_upper)
	_upper.add_child(ModelLib.instance("sweet_bots", "bot_" + style))
	var pod: Array = POD[style]
	var cols := int(pod[1])
	var rows := int(pod[2])
	var pitch := float(pod[3])
	var per: Array = []
	for c: Vector3 in pod[0]:
		var mouths: Array = []
		for r in rows: # bottom row first
			for k in cols:
				mouths.append(c + Vector3((k - (cols - 1) * 0.5) * pitch, (r - (rows - 1) * 0.5) * pitch, 0.0))
		per.append(mouths)
	for i in rows * cols: # one pod and then the other in turn
		for mouths: Array in per:
			_tubes.append(mouths[i])


func _build_v1() -> void:
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
	_cone_fire.size = 0.5
	_cone_fire.rate = 26.0
	_cone_fire.life = 0.4
	_cone_fire.rise = 0.8
	_cone_fire.inherit = 0.0
	_cone_fire.glow = 0.95
	_cone_fire.box = Vector3(0.07, 0.02, 0.07)
	var cone: Variant = marks.get("m_cone")
	_cone_fire.position = (((cone as Transform3D).origin - waist) if cone != null else Vector3(0, 1.57, 0.02)) + Vector3.DOWN * 0.2
	_upper.add_child(_cone_fire)
	_cone_fire.on = true


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
		"drop": # slides down out of the back door onto the road, lands with a thump, stands up
			var k := clampf(_t / DROP_TIME, 0.0, 1.0)
			global_position = _drop_from.lerp(_ground, k) + Vector3.UP * 0.25 * sin(k * PI)
			if k >= 1.0:
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
