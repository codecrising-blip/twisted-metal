class_name VehicleFx
extends Node
## Looks only, no gameplay: spinning gatlings with muzzle flashes, turbo flames from the exhausts,
## the springy roof mascot, tire smoke when the car slides. The Vehicle calls update() every
## physics step and gun_fired() for each machine-gun shot. Reads the model's metadata:
##   gun_spinners  Node3D per gatling (barrels along -Z, spun around Z)
##   exhaust       exhaust points (local); exhaust_dir = where the flames point (default backward)
##   bobble        Node3D that sways on a spring

const FLASH_TIME := 0.05
const SPIN_MAX := 38.0 # rad/s at full fire
const BOB_STIFF := 70.0
const BOB_DAMP := 5.5

var _model: Node3D
var _spinners: Array = []
var _spin := 0.0
var _flashes: Array[MeshInstance3D] = []
var _flash_left: Array[float] = []
var _flash_light: OmniLight3D
var _turbo: Array[CPUParticles3D] = []
var _skid: Array[CPUParticles3D] = []
var _bobble: Node3D
var _bob := Vector2.ZERO # x = pitch, y = roll (radians)
var _bob_vel := Vector2.ZERO
var _last_vel := Vector3.ZERO


func setup(model: Node3D) -> void:
	_model = model
	_spinners = model.get_meta("gun_spinners", [])
	var guns: Array = model.get_meta("guns", [])
	for g: Vector3 in guns:
		var f := MeshInstance3D.new()
		f.mesh = _flash_mesh()
		f.position = g + Vector3(0, 0, -0.15)
		f.visible = false
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		model.add_child(f)
		_flashes.append(f)
		_flash_left.append(0.0)
	if not guns.is_empty():
		_flash_light = OmniLight3D.new()
		_flash_light.light_color = Color(1.0, 0.75, 0.35)
		_flash_light.light_energy = 0.0
		_flash_light.omni_range = 6.0
		_flash_light.position = guns[0]
		model.add_child(_flash_light)
	var dir: Vector3 = model.get_meta("exhaust_dir", Vector3.BACK)
	for e: Vector3 in model.get_meta("exhaust", []):
		var p := FxKit.fire(0.45, 22)
		p.local_coords = false
		p.position = e
		p.direction = dir
		p.spread = 8.0
		p.gravity = Vector3(0, 1.0, 0)
		p.initial_velocity_min = 5.0
		p.initial_velocity_max = 8.0
		p.lifetime = 0.22
		p.color_ramp = FxKit._ramp([Color(0.55, 0.75, 1.0, 0.95), Color(1.0, 0.7, 0.3, 0.8), Color(1.0, 0.3, 0.05, 0.4), Color(0.2, 0.05, 0.0, 0.0)])
		p.emitting = false
		model.add_child(p)
		_turbo.append(p)
	var wheels: Array = model.get_meta("wheels", [])
	var r: float = model.get_meta("wheel_radius", 0.5)
	for w: Node3D in wheels:
		# Rear wheels only (the ones that don't steer); spin pivot sits under a steer pivot.
		if (model.get_meta("steer", []) as Array).has(w.get_parent()):
			continue
		var s := FxKit.smoke(0.55, 14)
		s.position = _local_pos(model, w)
		s.position.y = r * 0.3
		s.emitting = false
		model.add_child(s)
		_skid.append(s)
	_bobble = model.get_meta("bobble") if model.has_meta("bobble") else null


static func _local_pos(model: Node3D, n: Node3D) -> Vector3:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != model:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf.origin


static var _flash_mesh_cache: QuadMesh

static func _flash_mesh() -> QuadMesh:
	if _flash_mesh_cache == null:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.albedo_texture = FxKit.soft_texture()
		m.albedo_color = Color(1.0, 0.8, 0.4)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.disable_receive_shadows = true
		_flash_mesh_cache = QuadMesh.new()
		_flash_mesh_cache.size = Vector2(0.9, 0.9)
		_flash_mesh_cache.material = m
	return _flash_mesh_cache


func gun_fired(index: int) -> void:
	_spin = SPIN_MAX
	if _flashes.is_empty():
		return
	var i := index % _flashes.size()
	_flash_left[i] = FLASH_TIME
	_flashes[i].visible = true
	_flashes[i].rotation.z = randf() * TAU
	var s := randf_range(0.8, 1.3)
	_flashes[i].scale = Vector3(s, s, s)
	if _flash_light:
		_flash_light.position = _flashes[i].position
		_flash_light.light_energy = 2.5


## Wrecked or removed: no more flames or smoke from this car.
func stop() -> void:
	for p in _turbo:
		p.emitting = false
	for p in _skid:
		p.emitting = false
	for f in _flashes:
		f.visible = false
	if _flash_light:
		_flash_light.light_energy = 0.0


## car_velocity in world space; boosting = turbo on; sliding = handbrake drift on the ground.
func update(delta: float, car: Node3D, car_velocity: Vector3, boosting: bool, sliding: bool) -> void:
	# Gatlings wind down after the trigger is released.
	_spin = move_toward(_spin, 0.0, 30.0 * delta)
	if _spin > 0.0:
		for s: Node3D in _spinners:
			s.rotate_object_local(Vector3.FORWARD, _spin * delta)
	for i in _flashes.size():
		if _flash_left[i] > 0.0:
			_flash_left[i] -= delta
			if _flash_left[i] <= 0.0:
				_flashes[i].visible = false
	if _flash_light and _flash_light.light_energy > 0.0:
		_flash_light.light_energy = maxf(0.0, _flash_light.light_energy - 60.0 * delta)
	for p in _turbo:
		p.emitting = boosting
	for p in _skid:
		p.emitting = sliding
	# Mascot spring: pushed by the car's acceleration in its own frame, swings back.
	if _bobble and delta > 0.0:
		var accel := (car_velocity - _last_vel) / delta
		var local := car.global_basis.inverse() * accel
		var push := Vector2(-local.z, local.x) * 0.0035 # braking tips it forward, turning swings it out
		_bob_vel += (push * BOB_STIFF - _bob * BOB_STIFF - _bob_vel * BOB_DAMP) * delta
		_bob += _bob_vel * delta
		_bob = _bob.clamp(Vector2(-0.45, -0.45), Vector2(0.45, 0.45))
		_bobble.rotation = Vector3(_bob.x, 0.0, _bob.y)
	_last_vel = car_velocity
