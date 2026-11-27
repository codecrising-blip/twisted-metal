class_name AshCloud
extends Node3D
## Darkside's secondary (round 28, design 01 ch 11; round 29, owner: "a smoke screen that hides him completely"):
## his stacks and his whole body pour out thick black ash for "time" s and it hangs "linger" s, a trail "width" m
## wide. While it pours nobody can see or lock him (Vehicle.ash_cover -> is_hidden). Any other car inside it loses
## "drain" energy a second and can't start an energy move (Vehicle.ash_time); Darkside gets half of what they
## lose. The cloud is points dropped along his path every DROP s (the damage test) and smoke emitters (the look):
## the two stacks and a billowing envelope round the truck. For his own driver the ash right in front of the
## camera thins out (distance fade), so he can still drive out of it.
## Round 31 (owner): it starts with a BURST, a black wall racing out to burst_r in burst_time; whoever it reaches
## loses burst_drain energy at once, the burst zone hangs where it burst, and Darkside gets all that is taken.

const DROP := 0.2
const TICK := 0.1

var car: Vehicle
var def: Dictionary
var _points: Array[Vector3] = []
var _born: Array[float] = []
var _burst_at := Vector3.ZERO
var _burst_hit: Array[Vehicle] = []
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
	var size: Vector3 = car.stats.get("size", Vector3(2.9, 2.4, 7.6))
	var stacks: Array = car.model.get_meta("exhaust", [])
	if stacks.is_empty():
		stacks = [Vector3(-size.x * 0.4, size.y + 0.3, -size.z * 0.1), Vector3(size.x * 0.4, size.y + 0.3, -size.z * 0.1)]
	var q := FxKit.particle_mesh(false).duplicate() as QuadMesh
	var m := (q.material as StandardMaterial3D).duplicate() as StandardMaterial3D
	m.billboard_keep_scale = true # round 29: without it every particle quad is drawn 1 m, whatever its scale
	if car.is_player:
		m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
		m.distance_fade_min_distance = 2.5
		m.distance_fade_max_distance = 9.0
	q.material = m
	var linger := float(def.get("linger", 4.0))
	var lots := GraphicsSettings.particles()
	for p: Vector3 in stacks: # the stacks: black columns rolling up and back
		_smoke.append(_emitter(q, p, maxi(16, int(50 * lots)), linger, 0.5, Vector3(0, 1, 0.5), 4.0, 7.0, 3.5, 6.5))
	# the envelope: a low billowing wall all round the truck, the thing that hides him
	var env := _emitter(q, Vector3(0, size.y * 0.4, 0.0), maxi(30, int(100 * lots)), linger, 0.0, Vector3(0, 0.15, 0.3), 0.4, 2.0, 7.0, 12.0)
	env.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	env.emission_box_extents = Vector3(size.x * 0.8, size.y * 0.4, size.z * 0.55)
	env.spread = 180.0
	env.gravity = Vector3(0, 0.12, 0)
	_smoke.append(env)
	_burst(q)
	_snd = GameFeel.loop("fire_loop", self, -6.0, 14.0)
	if _snd:
		_snd.pitch_scale = 0.45 # a deep rumbling pour, not a crackle
		_snd.play()
	GameFeel.play("explosion_big", car.global_position + Vector3.UP * 3.0, car.get_parent(), -10.0, 0.5)


## The burst: thick ash thrown flat out all round him, slowing to a stop at burst_r (damping = v0^2 / 2R), a grey
## ring on the ground, a deep boom and a shake.
func _burst(q: QuadMesh) -> void:
	_burst_at = car.global_position
	var r := float(def.get("burst_r", 13.0))
	var v0 := r / float(def.get("burst_time", 0.3)) * 1.4
	var p := CPUParticles3D.new()
	p.emitting = false
	p.mesh = q
	p.amount = maxi(24, int(70 * GraphicsSettings.particles()))
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = 3.2
	p.lifetime_randomness = 0.3
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 2.0
	p.direction = Vector3(1, 0, 0)
	p.spread = 180.0
	p.flatness = 0.85
	p.gravity = Vector3(0, 0.5, 0)
	p.initial_velocity_min = v0 * 0.75
	p.initial_velocity_max = v0
	p.damping_min = v0 * v0 / (2.0 * r)
	p.damping_max = p.damping_min * 1.15
	p.scale_amount_min = 4.5
	p.scale_amount_max = 8.0
	p.scale_amount_curve = FxKit._grow_curve()
	p.color_ramp = FxKit._ramp([Color(0.03, 0.03, 0.03, 0.0), Color(0.045, 0.043, 0.04, 0.95), Color(0.08, 0.075, 0.07, 0.85),
		Color(0.13, 0.12, 0.11, 0.0)])
	car.get_parent().add_child(p)
	p.global_position = _burst_at + Vector3.UP * 1.4
	p.emitting = true
	var tw := p.create_tween()
	tw.tween_interval(3.8)
	tw.tween_callback(p.queue_free)
	# the zone it leaves: a low ash haze over the whole circle while his stacks pour (cars in it keep draining)
	var haze := CPUParticles3D.new()
	haze.emitting = false
	haze.mesh = q
	haze.amount = maxi(20, int(60 * GraphicsSettings.particles()))
	haze.lifetime = 3.0
	haze.preprocess = 0.0
	haze.local_coords = false
	haze.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	haze.emission_box_extents = Vector3(r * 0.7, 1.2, r * 0.7)
	haze.direction = Vector3.UP
	haze.spread = 60.0
	haze.gravity = Vector3(0, 0.15, 0)
	haze.initial_velocity_min = 0.2
	haze.initial_velocity_max = 0.9
	haze.scale_amount_min = 5.0
	haze.scale_amount_max = 9.0
	haze.scale_amount_curve = FxKit._grow_curve()
	haze.color_ramp = p.color_ramp
	car.get_parent().add_child(haze)
	haze.global_position = _burst_at + Vector3.UP * 1.5
	haze.emitting = true
	_smoke.append(haze)
	GameFeel.shockwave(car.get_parent(), _burst_at, r, Color(0.45, 0.43, 0.4))
	GameFeel.shake(_burst_at, 0.6)
	_tick = 0.0


func _emitter(q: QuadMesh, at: Vector3, amount: int, life: float, radius: float, dir: Vector3, v0: float, v1: float,
		s0: float, s1: float) -> CPUParticles3D:
	var s := CPUParticles3D.new()
	s.emitting = false
	s.mesh = q
	s.amount = amount
	s.lifetime = life
	s.local_coords = false
	s.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	s.emission_sphere_radius = maxf(radius, 0.01)
	s.direction = dir
	s.spread = 30.0
	s.gravity = Vector3(0, -0.4, 0)
	s.initial_velocity_min = v0
	s.initial_velocity_max = v1
	s.damping_min = 1.2
	s.damping_max = 2.2
	s.scale_amount_min = s0
	s.scale_amount_max = s1
	s.scale_amount_curve = FxKit._grow_curve()
	s.color_ramp = FxKit._ramp([Color(0.03, 0.03, 0.03, 0.0), Color(0.05, 0.048, 0.045, 0.92), Color(0.09, 0.085, 0.08, 0.85),
		Color(0.14, 0.13, 0.12, 0.0)])
	s.position = at
	car.model.add_child(s)
	s.emitting = true
	return s


func _physics_process(delta: float) -> void:
	_t += delta
	var pouring := _t < float(def.get("time", 6.0)) and is_instance_valid(car) and not car.is_dead
	if pouring:
		global_position = car.global_position
		car.ash_cover = 0.3
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
	if not pouring and _points.is_empty() and _t > float(def.get("time", 6.0)) + linger:
		for s in _smoke:
			if is_instance_valid(s):
				s.queue_free()
		queue_free()
		return
	# the burst wall racing out: anyone it reaches loses burst_drain at once (once each)
	var burst_r := float(def.get("burst_r", 13.0))
	var grow := clampf(_t / float(def.get("burst_time", 0.3)), 0.0, 1.0)
	var burst_live := _t < float(def.get("time", 6.0)) + 1.5 # the haze thins out after the pour
	var gain := float(def.get("gain", 1.0))
	if grow > 0.0 and burst_live:
		for node in get_tree().get_nodes_in_group("vehicles"):
			var o := node as Vehicle
			if o == car or o.is_dead or _burst_hit.has(o):
				continue
			var p := o.aim_point()
			if absf(p.y - _burst_at.y) < 6.0 and Vector2(p.x - _burst_at.x, p.z - _burst_at.z).length() < burst_r * grow:
				_burst_hit.append(o)
				_steal(o, float(def.get("burst_drain", 60.0)), gain)
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = TICK
	var r := float(def.get("width", 8.0)) * 0.5 + 1.0
	var drain := float(def.get("drain", 10.0)) * TICK
	for node in get_tree().get_nodes_in_group("vehicles"):
		var o := node as Vehicle
		if o == car or o.is_dead:
			continue
		var p := o.aim_point()
		var inside := burst_live and absf(p.y - _burst_at.y) < 6.0 \
			and Vector2(p.x - _burst_at.x, p.z - _burst_at.z).length() < burst_r * grow
		if not inside:
			for c in _points:
				if absf(c.y - p.y) < 5.0 and Vector2(c.x - p.x, c.z - p.z).length() < r:
					inside = true
					break
		if not inside:
			continue
		_steal(o, drain, gain)


## Takes up to amount energy from o (never below 0) and gives gain of it to Darkside.
func _steal(o: Vehicle, amount: float, gain: float) -> void:
	if o.ash_time <= 0.0 and o.is_player:
		o.notice.emit(o, "ASH CLOUD - ENERGY DRAINING")
	o.ash_time = 0.3
	var took := minf(o.energy, amount)
	o.energy -= took
	if is_instance_valid(car) and not car.is_dead:
		car.energy = minf(100.0, car.energy + took * gain)
