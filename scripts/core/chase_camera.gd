class_name ChaseCamera
extends Camera3D
## Third-person chase camera: trails the car, pulls back with speed, avoids walls,
## shakes on hits, looks back on demand and orbits the wreck when the player dies.
## Modes (owner, play-test 1; R3 / V): near chase, far chase, and in the car at the driver's eye
## (the driver's hands come later with our own driver model).

const WORLD_MASK := 1

var target: Vehicle
var distance := 9.5
var height := 3.4
var smoothing := 7.0

const MODES := ["near", "far", "car"]
static var mode := "near" # kept across restarts

var _shake := 0.0
var _orbit := 0.0
var _looking_back := false
var rear_view := false # R3 (round 7): toggled, looks back until pressed again


## Follow a car, using its roster camera settings if it has any.
func follow(v: Vehicle) -> void:
	target = v
	rear_view = false
	var c: Array = v.stats.get("camera", [4.2, 10.0])
	height = c[0]
	distance = c[1]
	snap()


func add_shake(amount: float) -> void:
	_shake = minf(1.0, _shake + amount)


func snap() -> void:
	if target:
		global_position = _desired_position(_target_forward())
		look_at(target.global_position + _target_forward() * 4.0 + Vector3.UP * height * 0.45)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(target):
		return
	if target.is_dead:
		_orbit_wreck(delta)
		return

	if Input.is_action_just_pressed("camera_mode"):
		mode = MODES[(MODES.find(mode) + 1) % MODES.size()]
		target.notice.emit(target, "CAMERA: " + {"near": "NEAR", "far": "FAR", "car": "IN THE CAR"}[mode])
		snap()
	if Input.is_action_just_pressed("rear_view"):
		rear_view = not rear_view
	if mode == "car":
		_in_car(delta)
		return
	near = 0.05
	var fwd := _target_forward()
	var back := looking_back()
	if back:
		fwd = -fwd
	var desired := _avoid_walls(_desired_position(fwd))
	if back != _looking_back:
		_looking_back = back
		global_position = desired
	else:
		# Owner, round 11: turbo must not throw the camera far back. While boosting it follows
		# tighter, so the sudden shove doesn't open a gap behind the car.
		var follow := smoothing * (1.8 if target._boosting else 1.0)
		global_position = global_position.lerp(desired, 1.0 - exp(-follow * delta))

	var look := target.global_position + fwd * 4.0 + Vector3.UP * height * 0.45
	look_at(look)
	fov = lerpf(fov, 70.0 + clampf(_cam_speed() - 20.0, 0.0, 25.0) * 0.6, 4.0 * delta)
	_apply_shake(delta)


## At the driver's eye, turning and tilting with the body; look back turns the view round.
func _in_car(delta: float) -> void:
	near = 0.05
	var size: Vector3 = target.stats.get("size", Vector3(2.2, 1.8, 5.0))
	var eye: Vector3 = target.model.get_meta("driver_eye", Vector3(-size.x * 0.2, size.y * 0.74, -size.z * 0.18))
	var xf := target.global_transform
	global_position = xf * eye
	var fwd := -xf.basis.z
	if looking_back():
		fwd = -fwd
	look_at(global_position + fwd * 10.0, xf.basis.y)
	fov = lerpf(fov, 78.0 + clampf(absf(target.speed) - 20.0, 0.0, 25.0) * 0.5, 4.0 * delta)
	_apply_shake(delta)


## B held on the keyboard, or the pad's R3 toggle.
func looking_back() -> bool:
	return rear_view or Input.is_action_pressed("look_back")


func _target_forward() -> Vector3:
	var f := -target.global_transform.basis.z
	f.y = 0.0
	return f.normalized()


## Speed as the camera feels it: up to the car's top speed in full, anything turbo adds on top
## only a quarter (owner, round 11: "the camera change after turbo minimum, but not zero").
func _cam_speed() -> float:
	var s := absf(target.speed)
	var top: float = float(target.stats.get("max_speed", 40.0))
	return s if s <= top else top + (s - top) * 0.25


func _desired_position(fwd: Vector3) -> Vector3:
	var pull := clampf(_cam_speed() * 0.06, 0.0, 3.0)
	var far := 1.6 if mode == "far" else 1.0
	return target.global_position - fwd * (distance * far + pull) + Vector3.UP * height * (1.4 if mode == "far" else 1.0)


func _avoid_walls(desired: Vector3) -> Vector3:
	var from := target.global_position + Vector3.UP * 2.0
	var q := PhysicsRayQueryParameters3D.create(from, desired, WORLD_MASK)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return desired
	return hit.position + (from - hit.position).normalized() * 0.6


func _orbit_wreck(delta: float) -> void:
	_orbit += delta * 0.35
	var center := target.global_position
	var pos := center + Vector3(sin(_orbit) * 12.0, 6.0, cos(_orbit) * 12.0)
	global_position = global_position.lerp(pos, 1.0 - exp(-2.0 * delta))
	look_at(center + Vector3.UP)
	_apply_shake(delta)


func _apply_shake(delta: float) -> void:
	if _shake <= 0.0:
		return
	_shake = maxf(0.0, _shake - delta * 2.5)
	var s := _shake * _shake * 0.5
	h_offset = randf_range(-s, s)
	v_offset = randf_range(-s, s)
	if _shake == 0.0:
		h_offset = 0.0
		v_offset = 0.0
