class_name AIDriver
extends RefCounted
## Enemy brain: hunts the closest car (prefers the player), dodges walls with
## feeler rays, backs out when stuck, grabs health when hurt, and shoots when lined up.

const WORLD_MASK := 1

var aggression := 1.0 # 0.5 easy .. 1.5 hard

var _retarget := 0.0
var _weapon_timer := 2.0
var _stuck := 0.0
var _reverse := 0.0
var _reverse_steer := 1.0
var _wander := Vector3.ZERO


func drive(v: Vehicle, delta: float) -> void:
	_retarget -= delta
	_weapon_timer -= delta
	if _retarget <= 0.0:
		_retarget = 0.6
		v.target = _choose_target(v)

	var goal := _choose_goal(v)
	var to := goal - v.global_position
	to.y = 0.0
	var dist := to.length()
	var fwd := -v.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var angle := fwd.signed_angle_to(to.normalized(), Vector3.UP) if dist > 0.1 else 0.0
	# signed_angle_to around UP is positive to the left; steer is positive to the right.
	var steer := clampf(-angle * 2.0, -1.0, 1.0)
	var throttle := 1.0
	var handbrake := absf(angle) > 1.3 and v.speed > 14.0

	if is_instance_valid(v.target) and dist < 12.0 and absf(angle) < 0.5:
		throttle = 0.5

	steer = clampf(steer + _avoid(v, fwd), -1.0, 1.0)

	# Stuck against something: back out, turning the other way.
	if _reverse > 0.0:
		_reverse -= delta
		throttle = -1.0
		steer = _reverse_steer
		handbrake = false
	elif absf(v.speed) < 2.0 and throttle > 0.0:
		_stuck += delta
		if _stuck > 1.0:
			_stuck = 0.0
			_reverse = 1.1
			_reverse_steer = -signf(steer) if absf(steer) > 0.1 else (1.0 if randf() < 0.5 else -1.0)
	else:
		_stuck = 0.0

	v.in_throttle = throttle
	v.in_steer = steer
	v.in_handbrake = handbrake
	v.in_turbo = dist > 45.0 and absf(angle) < 0.25 and v.turbo > 40.0
	_shoot(v)


func _choose_target(v: Vehicle) -> Vehicle:
	var best: Vehicle = null
	var best_score := INF
	for node in v.get_tree().get_nodes_in_group("vehicles"):
		var o := node as Vehicle
		if o == v or o.is_dead:
			continue
		var score := v.global_position.distance_to(o.global_position)
		if o.is_player:
			score *= 0.6
		if o == v.last_attacker:
			score *= 0.7
		if score < best_score:
			best_score = score
			best = o
	return best


func _choose_goal(v: Vehicle) -> Vector3:
	if v.health < v.max_health * 0.35:
		var pickup := _nearest_health(v)
		if pickup:
			return pickup.global_position
	if is_instance_valid(v.target) and not v.target.is_dead:
		# Lead the target a little.
		return v.target.global_position + v.target.velocity * 0.4
	if _wander == Vector3.ZERO or v.global_position.distance_to(_wander) < 8.0:
		_wander = Vector3(randf_range(-60, 60), 0, randf_range(-60, 60))
	return _wander


func _nearest_health(v: Vehicle) -> Pickup:
	var best: Pickup = null
	var best_d := INF
	for node in v.get_tree().get_nodes_in_group("pickups"):
		var p := node as Pickup
		if not p.active or p.kind != "health":
			continue
		var d := v.global_position.distance_to(p.global_position)
		if d < best_d:
			best_d = d
			best = p
	return best


## Three feeler rays; returns a steering correction away from walls.
func _avoid(v: Vehicle, fwd: Vector3) -> float:
	var space := v.get_world_3d().direct_space_state
	var origin := v.global_position + Vector3.UP * 1.0
	var length := 7.0 + absf(v.speed) * 0.5
	var center := _ray(space, origin, fwd * length)
	var left := _ray(space, origin, fwd.rotated(Vector3.UP, 0.6) * length * 0.75)
	var right := _ray(space, origin, fwd.rotated(Vector3.UP, -0.6) * length * 0.75)
	var correction := 0.0
	if left < 1.0:
		correction += (1.0 - left) * 1.2
	if right < 1.0:
		correction -= (1.0 - right) * 1.2
	if center < 1.0:
		# Turn toward the more open side (negative steer = left).
		correction += (1.0 - center) * (-1.5 if left > right else 1.5)
	return correction


## Fraction (0..1) of the ray that is clear.
func _ray(space: PhysicsDirectSpaceState3D, origin: Vector3, vec: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(origin, origin + vec, WORLD_MASK)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return 1.0
	return origin.distance_to(hit.position) / vec.length()


func _shoot(v: Vehicle) -> void:
	v.in_fire_guns = false
	var t := v.target
	if not is_instance_valid(t) or t.is_dead:
		return
	var to := t.global_position - v.global_position
	var dist := to.length()
	var fwd := -v.global_transform.basis.z
	var angle := fwd.angle_to(to.normalized())
	if dist < 75.0 and angle < 0.22 and _clear_shot(v, t):
		v.in_fire_guns = true
	if _weapon_timer <= 0.0 and dist < 85.0 and angle < 0.6:
		_weapon_timer = randf_range(1.8, 4.5) / aggression
		var options: Array[int] = []
		for i in v.weapon_order.size():
			if v.ammo.get(v.weapon_order[i], 0) > 0:
				options.append(i)
		if not options.is_empty():
			v.selected = options.pick_random()
			v.want_fire_weapon = true
	if dist < 30.0 and v.energy >= 80.0 and randf() < 0.004 * aggression:
		v.want_freeze = true


func _clear_shot(v: Vehicle, t: Vehicle) -> bool:
	var q := PhysicsRayQueryParameters3D.create(v.global_position + Vector3.UP * 1.2, t.global_position + Vector3.UP * 1.2, WORLD_MASK)
	return v.get_world_3d().direct_space_state.intersect_ray(q).is_empty()
