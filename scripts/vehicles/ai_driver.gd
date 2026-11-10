class_name AIDriver
extends RefCounted
## Enemy brain, tuned to the owner's play-test 1 (TM-style dogfights, no magnet):
##   CHASE     the target drives away or shows its side: follow with a gap (never glued to the
##             bumper) and shoot; no handbrake drifts around it.
##   FACE-OFF  the target turns to face us: hold the line and fight head-on from the front at about
##             STANDOFF meters (back off if it comes too close), instead of sliding round behind it.
##   RETREAT   only when badly hurt: break away (drifting allowed) and look for health.
## Also: dodges walls with feeler rays, backs out when stuck, takes ramps to reach high targets.
## Story rule (design 1.5): at most two AI cars go after the player at the same time.

const WORLD_MASK := 1
const MAX_ON_PLAYER := 2
const STANDOFF := 17.0 # head-on fights hold about this far
const CHASE_GAP := 15.0 # following distance behind a fleeing target
const FACING := deg_to_rad(40.0) # the target "faces us" when we are inside this cone of its nose
const RETREAT_AT := 0.35 # share of max health

var aggression := 1.0 # 0.5 easy .. 1.5 hard
var arena: Node3D # stage: ramps, wander area
var mode := "wander" # chase | faceoff | retreat | wander (tests and debugging read it)

var _retarget := 0.0
var _weapon_timer := 2.0
var _special_timer := 3.0
var _mash_timer := 0.0
var _hold := 0.0 # seconds left holding fire (charging the Napalm Cone)
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

	var plan := _plan(v)
	var goal: Vector3 = plan.goal
	var throttle: float = plan.throttle
	var to := goal - v.global_position
	to.y = 0.0
	var dist := to.length()
	var fwd := v.flat_forward()
	var angle := fwd.signed_angle_to(to.normalized(), Vector3.UP) if dist > 0.1 else 0.0
	# signed_angle_to around UP is positive to the left; steer is positive to the right.
	var steer := clampf(-angle * 2.0, -1.0, 1.0)
	if mode == "faceoff" and absf(angle) > 0.6:
		throttle = maxf(throttle, 0.55) # turn the nose back onto the target
	# Handbrake only to break away when hurt, or for a U-turn far from the fight. No drifting
	# circles around the target.
	var handbrake := absf(angle) > 1.3 and v.speed > 14.0 and (mode == "retreat" or (mode == "wander" and absf(angle) > 2.2))

	steer = clampf(steer + _avoid(v, fwd), -1.0, 1.0)
	if v.speed < -0.5:
		steer = -steer # backing up: the nose turns the other way

	# Stuck against something: back out, turning the other way.
	if _reverse > 0.0:
		_reverse -= delta
		throttle = -1.0
		steer = _reverse_steer
		handbrake = false
	elif absf(v.speed) < 2.0 and throttle > 0.3:
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
	# Turbo never refills by itself: save it for escaping or closing a long gap.
	var far := dist > 70.0 and mode == "chase"
	v.in_turbo = (mode == "retreat" or far or not _ramp_goal.is_empty()) and absf(angle) < 0.25 and v.turbo > 25.0
	_shoot(v, delta)


## Where to drive and how hard, from the target's health, distance and which way it faces.
func _plan(v: Vehicle) -> Dictionary:
	var t := v.target
	var has_t := is_instance_valid(t) and not t.is_dead
	if v.health < v.max_health * RETREAT_AT:
		var pickup := _nearest_health(v)
		if pickup:
			mode = "retreat"
			return {"goal": _via_ramp(v, pickup.global_position), "throttle": 1.0}
		if has_t and v.global_position.distance_to(t.global_position) < 40.0:
			mode = "retreat" # nothing to heal with: get some room
			var away := (v.global_position - t.global_position)
			away.y = 0.0
			var flee := v.global_position + away.normalized() * 40.0
			var half: float = arena.wander_half if arena else 60.0
			flee.x = clampf(flee.x, -half, half)
			flee.z = clampf(flee.z, -half, half)
			return {"goal": flee, "throttle": 1.0}
	if has_t:
		var to := t.global_position - v.global_position
		var d := Vector2(to.x, to.z).length()
		var level := absf(to.y) < 3.0
		var back := -to
		back.y = 0.0
		var faces_us := t.flat_forward().angle_to(back.normalized()) < FACING
		if faces_us and level and d < 45.0:
			mode = "faceoff"
			_ramp_goal = {}
			return {"goal": t.global_position, "throttle": clampf((d - STANDOFF) / 12.0, -0.7, 0.85)}
		mode = "chase"
		var goal := _via_ramp(v, t.global_position + t.velocity * 0.25)
		var throttle := 1.0
		if level and d < CHASE_GAP + 8.0:
			# Match its speed and keep a gap instead of riding its bumper.
			var match_speed := t.velocity.length() / float(v.stats.get("max_speed", 25.0))
			throttle = clampf(match_speed * 0.95 + (d - CHASE_GAP) * 0.06, -0.4, 1.0)
		return {"goal": goal, "throttle": throttle}
	mode = "wander"
	var half: float = arena.wander_half if arena else 60.0
	if _wander == Vector3.ZERO or v.global_position.distance_to(_wander) < 8.0:
		_ramp_goal = {}
		_wander = Vector3(randf_range(-half, half), 0, randf_range(-half, half))
		if arena and arena.has_method("ground"):
			_wander = arena.ground(_wander.x, _wander.z) # up on a deck or plateau: _via_ramp finds the way
	return {"goal": _via_ramp(v, _wander), "throttle": 1.0}


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
	# Charging the Napalm Cone: keep the button down, let go when it is full.
	if _hold > 0.0:
		_hold -= delta
		v.in_fire_weapon = _hold > 0.0
		return
	v.in_fire_weapon = false
	# A live taser link, chain bomb, napalm can or remote bomb: mash, drop or blow it.
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
	if mode == "retreat" and dist > 30.0:
		return # busy getting away
	if _special_timer <= 0.0 and v.ammo.get(v.special_id, 0) > 0 and _special_makes_sense(v, dist, angle):
		_special_timer = randf_range(3.0, 6.0) / aggression
		v.selected = 0
		v.want_fire_weapon = true
		if v.special_id == "napalm_cone" and angle < 0.12 and dist > 18.0 and dist < 50.0 and randf() < 0.35:
			_hold = Vehicle.charge_full("napalm_cone") + 0.1 # charged shot: straight, double damage
			v.in_fire_weapon = true
		return
	if _weapon_timer <= 0.0:
		var options: Array[int] = []
		for i in v.weapon_order.size():
			var id := v.weapon_order[i]
			if id != v.special_id and v.ammo.get(id, 0) > 0 and _weapon_makes_sense(id, dist, angle):
				options.append(i)
		if not options.is_empty():
			_weapon_timer = randf_range(1.8, 4.5) / aggression
			v.selected = options.pick_random()
			v.want_fire_weapon = true
	if dist < 30.0 and v.energy >= 80.0 and randf() < 0.004 * aggression:
		v.want_freeze = true


func _weapon_makes_sense(id: String, dist: float, angle: float) -> bool:
	match id:
		"power":
			return dist < 60.0 and angle < 0.15
		"napalm":
			return dist > 12.0 and dist < 40.0 and angle < 0.3
		"remote":
			return dist < 26.0 and angle < 0.35
		"zoomy":
			return dist < 70.0 and angle < 0.5
		"sat":
			return dist < 70.0 and angle < 0.9
	return dist < 85.0 and angle < 0.6


func _special_makes_sense(v: Vehicle, dist: float, angle: float) -> bool:
	match v.special_id:
		"omni_taser":
			return dist < 20.0 and _clear_shot(v, v.target)
		"chain_bomb":
			return dist < 22.0 and angle < 0.2
		"napalm_cone":
			return dist < 65.0 and angle < 0.5
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
	elif live is Projectile:
		var p := live as Projectile
		var reach := 4.0 if p.def.get("kind", "") == "gas" else 4.5
		for o in Specials.cars_near(v.get_parent(), p.global_position, 60.0, v):
			var flat := Vector2(o.global_position.x - p.global_position.x, o.global_position.z - p.global_position.z)
			if flat.length() < reach and (p.def.get("kind", "") == "gas" or p.is_resting()):
				v.want_fire_weapon = true # drop the can on it / blow the bomb
				return


func _clear_shot(v: Vehicle, t: Vehicle) -> bool:
	var q := PhysicsRayQueryParameters3D.create(v.global_position + Vector3.UP * 1.2, t.global_position + Vector3.UP * 1.2, WORLD_MASK)
	return v.get_world_3d().direct_space_state.intersect_ray(q).is_empty()
