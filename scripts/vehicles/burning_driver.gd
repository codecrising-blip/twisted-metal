class_name BurningDriver
extends StaticBody3D
## The driver of a destroyed car (round 17, the owner's idea from Twisted Metal: Black, made our own).
##
## Died on the ground: once the wreck has landed the driver stumbles out of the driver's door, burnt
## beyond recognition and on fire, screaming, and runs away from whoever killed them for RUN_TIME
## seconds, stumbling and beating at the flames with no hope, then drops to the knees, crawls a few
## metres and crumples dead, curled up as burnt bodies do. Died in the air: the driver is blasted out
## of the car and lands dead and burning (DriverCorpse). The flames are the TMB kind (TmbFire): streaky
## sheets on every limb that trail behind as they run; no smoke. The body sinks away after BODY_STAYS.
## While alive they can be finished off: shot (any projectile, blasts too) or run down. Run down hard
## and head-on they go over the hood into the windshield and off (DriverCorpse); otherwise they are
## pressed under the car. Either way the fire goes out, the body is black, blood pools on the ground
## and a little stays on the car. The killer gets WeaponData.DRIVER_KILL_ENERGY.
## The camera never follows a driver (owner): it stays on the wreck.

const LAYER := 64 # physics layer 7: projectiles hit it, cars and the world ignore it
const EXIT_DELAY := 0.9 # the wreck hops on its death blast; the driver gets out once it is down
const WRECK_WAIT := 4.0 # ...or after this long whatever it is doing
const RUN_TIME := 5.0 # owner: they run for 5 seconds
const RUN_SPEED := 3.9 # a stumbling run, slowed further by stumbles
const KNEEL_TIME := 1.0
const CRAWL_TIME := 2.6
const CRAWL_SPEED := 0.7 # about two metres of crawling
const BODY_STAYS := 8.0 # the body lies this long, then sinks away (owner: not left lying for good)
const FIRE_DIES := 2.5 # seconds the flames take to die down on a dead body
const RAM_MIN_SPEED := 3.0 # slower than this a car only shoves them aside
const WINDSHIELD_SPEED := 9.0 # m/s (~32 km/h) and head-on: over the hood into the windshield
const WINDSHIELD_ANGLE := 40.0 # degrees off the car's line of travel
const MAX_BODIES := 8
const HEAD_ON_PART := 0.55 # the front this share of the half length counts as the car's front

enum { RUN, KNEEL, CRAWL, DEAD }

static var _bodies: Array = []

var female := false
var killer: Vehicle
var state := RUN
var _t := 0.0
var _heading := Vector3.FORWARD
var _wander := 0.0
var _fall := 0.0
var _model: Node3D
var _anim: AnimationPlayer
var _mat: ShaderMaterial
var _flames: Array = [] # TmbFire sheets on the limbs
var _burn := 1.0 # how strongly they burn (0 = out)
var _burn_rate := 0.0 # how fast the fire dies once they are dead
var _speed := 0.0
var _stumble := 0.0 # seconds left of a stumble (slowed right down)
var _next_stumble := 1.2
var _scream: AudioStreamPlayer3D
var _shape: CollisionShape3D
var _box: BoxShape3D
var _heat := 1.0
var _cool := 0.0 # embers fade at this rate (per second) once dead


## A car has just been destroyed. `airborne`: it was off the ground when it died.
static func spawn_for(car: Vehicle, airborne: bool) -> void:
	var world := car.get_parent()
	var female := bool(car.stats.get("female", false))
	if airborne:
		var out := car.linear_velocity * 0.6 + Vector3(randf_range(-4.0, 4.0), 8.5, randf_range(-4.0, 4.0))
		DriverCorpse.fling(world, car.global_position + Vector3.UP * 1.4, out, female, true, null)
		return
	_wait_for_wreck(world, car, female, car.last_attacker, 0.0)


## The wreck hops and tumbles on its death blast: the driver gets out once it has come down and
## nearly stopped (at least EXIT_DELAY after the blast, at most WRECK_WAIT).
static func _wait_for_wreck(world: Node, car: Vehicle, female: bool, killer: Vehicle, waited: float) -> void:
	if not is_instance_valid(world) or not is_instance_valid(car) or not world.is_inside_tree():
		return
	var settled := waited >= EXIT_DELAY and car.linear_velocity.length() < 2.5 \
		and car.global_position.y - Specials.ground_below(world, car.global_position + Vector3.UP).y < 1.6
	if settled or waited >= WRECK_WAIT:
		_climb_out(world, car, female, killer)
		return
	car.get_tree().create_timer(0.15, false).timeout.connect(func() -> void:
		BurningDriver._wait_for_wreck(world, car, female, killer, waited + 0.15))


static func _climb_out(world: Node, car: Vehicle, female: bool, killer: Vehicle) -> void:
	var size: Vector3 = car.stats.get("size", Vector3(2.2, 1.8, 5.0))
	var b := car.global_basis
	var right := Vector3(b.x.x, 0.0, b.x.z)
	right = right.normalized() if right.length() > 0.1 else Vector3.RIGHT
	var ahead := Vector3(-b.z.x, 0.0, -b.z.z)
	ahead = ahead.normalized() if ahead.length() > 0.1 else Vector3.FORWARD
	var base := car.global_position
	var at := Vector3.ZERO
	var found := false
	for side: float in [-1.0, 1.0]: # the driver's door (left), else the other side
		var door := base + right * side * (size.x * 0.5 + 0.5) + ahead * size.z * 0.1
		var g := Specials.ground_below(world, door + Vector3.UP * 2.0)
		if absf(g.y - base.y) < 2.5:
			at = g
			found = true
			break
	if not found:
		return
	var d := BurningDriver.new()
	d.female = female
	d.killer = killer
	var away := at - base
	away.y = 0.0
	d._heading = away.normalized() if away.length() > 0.1 else -right
	d.position = at # the world node sits at the origin
	world.add_child(d)
	_keep(d)


static func _keep(node: Node3D) -> void:
	_bodies.assign(_bodies.filter(func(n: Variant) -> bool: return is_instance_valid(n)))
	_bodies.append(node)
	while _bodies.size() > MAX_BODIES:
		(_bodies.pop_front() as Node).queue_free()


## A burnt body (the Blender dummy, driver_m / driver_f) with its clips set to loop. Returns the model;
## its AnimationPlayer and ShaderMaterial are in the metas "anim" and "mat".
static func make_body(female: bool) -> Node3D:
	var scene: PackedScene = load("res://assets/models/driver_%s.glb" % ("f" if female else "m"))
	var model := scene.instantiate() as Node3D
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://scripts/fx/burnt_body.gdshader")
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = mat
	var anim: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false)[0]
	for a in anim.get_animation_list():
		anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	model.set_meta("anim", anim)
	model.set_meta("mat", mat)
	return model


func _ready() -> void:
	collision_layer = LAYER
	collision_mask = 0
	add_to_group(&"drivers")
	_box = BoxShape3D.new()
	_box.size = Vector3(0.9, 1.9, 0.9)
	_shape = CollisionShape3D.new()
	_shape.shape = _box
	_shape.position = Vector3(0, 0.95, 0)
	add_child(_shape)
	_model = make_body(female)
	add_child(_model)
	_anim = _model.get_meta("anim")
	_mat = _model.get_meta("mat")
	_anim.play("run_burn")
	_anim.seek(randf() * 1.3)
	_anim.speed_scale = randf_range(0.92, 1.08)
	_flames = TmbFire.on_body(_model)
	_next_stumble = randf_range(0.8, 1.6)
	_scream = GameFeel.play("death_female" if female else "death_male", global_position + Vector3.UP * 1.5, self, -1.0, randf_range(0.95, 1.05))
	_wander = randf() * TAU
	look_at(global_position + _heading, Vector3.UP)


func _physics_process(delta: float) -> void:
	_t += delta
	match state:
		RUN:
			_steer(delta)
			_speed = RUN_SPEED * (0.8 + 0.2 * sin(_t * 7.3))
			# Stumbles now and then: nearly stopped for a moment, the run breaking up, slower each time.
			_next_stumble -= delta
			if _next_stumble <= 0.0:
				_stumble = randf_range(0.3, 0.5)
				_next_stumble = randf_range(0.9, 1.7)
			if _stumble > 0.0:
				_stumble -= delta
				_speed *= 0.35
			_speed *= lerpf(1.0, 0.75, _t / RUN_TIME)
			_anim.speed_scale = lerpf(1.05, 0.85, _t / RUN_TIME) * (0.6 if _stumble > 0.0 else 1.0)
			_move(_speed, delta)
			if _t >= RUN_TIME:
				_enter(KNEEL)
		KNEEL:
			_speed = 0.0
			_move(0.0, delta)
			if _t >= KNEEL_TIME:
				_enter(CRAWL)
		CRAWL:
			_speed = CRAWL_SPEED
			_move(CRAWL_SPEED, delta)
			if _t >= CRAWL_TIME:
				_die(null, "burns")
		DEAD:
			_move(0.0, delta)
			_heat = maxf(0.0, _heat - _cool * delta)
			_mat.set_shader_parameter("heat", _heat)
			_burn = maxf(0.0, _burn - _burn_rate * delta)
			TmbFire.set_all(_flames, _burn)
			if _t > BODY_STAYS:
				position.y -= delta * 0.4 # sinks away
				if _t > BODY_STAYS + 1.5:
					queue_free()
			return
	# Running, the tips of the flames stream back against the way they go.
	TmbFire.set_all(_flames, _burn, -_heading * minf(_speed, 5.0) * 0.12)
	_check_cars()


## Panicked running: away from the killer, weaving, turning off walls.
func _steer(delta: float) -> void:
	var want := _heading
	if is_instance_valid(killer) and not killer.is_dead:
		var away := global_position - killer.global_position
		away.y = 0.0
		if away.length() > 0.5:
			want = want.lerp(away.normalized(), 0.6 * delta * 3.0).normalized()
	want = want.rotated(Vector3.UP, sin(_t * 1.7 + _wander) * 1.2 * delta)
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * 1.0
	var q := PhysicsRayQueryParameters3D.create(from, from + want * 1.8, 1)
	if not space.intersect_ray(q).is_empty():
		want = want.rotated(Vector3.UP, randf_range(1.8, 2.8) * (1.0 if randf() < 0.5 else -1.0))
	_heading = Vector3(want.x, 0.0, want.z).normalized()
	var face := global_position + _heading
	look_at(Vector3(face.x, global_position.y, face.z), Vector3.UP)


## Moves along the heading and keeps the feet on the ground (they fall off ledges like anyone).
func _move(speed: float, delta: float) -> void:
	var next := global_position + _heading * speed * delta
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(next + Vector3.UP * 1.2, next + Vector3.DOWN * 4.0, 1)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	var gy := (hit.position as Vector3).y
	if next.y - gy > 0.35: # off an edge: falls
		_fall += 30.0 * delta
		next.y = maxf(gy, next.y - _fall * delta)
	elif gy - next.y > 0.6 and state != DEAD: # a step too high: turn away
		_heading = _heading.rotated(Vector3.UP, PI * 0.7)
		return
	else:
		_fall = 0.0
		next.y = gy
	global_position = next


func _enter(s: int) -> void:
	state = s
	_t = 0.0
	match s:
		KNEEL:
			_anim.play("kneel", 0.35)
			_box.size = Vector3(0.9, 1.3, 0.9)
			_shape.position = Vector3(0, 0.65, 0)
		CRAWL:
			_anim.play("crawl", 0.45)
			_box.size = Vector3(0.9, 0.8, 1.6)
			_shape.position = Vector3(0, 0.4, 0)


## Dead: by the burns (`how` "burns"), a shot ("shot") or a car ("under" / "thrown"). Shots and cars
## pay the killer in energy.
func _die(by: Vehicle, how: String) -> void:
	if state == DEAD:
		return
	state = DEAD
	_t = 0.0
	collision_layer = 0
	_shape.disabled = true
	remove_from_group(&"drivers")
	if is_instance_valid(by) and not by.is_dead: # paid quietly (owner: no text)
		by.energy = minf(100.0, by.energy + WeaponData.DRIVER_KILL_ENERGY)
	if how != "burns" and is_instance_valid(_scream):
		var tw := _scream.create_tween()
		tw.tween_property(_scream, "volume_db", -40.0, 0.12)
		tw.tween_callback(_scream.stop)
	match how:
		"burns": # crumples where they are; the fire burns down on the body
			_anim.play("prone", 0.8)
			_burn_rate = 1.0 / FIRE_DIES
			_cool = 0.22
		"shot": # drops and curls up
			_anim.play("prone", 0.35)
			BloodFx.pool(get_parent(), global_position + _heading * 0.3, 0.55)
			_burn_rate = 1.0 / (FIRE_DIES * 0.6)
			_cool = 0.3
		"under": # the fire is crushed out; a black body
			_anim.play("prone", 0.1)
			_put_out()
		"thrown":
			queue_free()


## Run down: the fire is crushed out at once, a black body (a puff of dust where it went down).
func _put_out() -> void:
	_burn = 0.0
	_burn_rate = 0.0
	TmbFire.set_all(_flames, 0.0)
	_heat = 0.0
	_cool = 0.0
	_mat.set_shader_parameter("heat", 0.0)
	FxKit.puff(get_parent(), global_position + Vector3.UP * 0.4, 0.6)


## Anything that hurts them kills them (they have no fight left): projectiles and blasts.
func projectile_hit(_damage: float, shooter: Vehicle) -> void:
	_die(shooter, "shot")


## A blast near them throws the body away from it, still burning.
func blast(pos: Vector3, owner_car: Vehicle) -> void:
	if state == DEAD:
		return
	var away := global_position - pos
	away.y = 0.0
	var out := (away.normalized() if away.length() > 0.1 else _heading) * 7.0 + Vector3.UP * 7.5
	DriverCorpse.fling(get_parent(), global_position + Vector3.UP * 0.9, out, female, true, null)
	_die(owner_car, "thrown")


## Cars: a car moving into them runs them down; one barely moving just shoves them aside.
func _check_cars() -> void:
	for n in get_tree().get_nodes_in_group(&"vehicles"):
		var v := n as Vehicle
		if v == null or v.is_dead or v.global_position.distance_squared_to(global_position) > 64.0:
			continue
		var size: Vector3 = v.stats.get("size", Vector3(2.2, 1.8, 5.0))
		var local := v.global_transform.affine_inverse() * (global_position + Vector3.UP * 0.6)
		var reach := 0.35 if state == RUN else 0.2
		if absf(local.x) > size.x * 0.5 + reach or absf(local.z) > size.z * 0.5 + reach or local.y < -0.6 or local.y > size.y + 0.6:
			continue
		var vel := v.linear_velocity
		vel.y = 0.0
		if vel.length() < RAM_MIN_SPEED:
			var out := Vector3(local.x, 0.0, 0.0).normalized() if absf(local.x) > 0.05 else Vector3.RIGHT
			global_position += v.global_basis * out * 0.08
			continue
		_run_down(v, local, size)
		return


## Run down (owner): head-on and fast enough they go over the hood into the windshield; otherwise
## they are pressed under the car. Dead at once, the fire out, a black body, blood on the ground and
## a little on the car.
func _run_down(car: Vehicle, local: Vector3, size: Vector3) -> void:
	var vel := car.linear_velocity
	vel.y = 0.0
	var speed := vel.length()
	var to_me := global_position - car.global_position
	to_me.y = 0.0
	var angle := rad_to_deg(vel.angle_to(to_me)) if to_me.length() > 0.1 else 0.0
	var front := local.z < -size.z * 0.5 * HEAD_ON_PART and car.speed > 0.0
	var world := get_parent()
	GameFeel.play("land_thud", global_position + Vector3.UP, world, 2.0, 0.8)
	GameFeel.play("crash_1", global_position + Vector3.UP, world, -8.0, 1.3)
	if car.is_player:
		GameFeel.shake(global_position, 0.25)
		GameFeel.hitstop(get_tree(), 0.04)
	if front and speed >= WINDSHIELD_SPEED and angle <= WINDSHIELD_ANGLE:
		DriverCorpse.windshield(world, car, female, local.x, size)
		_die(car, "thrown")
		return
	# Pressed under: knocked flat where they stood, pushed a little along the car's way.
	var along := vel.normalized()
	global_position += along * minf(0.6, speed * 0.04)
	look_at(global_position + along, Vector3.UP)
	_die(car, "under")
	BloodFx.pool(world, global_position, 1.1)
	BloodFx.on_car(car, Vector3(clampf(local.x, -size.x * 0.4, size.x * 0.4), 0.4, -size.z * 0.5 if local.z < 0.0 else size.z * 0.5), Vector3(0, 0.1, -1.0 if local.z < 0.0 else 1.0), 0.6)
	car.push(Vector3.UP * 1.2) # a bump as it goes over
