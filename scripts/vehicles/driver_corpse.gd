class_name DriverCorpse
extends RigidBody3D
## A driver's body that physics throws (round 17): blasted out of a car destroyed in the air or by a
## blast, or run down head-on and fast (over the hood, into the windshield, then off). It tumbles
## limp, lands and lies; a burning one burns down on the ground. It only touches the world, never the
## cars (they would brake on it and read it as a wall).

const SETTLE_SPEED := 0.4
const ON_GLASS := 0.32 # seconds on the hood and windshield before it is thrown off

var female := false
var burning := true
var bloody := false
var _model: Node3D
var _mat: ShaderMaterial
var _fx: Array = []
var _t := 0.0
var _settled := false
var _heat := 1.0
# windshield ride: the car carries the body for a moment
var _car: Vehicle
var _ride: Array = [] # [Transform3D local start, Transform3D local end]
var _ride_t := 0.0


static func _make(world: Node, female_body: bool, is_burning: bool) -> DriverCorpse:
	var c := DriverCorpse.new()
	c.female = female_body
	c.burning = is_burning
	world.add_child(c)
	BurningDriver._keep(c)
	return c


## Thrown from `pos` with velocity `v`, tumbling.
static func fling(world: Node, pos: Vector3, v: Vector3, female_body: bool, is_burning: bool, _by: Vehicle) -> DriverCorpse:
	if world == null or not world.is_inside_tree():
		return null
	var c := _make(world, female_body, is_burning)
	c.global_position = pos
	c.global_basis = Basis.from_euler(Vector3(randf() * TAU, randf() * TAU, randf() * TAU))
	c.linear_velocity = v
	c.angular_velocity = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * randf_range(4.0, 8.0)
	return c


## Run down head-on and fast (owner): legs swept, the body folds back onto the hood, the head hits
## the windshield (blood on the glass), then it is thrown up and off as the car drives on. `x` = where
## across the car's front it was hit (car space).
static func windshield(world: Node, car: Vehicle, female_body: bool, x: float, size: Vector3) -> void:
	var c := _make(world, female_body, false)
	c.bloody = true
	c._car = car
	c.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	c.freeze = true
	var half := size * 0.5
	var lx := clampf(x, -half.x * 0.6, half.x * 0.6)
	# Car space (the car faces -Z): the hood and windshield as measured per car in Roster, else a
	# guess from its size. The body ends lying back on the hood, its head against the glass.
	var hood: Vector2 = car.stats.get("hood", Vector2(size.y * 0.5, -half.z * 0.55))
	var glass: Vector2 = car.stats.get("glass", Vector2(size.y * 0.75, -half.z * 0.2))
	var gn: Vector3 = (car.stats.get("glass_n", Vector3(0, 0.6, -0.8)) as Vector3).normalized()
	var head_at := Vector3(lx * 0.8, glass.x, glass.y) + gn * 0.16
	var hip_at := Vector3(lx, hood.x + 0.17, hood.y)
	var head_dir := (head_at - hip_at).normalized()
	var face := (Vector3.UP - head_dir * head_dir.dot(Vector3.UP)).normalized() # the front looks up
	var lying := Basis(head_dir.cross(-face), head_dir, -face)
	var start := Transform3D(Basis.IDENTITY, Vector3(lx, 0.9, -half.z - 0.2)) # standing in front of it
	var end := Transform3D(lying.rotated(head_dir, randf_range(-0.25, 0.25)), head_at - head_dir * 0.85)
	c._ride = [start, end]
	c.global_transform = car.global_transform * start
	BloodFx.on_car(car, Vector3(lx * 0.8, glass.x, glass.y) + gn * 0.05, gn, 0.8)
	GameFeel.play("glass_shatter_1", car.global_position + Vector3.UP * 1.5, world, -10.0, 0.75)


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	mass = 80.0
	gravity_scale = 2.0
	continuous_cd = true # a thin body falling fast went straight through the ground's triangles
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.5, 1.75, 0.34)
	shape.shape = box
	add_child(shape)
	_model = BurningDriver.make_body(female)
	_model.position = Vector3(0, -0.9, 0) # the dummy stands on its feet; the box is centred
	add_child(_model)
	_mat = _model.get_meta("mat")
	(_model.get_meta("anim") as AnimationPlayer).play("limp")
	if burning:
		_fx = BurningDriver.flames(self, 0.9) # "lying": along the body's length, which is the box's Y
	else:
		_heat = 0.0
		_mat.set_shader_parameter("heat", 0.0)


## Our own guard against tunnelling (Godot's continuous_cd still let a fast thin body through the
## ground's triangles now and then): a ray from where the body was to where it is now; if it crossed
## a surface the body is put back on it and loses the speed going into it.
var _last := Vector3.INF


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var now := state.transform.origin
	if _last != Vector3.INF and _last.distance_to(now) > 0.001:
		var dir := (now - _last).normalized()
		var q := PhysicsRayQueryParameters3D.create(_last, now + dir * 0.18, 1)
		var hit := state.get_space_state().intersect_ray(q)
		if not hit.is_empty():
			var n: Vector3 = hit.normal
			state.transform.origin = (hit.position as Vector3) + n * 0.2
			var v := state.linear_velocity
			if v.dot(n) < 0.0:
				v -= n * v.dot(n) * 1.25
			state.linear_velocity = v * 0.6
			now = state.transform.origin
	_last = now


func _physics_process(delta: float) -> void:
	_t += delta
	if not _ride.is_empty():
		_ride_step(delta)
		return
	if not _settled:
		if (_t > 1.0 and linear_velocity.length() < SETTLE_SPEED) or _t > 6.0:
			_settle()
		return
	if burning:
		_heat = maxf(0.0, _heat - delta * 0.25)
		_mat.set_shader_parameter("heat", _heat)
	if _t > BurningDriver.BODY_STAYS:
		position.y -= delta * 0.25
		if _t > BurningDriver.BODY_STAYS + 3.0:
			queue_free()


## Carried on the car: swept up onto the hood (0.12 s), slides up the glass, then thrown off.
func _ride_step(delta: float) -> void:
	_ride_t += delta
	if not is_instance_valid(_car) or _car.is_dead or _car.linear_velocity.length() < 4.0 or _ride_t >= ON_GLASS:
		_let_go()
		return
	var k := clampf(_ride_t / 0.12, 0.0, 1.0)
	var a: Transform3D = _ride[0]
	var b: Transform3D = _ride[1]
	var local := a.interpolate_with(b, k * k * (3.0 - 2.0 * k))
	if _ride_t > 0.12: # slides up the windshield
		local.origin += b.basis.y * 0.3 * ((_ride_t - 0.12) / (ON_GLASS - 0.12))
	global_transform = _car.global_transform * local


func _let_go() -> void:
	var car_v := _car.linear_velocity if is_instance_valid(_car) else Vector3.ZERO
	var right := _car.global_basis.x if is_instance_valid(_car) else Vector3.RIGHT
	_ride = []
	_last = Vector3.INF
	freeze = false
	linear_velocity = car_v * 0.8 + Vector3.UP * 3.5 + right * randf_range(-2.5, 2.5)
	angular_velocity = (right * randf_range(4.0, 7.0) + Vector3.UP * randf_range(-2.0, 2.0))
	_t = 0.0


func _settle() -> void:
	_settled = true
	_t = 0.0
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	freeze = true
	if bloody:
		BloodFx.pool(get_parent(), global_position, 1.0)
	if burning and _fx.size() == 2:
		var fire: CPUParticles3D = _fx[0]
		var smoke: CPUParticles3D = _fx[1]
		# The body lies however it landed: point the flames and smoke up in the world, not along the
		# body (sideways smoke along the ground bunched into a black ball beside the head).
		var up := global_basis.inverse() * Vector3.UP
		fire.direction = up
		smoke.direction = up
		smoke.global_position = global_position + Vector3.UP * 0.4
		smoke.emitting = true
		get_tree().create_timer(2.5, false).timeout.connect(func() -> void:
			if is_instance_valid(fire):
				fire.emitting = false)
		get_tree().create_timer(9.0, false).timeout.connect(func() -> void:
			if is_instance_valid(smoke):
				smoke.emitting = false)
