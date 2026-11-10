class_name AIDriver
extends RefCounted
## Enemy brain: hunts a target, dodges walls with feeler rays, backs out when stuck, grabs health
## when hurt, takes the ramps when its target is up high, and shoots when lined up.
## Story rule (design 1.5): at most two AI cars go after the player at the same time.

const WORLD_MASK := 1
const MAX_ON_PLAYER := 2

var aggression := 1.0 # 0.5 easy .. 1.5 hard
var arena: Node3D # stage: ramps, wander area

var _retarget := 0.0
var _weapon_timer := 2.0
var _special_timer := 3.0
var _mash_timer := 0.0
var _stuck := 0.0
var _reverse := 0.0
var _reverse_steer := 1.0
var _wander := Vector3.ZERO
var _ramp_goal: Dictionary = {}


func drive(v: Vehicle, delta: float) -> void:
	_retarget -= delta
	_weapon_timer -= delta
	_special_timer -= delta
	if _retarget <= 0.0:
		_retarget = 0.6
		v.target = _choose_target(v)

	var goal := _choose_goal(v)
	var to := goal - v.global_position
	to.y = 0.0
	var dist := to.length()
	var fwd := v.flat_forward()
	var angle := fwd.signed_angle_to(to.normalized(), Vector3.UP) if dist > 0.1 else 0.0
	# signed_angle_to around UP is positive to the left; steer is positive to the right.
	var steer := clampf(-angle * 2.0, -1.0, 1.0)
	var throttle := 1.0
	var handbrake := absf(angle) > 1.3 and v.speed > 14.0

	if is_instance_valid(v.target) and _ramp_goal.is_empty() and dist < 12.0 and absf(angle) < 0.5:
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
		if _stuck > 1.2:
			_stuck = 0.0
			_reverse = 1.0
			_reverse_steer = -signf(steer) if absf(steer) > 0.1 else (1.0 if randf() < 0.5 else -1.0)
	else:
		_stuck = 0.0

	v.in_throttle = throttle
	v.in_steer = steer
	v.in_handbrake = handbrake
	v.in_turbo = (dist > 45.0 or not _ramp_goal.is_empty()) and absf(angle) < 0.25 and v.turbo > 40.0
	_shoot(v, delta)


func _choose_target(v: Vehicle) -> Vehicle:
	var on_player := 0
	for node in v.get_tree().get_nodes_in_group("vehicles"):
		var o := node as Vehicle
		if o != v and not o.is_player and not o.is_dead and is_instance_valid(o.target) and o.target.is_player:
			on_player += 1
	var best: Vehicle = null
	var best_score := INF
	for node in v.get_tree().get_nodes_in_group("vehicles"):
		var o := node as Vehicle
		if o == v or o.is_dead:
			continue
		var score := v.global_position.distance_to(o.global_position)
		if o.is_player:
			score *= 0.6 if on_player < MAX_ON_PLAYER or v.target == o else 3.0
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
			return _via_ramp(v, pickup.global_position)
	if is_instance_valid(v.target) and not v.target.is_dead:
		# Lead the target a little.
		return _via_ramp(v, v.target.global_position + v.target.velocity * 0.4)
	var half: float = arena.wander_half if arena else 60.0
	if _wander == Vector3.ZERO or v.global_position.distance_to(_wander) < 8.0:
		_ramp_goal = {}
		_wander = Vector3(randf_range(-half, half), 0, randf_range(-half, half))
		if arena and arena.has_method("ground"):
			_wander = arena.ground(_wander.x, _wander.z) # up on a deck or plateau: _via_ramp finds the way
	return _via_ramp(v, _wander)


## Something up on a roof or deck: drive to the foot of the nearest ramp, then up it.
func _via_ramp(v: Vehicle, goal: Vector3) -> Vector3:
	if arena == null or arena.ramps.is_empty() or goal.y < v.global_position.y + 3.5:
		_ramp_goal = {}
		return goal
	if _ramp_goal.is_empty():
		var best_d := INF
		for r: Dictionary in arena.ramps:
			if absf(r.top.y - goal.y) > 2.0:
				continue
			var d: float = v.global_position.distance_to(r.foot) + (r.top as Vector3).distance_to(goal)
			if d < best_d:
				best_d = d
				_ramp_goal = r.duplicate()
				_ramp_goal["climbing"] = false
		if _ramp_goal.is_empty():
			return goal
	var foot: Vector3 = _ramp_goal.foot
	if not _ramp_goal.climbing and Vector2(v.global_position.x - foot.x, v.global_position.z - foot.z).length() < 8.0:
		_ramp_goal.climbing = true
	if not _ramp_goal.climbing and foot.y > v.global_position.y + 3.5:
		return _lower_ramp(v, foot) # that ramp starts up on a plateau: get up there first
	return _ramp_goal.top if _ramp_goal.climbing else foot


## Route to a ramp that climbs to `level` (its top at that height): foot first, then up.
func _lower_ramp(v: Vehicle, level: Vector3) -> Vector3:
	var best: Dictionary = {}
	var best_d := INF
	for r: Dictionary in arena.ramps:
		if absf(r.top.y - level.y) > 2.0 or r.foot.y > v.global_position.y + 2.0:
			continue
		var d: float = v.global_position.distance_to(r.foot) + (r.top as Vector3).distance_to(level)
		if d < best_d:
			best_d = d
			best = r
	if best.is_empty():
		return level
	var on_slope: bool = v.global_position.y > best.foot.y + 0.8
	var near_foot := Vector2(v.global_position.x - best.foot.x, v.global_position.z - best.foot.z).length() < 8.0
	return best.top if (on_slope or near_foot) else best.foot


func _nearest_health(v: Vehicle) -> Pickup:
	var best: Pickup = null
	var best_d := INF
	for node in v.get_tree().get_nodes_in_group("pickups"):
		var p := node as Pickup
		if not p.active or not p.is_health():
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


func _shoot(v: Vehicle, delta: float) -> void:
	v.in_fire_guns = false
	# A live taser link or chain bomb: mash or pick the moment to blow it.
	if v.has_live_special():
		_use_live_special(v, delta)
		return
	var t := v.target
	if not is_instance_valid(t) or t.is_dead:
		return
	var to := t.global_position - v.global_position
	var dist := to.length()
	var angle := v.flat_forward().angle_to(Vector3(to.x, 0, to.z).normalized())
	if dist < 75.0 and angle < 0.22 and _clear_shot(v, t):
		v.in_fire_guns = true
	if _special_timer <= 0.0 and v.ammo.get(v.special_id, 0) > 0 and _special_makes_sense(v, dist, angle):
		_special_timer = randf_range(3.0, 6.0) / aggression
		v.selected = 0
		v.want_fire_weapon = true
		return
	if _weapon_timer <= 0.0 and dist < 85.0 and angle < 0.6:
		_weapon_timer = randf_range(1.8, 4.5) / aggression
		var options: Array[int] = []
		for i in v.weapon_order.size():
			var id := v.weapon_order[i]
			if id != v.special_id and v.ammo.get(id, 0) > 0:
				options.append(i)
		if not options.is_empty():
			v.selected = options.pick_random()
			v.want_fire_weapon = true
	if dist < 30.0 and v.energy >= 80.0 and randf() < 0.004 * aggression:
		v.want_freeze = true


func _special_makes_sense(v: Vehicle, dist: float, angle: float) -> bool:
	match v.special_id:
		"omni_taser":
			return dist < 20.0 and _clear_shot(v, v.target)
		"chain_bomb":
			return dist < 22.0 and angle < 0.2
		"napalm_cone":
			return dist > 15.0 and dist < 65.0
		"reaper_skull":
			return dist < 80.0 and angle < 0.12 and _clear_shot(v, v.target)
		"ghost_missile":
			return dist < 70.0
	return dist < 60.0 and angle < 0.3


func _use_live_special(v: Vehicle, delta: float) -> void:
	var live := v.live_special()
	if live is TaserLink:
		_mash_timer -= delta
		if _mash_timer <= 0.0:
			_mash_timer = randf_range(0.12, 0.25) / aggression
			v.want_fire_weapon = true
	elif live is ChainBomb:
		var bomb := live as ChainBomb
		if bomb.state == ChainBomb.State.STUCK:
			v.want_fire_weapon = true
			return
		for o in Specials.cars_near(v.get_parent(), bomb.global_position, 4.5, v):
			v.want_fire_weapon = true
			return


func _clear_shot(v: Vehicle, t: Vehicle) -> bool:
	var q := PhysicsRayQueryParameters3D.create(v.global_position + Vector3.UP * 1.2, t.global_position + Vector3.UP * 1.2, WORLD_MASK)
	return v.get_world_3d().direct_space_state.intersect_ray(q).is_empty()
