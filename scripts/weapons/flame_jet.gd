class_name FlameJet
extends Node3D
## Thumper's Megafire (round 29, owner: "IT'S MEGAFIRE": not the game's ordinary fire out of one point). While it
## burns, a glowing sheet of fire as wide as his nose roars straight ahead, halfway between a beam and a flame
## (TM4's Super Thumper): three crossed ribbons drawn by megafire.gdshader (white-hot core line, yellow-orange
## glazing body streaming forward, red torn edges), cut short where it meets a wall, with fire licking off the
## grille's corners, embers, a splash where it lands, a heat light and a roar. Every TICK s every car inside the
## fire box (range m ahead, half_w wide at the nose widening by spread a metre, height m tall, not behind a wall)
## takes dps x TICK and burns; palms and props in it burn, a running sinner is burnt down. Vehicle drains the
## bar. backfire() is his rear attack: one short burst out of the back.

const TICK := 0.1
const RIBBONS := 4
const SEGS := 14
const VIS_SPREAD := 0.21 # the fire looks wider than the box that burns (it billows past its hot middle)

var car: Vehicle
var def: Dictionary
var _beam: MeshInstance3D
var _mat: ShaderMaterial
var _slices: MeshInstance3D # round 29: cross-sections facing back: the ribbons are edge-on from the chase camera
var _smat: ShaderMaterial
var _licks: Array[FoamFire] = []
var _splash: FoamFire
var _embers: CPUParticles3D
var _snd: AudioStreamPlayer3D
var _roar: AudioStreamPlayer3D
var _light: OmniLight3D
var _t := 0.0
var _on := false
var _level := 0.0 # 0 -> 1 as it lights, back to 0 as it dies
var _reach := 16.0


static func attach(v: Vehicle) -> FlameJet:
	var j := FlameJet.new()
	j.car = v
	j.def = WeaponData.get_def(v.special_id)
	var size: Vector3 = v.stats.get("size", Vector3(2.3, 1.5, 5.8))
	j.position = v.model.get_meta("nozzle", Vector3(0, 0.65, -size.z * 0.5 - 0.15))
	v.model.add_child(j)
	return j


func _ready() -> void:
	_reach = float(def.get("range", 16.0))
	_beam = MeshInstance3D.new()
	_beam.mesh = _beam_mesh(1.0, float(def.get("half_w", 1.2)), VIS_SPREAD)
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://scripts/fx/megafire.gdshader")
	_beam.material_override = _mat
	_beam.visible = false
	_beam.position = Vector3(0, 0.2, 0) # a little over the grille: seen over the hood from the chase camera
	add_child(_beam)
	_slices = MeshInstance3D.new()
	_slices.mesh = _slice_mesh(float(def.get("half_w", 1.2)), VIS_SPREAD)
	_slices.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_smat = ShaderMaterial.new()
	_smat.shader = _mat.shader
	_smat.set_shader_parameter("slice", 1.0)
	_slices.material_override = _smat
	_beam.add_child(_slices)
	for sx: float in [-1.0, 1.0]: # fire licking off the grille's corners and streaming back over the hood
		var f := FoamFire.new()
		f.box = Vector3(0.18, 0.15, 0.1)
		f.position = Vector3(sx * float(def.get("half_w", 1.25)) * 0.8, 0.05, -0.2)
		f.rate = 40.0
		f.life = 0.4
		f.size = 0.55
		f.rise = 1.4
		f.inherit = 0.9
		f.drag = 2.5
		f.jet = 9.0
		f.jet_spread = 0.45
		f.rise_in = 14.0
		f.die_out = 6.0
		add_child(f)
		_licks.append(f)
	_splash = FoamFire.new() # where the beam lands on a wall: a heap of fire spilling up and sideways
	_splash.box = Vector3(1.4, 0.4, 0.4)
	_splash.rate = 46.0
	_splash.life = 0.55
	_splash.size = 0.9
	_splash.rise = 3.2
	_splash.top_level = true
	add_child(_splash)
	_embers = CPUParticles3D.new()
	_embers.emitting = false # off before it enters the tree (round 17 gotcha: a frozen first particle)
	_embers.mesh = FxKit.particle_mesh(true)
	_embers.amount = 40
	_embers.lifetime = 0.6
	_embers.local_coords = false
	_embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_embers.emission_box_extents = Vector3(0.9, 0.2, 0.2)
	_embers.direction = Vector3(0, 0.12, -1)
	_embers.spread = 9.0
	_embers.gravity = Vector3(0, 3.0, 0)
	_embers.initial_velocity_min = 22.0
	_embers.initial_velocity_max = 34.0
	_embers.scale_amount_min = 0.05
	_embers.scale_amount_max = 0.12
	_embers.color_ramp = FxKit._ramp([Color(1, 0.95, 0.7, 1), Color(1, 0.55, 0.12, 0.8), Color(0.8, 0.15, 0.03, 0)])
	add_child(_embers)
	_snd = GameFeel.loop("fire_loop", self, 3.0, 16.0)
	if _snd:
		_snd.pitch_scale = 0.7 # deeper than any burning car
	_roar = GameFeel.loop("megafire_roar", self, 2.0, 18.0)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.6, 0.25)
	_light.omni_range = 18.0
	_light.light_energy = 0.0
	_light.position = Vector3(0, 0.6, -6.0)
	_light.add_to_group(GraphicsSettings.EXTRA_LIGHT_GROUP)
	_light.visible = GraphicsSettings.high
	add_child(_light)


## Three ribbons crossed round the beam's axis (-Z), RIBBONS x SEGS quads, one unit long (scaled to the reach):
## wide across and nearly as tall, so from the low chase camera it reads as a wall of fire, not a flat strip.
static func _beam_mesh(length: float, half_w: float, spread: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for r in RIBBONS:
		var a := PI * float(r) / float(RIBBONS)
		for k in SEGS:
			var v0 := float(k) / SEGS
			var v1 := float(k + 1) / SEGS
			var pts := []
			for v: float in [v0, v1]:
				var w := half_w + spread * 16.0 * pow(v, 0.85)
				var across := Vector3(cos(a) * w, sin(a) * (w * 0.7 + 0.4), 0.0) # tall too: a wall of fire seen from behind
				var z := -v * length
				pts.append([Vector3(-across.x, -across.y, z), Vector3(across.x, across.y, z), v])
			var q := [[pts[0][0], Vector2(0, v0)], [pts[0][1], Vector2(1, v0)], [pts[1][1], Vector2(1, v1)], [pts[1][0], Vector2(0, v1)]]
			for idx: int in [0, 1, 2, 0, 2, 3]:
				st.set_uv(q[idx][1])
				st.add_vertex(q[idx][0])
	return st.commit()


## Cross-sections of the fire every metre or so along the beam (one unit long, scaled with it), each as big as
## the beam is there: from behind they stack into the wide wall of fire the ribbons can't show end-on.
static func _slice_mesh(half_w: float, spread: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 12
	for k in n:
		var v := (float(k) + 0.6) / float(n)
		var w := half_w + spread * 16.0 * pow(v, 0.85)
		var h := w * 0.7 + 0.4
		var z := -v
		var q := [[Vector3(-w, -h, z), Vector2(0, 1)], [Vector3(w, -h, z), Vector2(1, 1)], [Vector3(w, h, z), Vector2(1, 0)], [Vector3(-w, h, z), Vector2(0, 0)]]
		for idx: int in [0, 1, 2, 0, 2, 3]:
			st.set_uv(q[idx][1])
			st.set_uv2(Vector2(v, 0.0))
			st.add_vertex(q[idx][0])
	return st.commit()


func set_on(on: bool) -> void:
	_on = on
	for f in _licks:
		f.on = on
	_embers.emitting = on
	if on:
		_t = 0.0
		_beam.visible = true
		GameFeel.play("special_thumper", global_position, car, float(def.get("sound_db", 0.0)) - 1.0, randf_range(0.95, 1.05))
		GameFeel.play("launch_fire", global_position, car, -2.0, 0.6)
		for p in [_snd, _roar]:
			if p and not (p as AudioStreamPlayer3D).playing:
				(p as AudioStreamPlayer3D).play()
	else:
		_splash.on = false
		for p in [_snd, _roar]:
			if p:
				(p as AudioStreamPlayer3D).stop()


func _physics_process(delta: float) -> void:
	_level = move_toward(_level, 1.0 if _on else 0.0, delta * (7.0 if _on else 5.0))
	_light.light_energy = 4.0 * _level
	if _level <= 0.0:
		_beam.visible = false
		return
	if not is_instance_valid(car) or car.is_dead:
		set_on(false)
		return
	# the beam is cut short where it meets the world; the splash heap sits there
	var fwd := -global_basis.z
	var from := global_position
	var reach := _reach
	var q := PhysicsRayQueryParameters3D.create(from, from + fwd * _reach, 1)
	q.exclude = [car.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		reach = maxf(1.0, from.distance_to(hit.position))
	_beam.scale = Vector3(1.0, 1.0, reach)
	var glow := (0.85 + 0.12 * sin(Time.get_ticks_msec() * 0.031)) * minf(1.0, _level * 1.6)
	for m: ShaderMaterial in [_mat, _smat]:
		m.set_shader_parameter("length_m", reach)
		m.set_shader_parameter("ignite", _level if _on else 1.0)
		m.set_shader_parameter("intensity", glow)
	_splash.on = _on and not hit.is_empty()
	if _splash.on:
		_splash.global_position = (hit.position as Vector3) - fwd * 0.4
	if not _on:
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = TICK
	burn_box(car, from, fwd, reach, float(def.get("half_w", 1.25)), float(def.get("spread", 0.11)),
		float(def.get("height", 2.4)), float(def.get("dps", 38.0)) * TICK, float(def.get("burn", 2.0)))
	if car.is_player and GameFeel.camera:
		GameFeel.camera.add_shake(0.06)


## Round 29: everything inside the Megafire's box: cars (not behind walls), props, running sinners.
static func burn_box(by: Vehicle, origin: Vector3, fwd: Vector3, reach: float, half_w: float, spread: float, height: float,
		damage: float, burn: float) -> void:
	var space := by.get_world_3d().direct_space_state
	var flat := Vector3(fwd.x, 0.0, fwd.z).normalized()
	var side := flat.cross(Vector3.UP)
	for node in by.get_tree().get_nodes_in_group("vehicles"):
		var o := node as Vehicle
		if o == by or o.is_dead:
			continue
		var size: Vector3 = o.stats.get("size", Vector3(2.2, 1.8, 5.0))
		var to := o.aim_point() - origin
		var along := to.dot(flat)
		if along < -size.z * 0.4 or along > reach + size.z * 0.35:
			continue
		var w := half_w + spread * maxf(along, 0.0) + maxf(size.x, size.z) * 0.45
		if absf(to.dot(side)) > w or absf(to.y) > height:
			continue
		var q := PhysicsRayQueryParameters3D.create(origin, o.aim_point(), 1)
		q.exclude = [by.get_rid(), o.get_rid()]
		if not space.intersect_ray(q).is_empty():
			continue # the fire doesn't go through walls
		o.take_damage(damage * WeaponData.DAMAGE_SCALE, by)
		o.ignite(burn, by)
		o.hit_react(to, damage)
	for node in by.get_tree().get_nodes_in_group(&"breakables"):
		var b := node as Breakable
		if b and not b.is_broken and randf() < 0.3:
			var tb := b.global_position + Vector3.UP - origin
			var al := tb.dot(flat)
			if al > 0.0 and al < reach and absf(tb.dot(side)) < half_w + spread * al + 1.0:
				b.weapon_hit(damage * 2.0, by, origin, true)
	for node in by.get_tree().get_nodes_in_group(&"sinners"):
		var sn := node as Node3D
		var ts := sn.global_position + Vector3.UP - origin
		var al2 := ts.dot(flat)
		if al2 > 0.0 and al2 < reach and absf(ts.dot(side)) < half_w + spread * al2 + 0.6:
			sn.call("projectile_hit", damage * 2.0, by)


## Everything in a cone of fire: cars (not behind walls), props, running sinners.
static func scorch(by: Vehicle, origin: Vector3, fwd: Vector3, reach: float, cone_deg: float, damage: float, burn: float) -> void:
	var world := by.get_parent()
	var space := by.get_world_3d().direct_space_state
	var cone := deg_to_rad(cone_deg)
	for node in by.get_tree().get_nodes_in_group("vehicles"):
		var o := node as Vehicle
		if o == by or o.is_dead:
			continue
		var to := o.aim_point() - origin
		var d := to.length()
		var size: Vector3 = o.stats.get("size", Vector3(2.2, 1.8, 5.0))
		if d > reach + size.z * 0.4 or d < 0.01:
			continue
		if fwd.angle_to(to / d) > cone + atan2(size.x * 0.6, d):
			continue
		var q := PhysicsRayQueryParameters3D.create(origin, o.aim_point(), 1)
		q.exclude = [by.get_rid(), o.get_rid()]
		if not space.intersect_ray(q).is_empty():
			continue # the flame doesn't go through walls
		o.take_damage(damage * WeaponData.DAMAGE_SCALE, by)
		o.ignite(burn, by)
		o.hit_react(to, damage)
	for node in by.get_tree().get_nodes_in_group(&"breakables"):
		var b := node as Breakable
		if b and not b.is_broken and randf() < 0.3:
			var tb := b.global_position + Vector3.UP - origin
			if tb.length() < reach and fwd.angle_to(tb.normalized()) < cone * 1.5:
				b.weapon_hit(damage * 2.0, by, origin, true)
	for node in by.get_tree().get_nodes_in_group(&"sinners"):
		var s := node as Node3D
		var ts := s.global_position + Vector3.UP - origin
		if ts.length() < reach and fwd.angle_to(ts.normalized()) < cone * 1.6:
			s.call("projectile_hit", damage * 2.0, by)


## Backfire (Thumper's rear attack): a short burst of flame out of the back, 8 m, damage + burning, once.
static func backfire(v: Vehicle) -> void:
	var d := WeaponData.get_def("backfire")
	var size: Vector3 = v.stats.get("size", Vector3(2.3, 1.5, 5.8))
	var holder := Node3D.new()
	holder.position = Vector3(0, 0.6, size.z * 0.5 + 0.2)
	holder.rotation.y = PI # the jet shoots along -Z: turned round, out of the back
	v.model.add_child(holder)
	var f := FoamFire.new()
	f.box = Vector3(0.3, 0.15, 0.1)
	f.rate = 140.0
	f.life = 0.45
	f.size = 0.9
	f.rise = 0.6
	f.inherit = 1.0
	f.drag = 2.4
	f.jet = float(d.get("range", 8.0)) * 2.3
	f.jet_spread = 0.35
	f.rise_in = 20.0
	f.die_out = 4.0
	f.on = true
	holder.add_child(f)
	GameFeel.play("special_thumper", holder.global_position, v, 0.0, 1.15)
	GameFeel.play("launch_fire", holder.global_position, v, -4.0, 0.7)
	scorch(v, v.global_position + v.global_basis.z * (size.z * 0.5) + Vector3.UP * 0.8, -v.level_forward(),
		float(d.get("range", 8.0)), float(d.get("cone", 25.0)), float(d.get("damage", 12.0)), float(d.get("burn", 4.0)))
	var tree := v.get_tree()
	tree.create_timer(float(d.get("time", 0.7)), false).timeout.connect(func() -> void:
		if is_instance_valid(f):
			f.on = false)
	tree.create_timer(2.5, false).timeout.connect(func() -> void:
		if is_instance_valid(holder):
			holder.queue_free())
