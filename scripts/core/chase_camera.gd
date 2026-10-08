class_name ChaseCamera
extends Camera3D
## Third-person chase camera: trails the car, pulls back with speed, avoids walls,
## shakes on hits, looks back on demand and orbits the wreck when the player dies.

const WORLD_MASK := 1

var target: Vehicle
var distance := 9.5
var height := 3.4
var smoothing := 7.0

var _shake := 0.0
var _orbit := 0.0
var _looking_back := false


## Follow a car, using its roster camera settings if it has any.
func follow(v: Vehicle) -> void:
	target = v
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

	var fwd := _target_forward()
	var back := Input.is_action_pressed("look_back")
	if back:
		fwd = -fwd
	var desired := _avoid_walls(_desired_position(fwd))
	if back != _looking_back:
		_looking_back = back
		global_position = desired
	else:
		global_position = global_position.lerp(desired, 1.0 - exp(-smoothing * delta))

	var look := target.global_position + fwd * 4.0 + Vector3.UP * height * 0.45
	look_at(look)
	var spd := absf(target.speed)
	fov = lerpf(fov, 70.0 + clampf(spd - 20.0, 0.0, 25.0) * 0.6, 4.0 * delta)
	_apply_shake(delta)


func _target_forward() -> Vector3:
	var f := -target.global_transform.basis.z
	f.y = 0.0
	return f.normalized()


func _desired_position(fwd: Vector3) -> Vector3:
	var pull := clampf(absf(target.speed) * 0.06, 0.0, 3.0)
	return target.global_position - fwd * (distance + pull) + Vector3.UP * height


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
