class_name SatStrike
extends Node3D
## SAT (owner's design): marks a locked area ahead of the shooter; after `delay` seconds a beam
## from orbit hits it for `damage` (112). The mark is plain to see and the warning ticks faster
## near the end, so a target that keeps moving can get out; one that sits still takes it all.

var shooter: Vehicle
var def := {}
var radius := 7.5

var _t := 0.0
var _delay := 4.0
var _ring: MeshInstance3D
var _disc: MeshInstance3D
var _guide: MeshInstance3D
var _beam: MeshInstance3D
var _struck := false


static func start(v: Vehicle, _id: String, d: Dictionary) -> SatStrike:
	var s := SatStrike.new()
	s.shooter = v
	s.def = d
	s.radius = d.get("radius", 7.5)
	s._delay = d.get("delay", 4.0)
	v.get_parent().add_child(s)
	s.global_position = Specials.ground_below(v.get_parent(), mark_point(v, d))
	if v.is_player:
		v.notice.emit(v, "SAT LOCKED")
	return s


## The locked target's spot when it is ahead and in reach, otherwise a point straight ahead.
static func mark_point(v: Vehicle, d: Dictionary) -> Vector3:
	var t := v.target
	var fwd := v.flat_forward()
	if is_instance_valid(t) and not t.is_dead:
		var to := t.global_position - v.global_position
		var flat := Vector3(to.x, 0, to.z)
		if flat.length() < float(d.get("reach", 80.0)) and fwd.angle_to(flat.normalized()) < deg_to_rad(70.0):
			return t.global_position
	return v.global_position + fwd * float(d.get("ahead", 35.0))


func _ready() -> void:
	var red := MeshKit.emissive(Color(1.0, 0.15, 0.1), 2.5)
	red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring = MeshKit.torus(self, radius - 0.35, radius, Vector3.UP * 0.25, red)
	var fill := StandardMaterial3D.new()
	fill.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fill.albedo_color = Color(1.0, 0.1, 0.05, 0.16)
	fill.cull_mode = BaseMaterial3D.CULL_DISABLED
	_disc = MeshKit.cylinder(self, radius, 0.04, Vector3.UP * 0.2, fill, Vector3.ZERO, 24)
	var guide := fill.duplicate() as StandardMaterial3D
	guide.albedo_color = Color(1.0, 0.2, 0.1, 0.22)
	_guide = MeshKit.cylinder(self, 0.25, 160.0, Vector3.UP * 80.0, guide, Vector3.ZERO, 6)
	for mi: MeshInstance3D in [_ring, _disc, _guide]:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _physics_process(delta: float) -> void:
	_t += delta
	if not _struck:
		# Pulses faster as the strike gets close.
		var left := _delay - _t
		var rate := 2.0 if left > 2.0 else (5.0 if left > 0.8 else 10.0)
		_ring.visible = fmod(_t * rate, 1.0) < 0.6
		_disc.scale = Vector3.ONE * (1.0 - clampf(left / _delay, 0.0, 1.0) * 0.6)
		if _t >= _delay:
			_strike()
		return
	if _beam:
		_beam.scale.x = maxf(0.05, _beam.scale.x - delta * 2.5)
		_beam.scale.z = _beam.scale.x
	if _t > _delay + 1.0:
		queue_free()


func _strike() -> void:
	_struck = true
	_ring.visible = false
	_disc.visible = false
	_guide.visible = false
	var glow := MeshKit.emissive(Color(0.75, 0.85, 1.0), 8.0)
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam = MeshKit.cylinder(self, radius * 0.7, 200.0, Vector3.UP * 100.0, glow, Vector3.ZERO, 16)
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var world := get_parent()
	FxKit.explosion(world, global_position + Vector3.UP, 3.2, Color(0.7, 0.8, 1.0))
	Specials.blast(world, global_position + Vector3.UP, radius, float(def.get("damage", 112.0)), shooter)
