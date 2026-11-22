class_name AshCloud
extends Node3D
## Darkside's secondary (round 28, design 01 ch 11): his stacks pour out black ash for "time" s and it hangs
## behind him "linger" s, a trail "width" m wide. Any other car inside it loses "drain" energy a second and
## can't start an energy move (Vehicle.ash_time); Darkside gets half of what they lose. The cloud is points
## dropped along his path every DROP s (the damage test) and two smoke emitters at the stacks (the look).

const DROP := 0.2
const TICK := 0.1

var car: Vehicle
var def: Dictionary
var _points: Array[Vector3] = []
var _born: Array[float] = []
var _t := 0.0
var _drop := 0.0
var _tick := 0.0
var _smoke: Array[CPUParticles3D] = []
var _snd: AudioStreamPlayer3D


static func start(v: Vehicle, d: Dictionary) -> AshCloud:
	var a := AshCloud.new()
	a.car = v
	a.def = d
	v.get_parent().add_child(a)
	return a


func _ready() -> void:
	var size: Vector3 = car.stats.get("size", Vector3(2.9, 3.6, 7.6))
	var stacks: Array = car.model.get_meta("exhaust", [])
	if stacks.is_empty():
		stacks = [Vector3(-size.x * 0.4, size.y + 0.3, -size.z * 0.1), Vector3(size.x * 0.4, size.y + 0.3, -size.z * 0.1)]
	for p: Vector3 in stacks:
		var s := CPUParticles3D.new()
		s.mesh = FxKit.particle_mesh(false)
		s.amount = maxi(12, int(46 * GraphicsSettings.particles()))
		s.lifetime = float(def.get("linger", 4.0))
		s.local_coords = false
		s.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		s.emission_sphere_radius = 0.4
		s.direction = Vector3(0, 1, 0.4)
		s.spread = 25.0
		s.gravity = Vector3(0, -0.6, 0)
		s.initial_velocity_min = 3.0
		s.initial_velocity_max = 5.0
		s.damping_min = 1.5
		s.damping_max = 2.5
		s.scale_amount_min = 2.6
		s.scale_amount_max = 4.0
		s.scale_amount_curve = FxKit._grow_curve()
		s.color_ramp = FxKit._ramp([Color(0.06, 0.06, 0.06, 0.0), Color(0.09, 0.085, 0.08, 0.7), Color(0.16, 0.15, 0.14, 0.55),
			Color(0.2, 0.19, 0.18, 0.0)])
		s.emitting = false
		s.position = p
		car.model.add_child(s)
		s.emitting = true
		_smoke.append(s)
	_snd = GameFeel.loop("fire_loop", self, -6.0, 14.0)
	if _snd:
		_snd.pitch_scale = 0.45 # a deep rumbling pour, not a crackle
		_snd.play()
	GameFeel.play("explosion_big", car.global_position + Vector3.UP * 3.0, car.get_parent(), -10.0, 0.5)


func _physics_process(delta: float) -> void:
	_t += delta
	var pouring := _t < float(def.get("time", 6.0)) and is_instance_valid(car) and not car.is_dead
	if pouring:
		global_position = car.global_position
		_drop -= delta
		if _drop <= 0.0:
			_drop = DROP
			var back := float(car.stats.get("size", Vector3(2.9, 3.6, 7.6)).z) * 0.5 + 1.0
			_points.append(car.global_position + car.global_basis.z * back + Vector3.UP * 1.5)
			_born.append(_t)
	else:
		for s in _smoke:
			if is_instance_valid(s):
				s.emitting = false
		if _snd and _snd.playing:
			_snd.stop()
	var linger := float(def.get("linger", 4.0))
	while not _born.is_empty() and _t - _born[0] > linger:
		_born.pop_front()
		_points.pop_front()
	if not pouring and _points.is_empty():
		for s in _smoke:
			if is_instance_valid(s):
				s.queue_free()
		queue_free()
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = TICK
	var r := float(def.get("width", 8.0)) * 0.5 + 1.0
	var drain := float(def.get("drain", 15.0)) * TICK
	for node in get_tree().get_nodes_in_group("vehicles"):
		var o := node as Vehicle
		if o == car or o.is_dead:
			continue
		var p := o.aim_point()
		var inside := false
		for c in _points:
			if absf(c.y - p.y) < 5.0 and Vector2(c.x - p.x, c.z - p.z).length() < r:
				inside = true
				break
		if not inside:
			continue
		if o.ash_time <= 0.0 and o.is_player:
			o.notice.emit(o, "ASH CLOUD - ENERGY DRAINING")
		o.ash_time = 0.3
		var took := minf(o.energy, drain)
		o.energy -= took
		if is_instance_valid(car) and not car.is_dead:
			car.energy = minf(100.0, car.energy + took * 0.5)
