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


# ---------------------------------------------------------------- headlights (round 7)
# A real SpotLight3D on the Compatibility renderer draws everything it touches a second time, and
# the merged stage meshes are big enough that it touches them all. So on LOW the beam is faked like
# on the PS2: a soft pool of light painted on the ground ahead and a faint glow cone from the lamps,
# two cheap draws. HIGH keeps the real light (and the cone).

const HEADLIGHT_FAKE_GROUP := &"headlight_fake"
static var _pool_mat: StandardMaterial3D
static var _beam_mat: StandardMaterial3D


## Builds the fake beam for a car model (hidden until the headlights are switched on).
static func headlight_beams(model: Node3D, car_size: Vector3) -> Node3D:
	var holder := Node3D.new()
	holder.name = "HeadlightFx"
	holder.add_to_group(HEADLIGHT_FAKE_GROUP)
	holder.visible = false
	model.add_child(holder)
	var lamp := Vector3(0, car_size.y * 0.45, -car_size.z * 0.5)
	for l in model.find_children("*", "SpotLight3D", true, false):
		if (l as Node).is_in_group(GraphicsSettings.HEADLIGHT_GROUP):
			lamp = _local_pos(model, l as Node3D)
			break
	var near := absf(lamp.z) + 0.6
	var length := 20.0
	var pool := MeshInstance3D.new()
	pool.name = "Pool"
	var quad := PlaneMesh.new()
	quad.size = Vector2(9.0, length)
	pool.mesh = quad
	pool.material_override = _pool_material()
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pool.position = Vector3(0, 0.07, -near - length * 0.5)
	holder.add_child(pool)
	var beam := MeshInstance3D.new()
	beam.name = "Beam"
	var cone := CylinderMesh.new()
	cone.top_radius = 0.35
	cone.bottom_radius = 3.2
	cone.height = 14.0
	cone.radial_segments = 10
	cone.rings = 1
	cone.cap_top = false
	cone.cap_bottom = false
	beam.mesh = cone
	beam.material_override = _beam_material()
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The cylinder's axis is +Y: lay it along -Z, narrow end at the lamps, dipping a little.
	beam.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(88.0)), lamp + Vector3(0, -0.25, -7.0))
	holder.add_child(beam)
	return holder


## Shows or hides the fake beam: the ground pool only on LOW (HIGH has the real light for that).
static func show_headlights(model: Node3D, on: bool) -> void:
	for n in model.find_children("HeadlightFx", "Node3D", false, false):
		update_headlight_fx(n as Node3D, on)


static func update_headlight_fx(holder: Node3D, on: bool) -> void:
	holder.set_meta("on", on)
	holder.visible = on
	var pool := holder.get_node_or_null("Pool") as Node3D
	if pool:
		pool.visible = not GraphicsSettings.high


static func _pool_material() -> StandardMaterial3D:
	if _pool_mat:
		return _pool_mat
	# Near the car the beam is narrow and bright, then it widens and fades out (v = 0 far, 1 near).
	var w := 48
	var h := 96
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var along := 1.0 - float(y) / (h - 1) # 0 near the car .. 1 far
		var half := 0.16 + 0.34 * along
		var fade := smoothstep(0.0, 0.12, along) * (1.0 - smoothstep(0.45, 1.0, along))
		for x in w:
			var across := absf(float(x) / (w - 1) - 0.5)
			var edge := 1.0 - smoothstep(half * 0.55, half, across)
			img.set_pixel(x, y, Color(1.0, 0.93, 0.78, edge * fade))
	_pool_mat = StandardMaterial3D.new()
	_pool_mat.albedo_texture = ImageTexture.create_from_image(img)
	_pool_mat.albedo_color = Color(1.0, 0.95, 0.85, 0.75)
	_pool_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_pool_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_pool_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_pool_mat.texture_repeat = false
	_pool_mat.disable_receive_shadows = true
	return _pool_mat


static func _beam_material() -> StandardMaterial3D:
	if _beam_mat:
		return _beam_mat
	var img := Image.create(4, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		var t := float(y) / 31.0 # cylinder v: 0 at the top (lamp) .. 1 at the wide end
		var a := (1.0 - t) * (1.0 - t) * smoothstep(0.0, 0.08, t)
		for x in 4:
			img.set_pixel(x, y, Color(1.0, 0.94, 0.8, a))
	_beam_mat = StandardMaterial3D.new()
	_beam_mat.albedo_texture = ImageTexture.create_from_image(img)
	_beam_mat.albedo_color = Color(1.0, 0.95, 0.85, 0.15)
	_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_beam_mat.cull_mode = BaseMaterial3D.CULL_BACK
	_beam_mat.texture_repeat = false
	return _beam_mat
