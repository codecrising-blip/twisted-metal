class_name SatStrike
extends Node3D
## SAT (owner, play-test 2): the strike zone is locked `ahead` meters in front of the shooter's car
## and moves with it. For `delay` seconds you steer to keep your enemy inside it (it goes left, you
## go left), then the beam from orbit hits wherever the zone is for `damage` (112), you included if
## you somehow end up inside it.
## Round 9 (owner: "lazy in every aspect"), built on the juice guide's five beats:
## TELL     the marker (SatMarker) turns yellow -> orange -> red as the strike nears, its disc fills,
##          it pulses faster with a rising tick; the scan hum climbs; the owner's incoming whistle
##          rides WITH the zone (it used to stay where it started and fade behind the car).
## TRAVEL   a guide beam from the sky thickens, a charge point glows up there, rings fall down the
##          beam and shrink onto the zone, faster and faster; a white column flickers just before.
## IMPACT   one frame: the beam slams down wide and white-hot, flash, two shockwaves, a blast with
##          debris, sparks, hit-stop if the player is in it, every sound layer synced to this frame.
## AFTERMATH the beam narrows and fades, a molten ring glows and cools, scorch, dust, a smoke column.

var shooter: Vehicle
var def := {}
var radius := 7.5

var _t := 0.0
var _delay := 4.0
var _marker: SatMarker
var _guide: MeshInstance3D
var _guide_mat: StandardMaterial3D
var _orb: MeshInstance3D
var _orb_mat: StandardMaterial3D
var _drop_mat: StandardMaterial3D
var _drops: Array[MeshInstance3D] = []
var _next_drop := 0.0
var _struck := false
var _scan: AudioStreamPlayer3D
var _incoming: AudioStreamPlayer3D
var _pulse_on := false
var _tell: MeshInstance3D
var _core: MeshInstance3D
var _glow: MeshInstance3D
var _molten: MeshInstance3D
var _halo: MeshInstance3D
var _splash: MeshInstance3D

const SKY := 70.0 # height of the charge point
const DROP_FALL := 0.55 # seconds a falling ring takes from the sky to the zone
const TELL_TIME := 0.15 # the thin white column before the beam
const WHISTLE_LEAD := 2.3 # the incoming whistle starts this long before the beam (its rise + plateau)


static func start(v: Vehicle, _id: String, d: Dictionary) -> SatStrike:
	var s := SatStrike.new()
	s.shooter = v
	s.def = d
	s.radius = d.get("radius", 7.5)
	s._delay = d.get("delay", 4.0)
	v.get_parent().add_child(s)
	s.global_position = zone_point(v, d)
	s.add_to_group(&"sat_strikes")
	GameFeel.play("sat_launch", v.global_position + Vector3.UP * 2.0, v.get_parent(), 0.0, 0.85) # off it goes, up to the satellite
	GameFeel.play("sat_lock", v.global_position + Vector3.UP * 2.0, v.get_parent(), -4.0) # lock tone: the zone is yours
	if v.is_player:
		v.notice.emit(v, "SAT LOCKED - KEEP THEM IN FRONT")
	return s


## Ground point `ahead` meters in front of the car.
static func zone_point(v: Vehicle, d: Dictionary) -> Vector3:
	var p := v.global_position + v.flat_forward() * float(d.get("ahead", 24.0)) + Vector3.UP * 3.0
	return Specials.ground_below(v.get_parent(), p)


## True while a strike fired by this car is still on its way (the preview hides meanwhile).
static func busy(v: Vehicle) -> bool:
	for n in v.get_tree().get_nodes_in_group(&"sat_strikes"):
		var s := n as SatStrike
		if s and s.shooter == v and not s._struck:
			return true
	return false


func _ready() -> void:
	_marker = SatMarker.make(self, radius)
	_guide = _beam(0.5, Color.WHITE, SKY)
	_guide_mat = _guide.material_override as StandardMaterial3D
	_orb_mat = _additive()
	_orb = MeshKit.sphere(self, 1.0, Vector3.UP * SKY, _orb_mat, Vector3.ONE, 10)
	_drop_mat = _additive()
	_orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_paint(0.0, 1.0)
	# TM 2012 satellite sounds: the scan hums while the zone is locked and climbs as it nears.
	_scan = GameFeel.loop("sat_scan_loop", self, -10.0, 18.0)
	if _scan:
		_scan.play()


static var _soft_tex: GradientTexture2D


## A soft vertical beam: a quad that always turns to face the camera round its own axis, bright in
## the middle and fading to nothing at both edges (no hard cylinder edges). `width` in meters.
func _beam(width: float, color: Color, height := 200.0) -> MeshInstance3D:
	if _soft_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
		_soft_tex = GradientTexture2D.new()
		_soft_tex.gradient = g
		_soft_tex.width = 64
		_soft_tex.height = 4
		_soft_tex.fill_from = Vector2(0, 0.5)
		_soft_tex.fill_to = Vector2(1, 0.5)
	var m := _additive()
	m.albedo_texture = _soft_tex
	m.albedo_color = color
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.billboard_keep_scale = true
	var q := QuadMesh.new()
	q.size = Vector2(1.0, height)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3.UP * height * 0.5
	mi.scale = Vector3(width, 1.0, 1.0)
	add_child(mi)
	return mi


static func _additive() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _physics_process(delta: float) -> void:
	_t += delta
	if not _struck:
		if is_instance_valid(shooter) and not shooter.is_dead:
			global_position = global_position.lerp(zone_point(shooter, def), minf(1.0, 20.0 * delta))
		_approach(delta)
		if _t >= _delay:
			_strike()
		return
	_aftermath(delta)


## The tell and the travel: colour, pulse, fill, sounds, the guide beam, falling rings.
func _approach(delta: float) -> void:
	var left := _delay - _t
	var p := clampf(_t / _delay, 0.0, 1.0)
	# Pulse: 2 a second, 5 in the last 2 s, 10 in the last 0.8 s; a tick on each, rising in pitch.
	var rate := 2.0 if left > 2.0 else (5.0 if left > 0.8 else 10.0)
	var on := fmod(_t * rate, 1.0) < 0.55
	if on and not _pulse_on:
		GameFeel.play("sat_tick", global_position + Vector3.UP, get_parent(), -6.0, lerpf(0.9, 1.4, p))
	_pulse_on = on
	_paint(p, 1.0 if on else 0.55)
	_marker.set_fill(p)
	_marker.spin_speed = lerpf(0.5, 4.0, p * p)
	if _scan:
		_scan.pitch_scale = lerpf(0.9, 1.3, p)
		_scan.volume_db = lerpf(-10.0, -3.0, p)
	# The owner's incoming whistle, fixed to the zone so it travels with it, eased in (round 9).
	if _incoming == null and left <= WHISTLE_LEAD:
		_incoming = GameFeel.play("sat_incoming", global_position + Vector3.UP * 5.0, self, -14.0)
		if _incoming:
			_incoming.pitch_scale = 1.0
			_incoming.unit_size = 30.0
			GameFeel._soften(_incoming, 30.0) # round 24: half the distance fade
			_incoming.create_tween().tween_property(_incoming, "volume_db", 4.0, 0.7).set_ease(Tween.EASE_OUT)
	# Guide beam: thin and faint at first, thicker and brighter as the strike nears.
	_guide.scale.x = lerpf(0.6, 2.4, p * p)
	_orb.scale = Vector3.ONE * lerpf(0.8, 3.2, p) * (1.0 + 0.15 * sin(_t * 30.0))
	# Rings falling down the beam and shrinking onto the zone, more often as it nears.
	_next_drop -= delta
	if _next_drop <= 0.0 and left > DROP_FALL * 0.5:
		_next_drop = lerpf(0.7, 0.14, p)
		var ring := MeshKit.torus(self, radius * 0.92, radius, Vector3.UP * SKY, _drop_mat)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.set_meta(&"age", 0.0)
		_drops.append(ring)
	for ring in _drops.duplicate():
		var age: float = float(ring.get_meta(&"age")) + delta
		ring.set_meta(&"age", age)
		var f := clampf(age / DROP_FALL, 0.0, 1.0)
		ring.position.y = lerpf(SKY, 0.4, f * f) # accelerating down
		var s := lerpf(2.2, 1.0, f)
		ring.scale = Vector3(s, 0.5, s)
		if f >= 1.0:
			_drops.erase(ring)
			ring.queue_free()
	if left <= TELL_TIME and _tell == null:
		_tell = _beam(1.2, Color(1.0, 1.0, 1.0, 1.0))
	if _tell:
		_tell.visible = fmod(_t * 30.0, 1.0) < 0.7


## One tint for the marker, the guide, the charge point and the falling rings.
func _paint(p: float, pulse: float) -> void:
	var c := SatMarker.heat(p)
	_marker.set_tint(c, 0.55 + 0.4 * pulse, 0.1 + 0.12 * pulse)
	_guide_mat.albedo_color = Color(c.r, c.g, c.b, lerpf(0.35, 0.8, p) * pulse)
	_orb_mat.albedo_color = Color(c.r, c.g, c.b, 0.8)
	_drop_mat.albedo_color = Color(c.r, c.g, c.b, 0.55)


func _strike() -> void:
	_struck = true
	_t = 0.0
	if _scan:
		_scan.stop()
	if is_instance_valid(_incoming): # the whistle melts into the blast instead of being cut
		var tw := _incoming.create_tween()
		tw.tween_property(_incoming, "volume_db", -40.0, 0.35).set_ease(Tween.EASE_IN)
		tw.tween_callback(_incoming.queue_free)
	for n: Node in [_tell, _guide, _orb, _marker]:
		if n:
			n.queue_free()
	_tell = null
	for ring in _drops:
		ring.queue_free()
	_drops.clear()
	# Impact (owner, round 6 "bigger", round 8 "in sync", round 9 "not just a pillar of light"):
	# every sound layer synced so its loudest moment lands on this frame with the flash.
	var world := get_parent()
	var at := global_position + Vector3.UP
	GameFeel.play("sat_strike", at + Vector3.UP, world, 6.0, 1.0, true)
	GameFeel.play("explosion_big_3", at, world, 5.0, 0.85, true)
	GameFeel.play("explosion_big_4", at, world, 3.0, 0.55, true)
	# The beam (round 9: not "a pillar of light"): soft layers, no hard edges. A white-hot core, a
	# blue-white glow round it and a wide faint halo; it slams in at full width and draws in.
	_core = _beam(2.6, Color(1.0, 1.0, 1.0, 1.0))
	_glow = _beam(7.0, Color(0.45, 0.65, 1.0, 0.85))
	_halo = _beam(radius * 3.2, Color(0.4, 0.55, 1.0, 0.35))
	# The ground where it bites: a white-hot splash disc, gone in a blink.
	var splash_mat := _additive()
	splash_mat.albedo_texture = FxKit.soft_texture()
	splash_mat.albedo_color = Color(0.85, 0.92, 1.0, 1.0)
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * radius * 3.0
	_splash = MeshInstance3D.new()
	_splash.mesh = plane
	_splash.material_override = splash_mat
	_splash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_splash.position.y = 0.35
	add_child(_splash)
	# A molten ring left on the ground, glowing then cooling.
	var hot := _additive()
	hot.albedo_color = Color(1.0, 0.5, 0.12, 0.9)
	_molten = MeshKit.torus(self, radius * 0.55, radius * 0.8, Vector3.UP * 0.3, hot)
	_molten.scale = Vector3(1.0, 0.15, 1.0)
	_molten.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Fire against the cold beam: a white-blue burst on the ground, an orange fireball rolling up out
	# of it a beat later (the guide's two-colour layering).
	FxKit.explosion(world, at, 2.2, Color(0.6, 0.75, 1.0), false)
	get_tree().create_timer(0.06, false).timeout.connect(func() -> void:
		if is_instance_valid(world) and world.is_inside_tree():
			FxKit.explosion(world, at + Vector3.UP * 2.0, 2.6, Color(1.0, 0.5, 0.15), false)
			FxKit.explosion(world, at + Vector3.UP * 4.5, 1.6, Color(1.0, 0.35, 0.1), false))
	GameFeel.flash(world, global_position + Vector3.UP * 2.0, radius * 0.8, Color(0.55, 0.7, 1.0), 0.1)
	GameFeel.shockwave(world, global_position, radius * 2.0, Color(1.0, 1.0, 1.0))
	var ground := world
	get_tree().create_timer(0.08, false).timeout.connect(func() -> void:
		if is_instance_valid(ground) and ground.is_inside_tree():
			GameFeel.shockwave(ground, at - Vector3.UP, radius * 4.0, Color(0.6, 0.8, 1.0)))
	for k in 6:
		var a := k * TAU / 6.0 + randf() * 0.5
		FxKit.spark(world, global_position + Vector3(sin(a), 0.3, cos(a)) * radius * 0.6, Vector3(sin(a), 1.4, cos(a)).normalized())
	FxKit.crash_burst(world, at, Vector3.UP, 1.0)
	FxKit.dust_ring(world, global_position, 2.2)
	GameFeel.scorch(world, at, radius * 1.1)
	FxKit.smoke_column(world, global_position, 1.8)
	var hit_player := is_instance_valid(shooter) and shooter.is_player
	var caught := false
	for o in Specials.cars_near(world, at, radius + 1.0, null):
		if o.is_player:
			hit_player = true
			caught = true
			GameFeel.flash_bang(float(def.get("flashbang", 1.0)))
			if GameFeel.camera:
				GameFeel.camera.add_shake(float(def.get("shake", 1.0)))
	# The impact frame: anyone watching from near enough gets one white blink of the screen.
	if not caught and GameFeel.camera and GameFeel.camera.global_position.distance_to(at) < 70.0:
		GameFeel.flash_bang(0.1)
	GameFeel.shake(global_position, 0.7, 100.0)
	if hit_player:
		GameFeel.hitstop(get_tree(), 0.1, 0.05)
	Specials.blast(world, at, radius, float(def.get("damage", 112.0)), shooter)


## The beam draws in to a thread and fades, the splash blinks out, the molten ring cools.
func _aftermath(_delta: float) -> void:
	var c := clampf(1.0 - _t / 0.45, 0.0, 1.0)
	_core.scale.x = 2.6 * c * c + 0.05
	_core.visible = c > 0.0
	var g := clampf(1.0 - _t / 0.7, 0.0, 1.0)
	_glow.scale.x = lerpf(1.0, 7.0, g)
	(_glow.material_override as StandardMaterial3D).albedo_color.a = 0.85 * g
	var h := clampf(1.0 - _t / 0.25, 0.0, 1.0)
	_halo.visible = h > 0.0
	(_halo.material_override as StandardMaterial3D).albedo_color.a = 0.35 * h
	var sp := clampf(1.0 - _t / 0.3, 0.0, 1.0)
	_splash.visible = sp > 0.0
	_splash.scale = Vector3.ONE * lerpf(1.25, 0.8, sp)
	(_splash.material_override as StandardMaterial3D).albedo_color.a = sp
	if _molten:
		var m := clampf(1.0 - _t / 2.5, 0.0, 1.0)
		var mat := _molten.material_override as StandardMaterial3D
		mat.albedo_color = Color(1.0, lerpf(0.15, 0.5, m), lerpf(0.02, 0.12, m), 0.9 * m)
	if _t > 2.6:
		queue_free()
