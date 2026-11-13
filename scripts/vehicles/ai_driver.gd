class_name AIDriver
extends RefCounted
## Enemy brain, tuned to the owner's play-tests (aimed at a 7/10 fight, TM style):
##   HUNT     far away: drive at the target, hunt it with long-range missiles; grab weapons and
##            turbo on the way when low on them.
##   CHASE    the target runs: follow it with turbo, missiles, and the special from behind.
##   ATTACK   attack runs: come at the target from the front, aiming beside it on a side picked at
##            random each run (sometimes switched mid-run as a feint, never in answer to the
##            player's steering), swing round toward its back; keep driving past, then drift round
##            and come again. The player's counter is to turn into it or ram it. No circling.
##   RETREAT  only when badly hurt: break away (drifting) and look for health.
## Also: dodges walls with feeler rays, backs out when stuck, takes ramps to reach high targets.
## Story rule (design 1.5): at most two AI cars go after the player at the same time.

const WORLD_MASK := 1
const MAX_ON_PLAYER := 2
const RETREAT_AT := 0.3 # share of max health
const HUNT_RANGE := 55.0 # attack runs start inside this distance
const SPECIAL_RANGE := 8.0 # close-range specials (Outlaw's taser) only this close (owner)

var aggression := 1.2 # 0.5 easy .. 1.5 hard; 1.2 = the owner's 7/10
var arena: Node3D # stage: ramps, wander area
var mode := "wander" # hunt | chase | attack | retreat | detour | wander (tests and debugging read it)
var phase := "approach" # attack run: approach | pass | turn

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
var _escape := 0.0 # after backing out of a wall: drive to a point along the wall for a moment
var _escape_goal := Vector3.ZERO
var _bad_ramps := {} # ramp foot (rounded) -> seconds to avoid it after failing to climb it twice
var _ramp_fails := 0
var _no_jump := 0.0 # a jump-up attempt failed: use ramps for a while
var _side := 1.0 # attack run: pass on the target's right (1) or left (-1)
var _dodge_t := 0.0 # drifting out of a homing missile's way
var _dodge_steer := 1.0
var _dodge_scan := 0.0
var _feinted := false
var _phase_t := 0.0
var _drift := false
var _plan_jump := false
var drifts := 0 # handbrake turns started (tests)
var _energy_think := 1.0 # seconds to the next energy-move decision


func drive(v: Vehicle, delta: float) -> void:
	_retarget -= delta
	_weapon_timer -= delta
	_special_timer -= delta
	if _retarget <= 0.0:
		_retarget = 0.6
		v.target = _choose_target(v)
	_energy_moves(v, delta)

	if v.flipped: # on its roof or side: gas + steer rolls it back over (round 5)
		v.in_throttle = 1.0
		v.in_handbrake = false
		v.in_steer = 1.0
		v.in_turbo = false
		v.in_fire_guns = false
		return
	_drift = false
	_no_jump -= delta
	for key in _bad_ramps.keys():
		_bad_ramps[key] -= delta
		if _bad_ramps[key] <= 0.0:
			_bad_ramps.erase(key)
	var plan := _plan(v, delta)
	var goal: Vector3 = plan.goal
	var throttle: float = plan.throttle
	if _escape > 0.0: # just backed out of a wall or a corner: go round it, not straight back in
		_escape -= delta
		goal = _escape_goal
		throttle = 1.0
	var to := goal - v.global_position
	to.y = 0.0
	var dist := to.length()
	var fwd := v.flat_forward()
	var angle := fwd.signed_angle_to(to.normalized(), Vector3.UP) if dist > 0.1 else 0.0
	# signed_angle_to around UP is positive to the left; steer is positive to the right.
	var steer := clampf(-angle * 2.2, -1.0, 1.0)
	# Sharp turns at speed: lift off and drift round instead of a wide arc (a wide arc at full speed
	# runs off the battleground edge or past a ramp foot). Drift turns are part of attack runs too.
	if absf(angle) > 1.0 and v.speed > 15.0 and phase != "pass":
		throttle = minf(throttle, 0.35)
	var handbrake := (_drift and absf(angle) > 0.8 and v.speed > 10.0) or (absf(angle) > 1.4 and v.speed > 12.0)
	if handbrake and not v.in_handbrake:
		drifts += 1

	steer = clampf(steer + _avoid(v, fwd), -1.0, 1.0)
	# A homing missile coming in: break hard to one side with a drift (not every time: beatable).
	_dodge_scan -= delta
	if _dodge_scan <= 0.0 and _dodge_t <= 0.0:
		_dodge_scan = 0.15
		_watch_missiles(v)
	if _dodge_t > 0.0:
		_dodge_t -= delta
		steer = _dodge_steer
		handbrake = v.speed > 10.0
		throttle = 1.0

	# Stuck against something (a corner, a wall, a car): back out, turning the other way.
	if _reverse > 0.0:
		_reverse -= delta
		throttle = -1.0
		steer = _reverse_steer
		handbrake = false
	elif Vector2(v.velocity.x, v.velocity.z).length() < 2.0 and throttle > 0.3:
		_stuck += delta # pushing against a wall, a corner or a car without moving
		if _stuck > 0.7:
			_stuck = 0.0
			_reverse = 1.3
			_reverse_steer = -signf(steer) if absf(steer) > 0.1 else (1.0 if randf() < 0.5 else -1.0)
			_set_escape(v, goal)
			if not _ramp_goal.is_empty() and _ramp_goal.get("climbing", false):
				_ramp_failed()
			if _plan_jump:
				_no_jump = 12.0 # couldn't jump up there from here: take a ramp for a while
	else:
		_stuck = 0.0

	# Coming in to a ramp not yet lined up: ease off, and brake when much too fast (round 7: cars are
	# 1.4x faster and overshot the line again and again).
	if not _ramp_goal.is_empty() and not _ramp_goal.get("climbing", false) and _reverse <= 0.0:
		var to_foot := Vector2(v.global_position.x - (_ramp_goal.foot as Vector3).x, v.global_position.z - (_ramp_goal.foot as Vector3).z).length()
		if to_foot < 40.0 and v.speed > 24.0:
			throttle = minf(throttle, -0.6)
			handbrake = false
		elif to_foot < 25.0 and v.speed > 16.0:
			throttle = minf(throttle, 0.25)
	elif not _ramp_goal.is_empty() and _ramp_goal.get("climbing", false) and v.speed > 16.0:
		throttle = minf(throttle, 0.35) # on the ramp: steady, or the real body slides off its side
	v.in_throttle = throttle
	v.in_steer = steer
	v.in_handbrake = handbrake
	_try_jump_up(v)
	# Turbo never refills by itself: spend it on chasing a runner, closing a long gap or escaping.
	var want_turbo: bool = plan.get("turbo", false) and _ramp_goal.is_empty() # no turbo onto a ramp: too fast to line up
	v.in_turbo = want_turbo and absf(angle) < 0.3 and v.turbo > 10.0
	_shoot(v, delta)


func _watch_missiles(v: Vehicle) -> void:
	for node in v.get_tree().get_nodes_in_group("projectiles"):
		var p := node as Projectile
		if p == null or p.target != v or float(p.def.get("homing", 0.0)) <= 0.0:
			continue
		var to := v.global_position - p.global_position
		if to.length() > 28.0 or p.direction.dot(to.normalized()) < 0.7:
			continue
		var big := float(p.def.get("damage", 0.0)) >= 30.0
		if big and v.energy >= Vehicle.SHIELD_COST and v.shield_time <= 0.0 and randf() < 0.5:
			v.want_move = "shield" # a big one coming: shield up (energy move)
			_dodge_scan = 1.0
		elif randf() < 0.55 * aggression: # 1.2 aggression: about two missiles in three get a dodge
			_dodge_t = 0.55
			var side := p.direction.cross(Vector3.UP)
			_dodge_steer = 1.0 if side.dot(v.flat_forward().cross(Vector3.UP)) > 0.0 else -1.0
		else:
			_dodge_scan = 1.0 # this one gets through: don't try again at once
		return


## Energy moves for the AI (play-test 1 list): a chaser behind gets a mine or the rear attack, an
## enemy gone invisible nearby gets the headlights, and they go off again when nobody hides.
func _energy_moves(v: Vehicle, delta: float) -> void:
	_energy_think -= delta
	if _energy_think > 0.0:
		return
	_energy_think = randf_range(0.8, 1.6)
	var hidden_near := false
	for node in v.get_tree().get_nodes_in_group("vehicles"):
		var o := node as Vehicle
		if o != v and not o.is_dead and o.invisible_time > 0.0 and o.global_position.distance_to(v.global_position) < 40.0:
			hidden_near = true
	if hidden_near != v.headlights_on:
		v.toggle_headlights()
	var t := v.target
	if not is_instance_valid(t) or t.is_dead:
		return
	var to := t.global_position - v.global_position
	var behind := v.flat_forward().dot(to.normalized()) < -0.6
	# Only while driving on forward: never into its own mine while backing out of a corner.
	if behind and to.length() < 30.0 and v.speed > 10.0 and _reverse <= 0.0 and randf() < 0.35 * aggression:
		if v.energy >= Vehicle.REAR_ATTACK_COST + 25.0 and randf() < 0.5:
			v.want_move = "rear_attack"
		elif v.energy >= Vehicle.MINE_COST + 25.0:
			v.want_move = "mines"


## Where to drive, how hard, and whether to use turbo.
func _plan(v: Vehicle, delta: float) -> Dictionary:
	var t := v.target
	var has_t := is_instance_valid(t) and not t.is_dead
	if v.health < v.max_health * RETREAT_AT:
		var pickup := _nearest_pickup(v, "health")
		if pickup:
			mode = "retreat"
			_drift = true
			return {"goal": _via_ramp(v, pickup.global_position), "throttle": 1.0, "turbo": true}
		if has_t and v.global_position.distance_to(t.global_position) < 40.0:
			mode = "retreat" # nothing to heal with: get some room
			var away := (v.global_position - t.global_position)
			away.y = 0.0
			var flee := v.global_position + away.normalized() * 40.0
			var half: float = arena.wander_half if arena else 60.0
			flee.x = clampf(flee.x, -half, half)
			flee.z = clampf(flee.z, -half, half)
			return {"goal": flee, "throttle": 1.0, "turbo": true}
	if not has_t:
		return _wander_plan(v)
	var to := t.global_position - v.global_position
	var d := Vector2(to.x, to.z).length()
	var flat_to := Vector3(to.x, 0, to.z).normalized()
	var t_vel := Vector3(t.velocity.x, 0, t.velocity.z)
	var running := t_vel.length() > 9.0 and t_vel.normalized().dot(flat_to) > 0.4 # driving away from us
	_plan_jump = false
	if to.y > 2.5 and to.y < 5.6 and d < 70.0 and _no_jump <= 0.0 and v.energy >= Vehicle.JUMP_COST and _runway(v, t):
		# It is up on the battleground and close: drive straight at it and jump the wall (the
		# owner's "unorthodox entrance"). If that fails we fall back to the ramps for a while.
		mode = "chase"
		_plan_jump = true
		_ramp_goal = {}
		return {"goal": t.global_position, "throttle": 1.0, "turbo": d > 30.0}
	var mid_climb: bool = not _ramp_goal.is_empty() and _ramp_goal.get("climbing", false) and v.global_position.y < (_ramp_goal.top as Vector3).y - 0.6
	if absf(to.y) > 2.5 or mid_climb: # up on a deck or down on the road: go round by a ramp (and finish the climb)
		mode = "chase"
		return {"goal": _via_ramp(v, t.global_position + Vector3.UP * (5.0 if mid_climb else 0.0)), "throttle": 1.0, "turbo": d > 40.0}
	_ramp_goal = {}
	# Low on weapons or turbo and not in the thick of it: pick some up on the way.
	if d > 35.0:
		var detour := _detour(v)
		if detour:
			mode = "detour"
			return {"goal": detour.global_position, "throttle": 1.0}
	if running and d > 14.0:
		mode = "chase"
		phase = "approach"
		return {"goal": t.global_position + t_vel * 0.35, "throttle": 1.0, "turbo": d > 22.0}
	if d > HUNT_RANGE:
		mode = "hunt"
		phase = "approach"
		return {"goal": t.global_position, "throttle": 1.0, "turbo": d > 90.0}
	mode = "attack"
	return _attack_run(v, t, d, flat_to, delta)


## One attack run: come in beside the target on _side, swing toward its back, drive past,
## drift round to face it, pick a new side, again.
func _attack_run(v: Vehicle, t: Vehicle, d: float, flat_to: Vector3, delta: float) -> Dictionary:
	var t_fwd := t.flat_forward()
	var t_right := Vector3(-t_fwd.z, 0, t_fwd.x)
	var facing := v.flat_forward().angle_to(flat_to) # 0 = its nose points at the target
	match phase:
		"approach":
			# A feint now and then: switch sides mid-run (random, not a reaction to the player).
			if not _feinted and d < 24.0 and d > 12.0:
				_feinted = true
				if randf() < 0.3:
					_side = -_side
					_drift = true
			var lateral := clampf(d * 0.3, 3.5, 8.0)
			var behind := clampf((26.0 - d) / 26.0, 0.0, 1.0) * 7.0 # closer = aim further round its back
			var goal := t.global_position + t_right * _side * lateral - t_fwd * behind
			if d < 6.5 or (facing > 1.9 and d < 22.0):
				phase = "pass" # alongside or gone past: keep going
				_phase_t = randf_range(0.45, 0.85)
			return {"goal": goal, "throttle": 1.0}
		"pass":
			# Drive on past it, veering away so we never shove into it.
			_phase_t -= delta
			if _phase_t <= 0.0:
				phase = "turn"
			var away := -flat_to
			return {"goal": _keep_level(v, v.global_position + (v.flat_forward() + away * 0.9).normalized() * 25.0), "throttle": 1.0}
		_: # "turn": get some room, then drift round to face it again
			_drift = true
			if d < 16.0:
				return {"goal": _keep_level(v, v.global_position - flat_to * 20.0 + v.flat_forward() * 6.0), "throttle": 1.0}
			if facing < 0.45 or d > 40.0:
				phase = "approach"
				_feinted = false
				_side = 1.0 if randf() < 0.5 else -1.0
			return {"goal": t.global_position, "throttle": 0.9}


## Attack runs swing away to make room; never off the level we fight on (down a ramp or off the
## battleground edge, which made the AI go up and down the ramp instead of fighting). Tries the
## goal, then turned 60 and 120 degrees either way, then the stage centre.
func _keep_level(v: Vehicle, goal: Vector3) -> Vector3:
	if arena == null or not arena.has_method("ground"):
		return goal
	var here := v.global_position
	var off := goal - here
	off.y = 0.0
	for turn: float in [0.0, 1.05, -1.05, 2.1, -2.1]:
		var p := here + off.rotated(Vector3.UP, turn)
		if absf((arena.ground(p.x, p.z) as Vector3).y - here.y) < 1.5:
			return p
	return arena.center if "center" in arena else goal


func _wander_plan(v: Vehicle) -> Dictionary:
	mode = "wander"
	var half: float = arena.wander_half if arena else 60.0
	if _wander == Vector3.ZERO or v.global_position.distance_to(_wander) < 8.0:
		_ramp_goal = {}
		_wander = Vector3(randf_range(-half, half), 0, randf_range(-half, half))
		if arena and arena.has_method("ground"):
			_wander = arena.ground(_wander.x, _wander.z) # up on a deck or plateau: _via_ramp finds the way
	return {"goal": _via_ramp(v, _wander), "throttle": 1.0}


## A weapon pickup when we carry nothing but the special, or turbo when it runs low; only if close.
func _detour(v: Vehicle) -> Pickup:
	var armed := false
	for id in v.weapon_order:
		if id != v.special_id and v.ammo.get(id, 0) > 0:
			armed = true
	if not armed:
		var w := _nearest_pickup(v, "weapon")
		if w and v.global_position.distance_to(w.global_position) < 45.0:
			return w
	if v.turbo < 30.0:
		var tb := _nearest_pickup(v, "turbo")
		if tb and v.global_position.distance_to(tb.global_position) < 30.0:
			return tb
	return null


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
		if o.is_hidden() and v.global_position.distance_to(o.global_position) > 12.0:
			continue # invisible: lost past 12 m (design 5.2)
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
	# The goal moved a long way since this ramp was picked (it was chosen for a wander point, a
	# pickup, an old position of the target): pick again, unless already on the way up.
	if not _ramp_goal.is_empty() and not _ramp_goal.get("climbing", false) \
			and goal.distance_to(_ramp_goal.get("for", goal)) > 30.0:
		_ramp_goal = {}
	if _ramp_goal.is_empty():
		# Nearest ramp by the whole trip (to its foot, then from its top to the goal). One that went
		# wrong twice is avoided for a while, but not when every other ramp is much further: then
		# try it again (round 7: it drove across the map to another ramp and never got up).
		var best_d := INF
		var best: Dictionary = {}
		var best_any := INF
		var any: Dictionary = {}
		for r: Dictionary in arena.ramps:
			if absf(r.top.y - goal.y) > 2.0:
				continue
			var d: float = v.global_position.distance_to(r.foot) + (r.top as Vector3).distance_to(goal)
			if d < best_any:
				best_any = d
				any = r
			if d < best_d and not _bad_ramps.has(_ramp_key(r)):
				best_d = d
				best = r
		if best.is_empty() or best_d > best_any * 1.8 + 30.0:
			best = any
		if best.is_empty():
			return goal
		_ramp_goal = best.duplicate()
		_ramp_goal["climbing"] = false
		_ramp_goal["for"] = goal
	var foot: Vector3 = _ramp_goal.foot
	var top: Vector3 = _ramp_goal.top
	var axis := Vector3(foot.x - top.x, 0, foot.z - top.z).normalized() # from the top out to the foot
	var rel := v.global_position - top
	var lateral := absf(rel.dot(Vector3(-axis.z, 0, axis.x)))
	if not _ramp_goal.climbing:
		if foot.y > v.global_position.y + 3.5:
			return _lower_ramp(v, foot) # that ramp starts up on a plateau: get up there first
		var out := rel.dot(axis) # how far out along the ramp's line (the foot is ~RAMP_L + 10 out)
		var lined_up := v.flat_forward().dot(-axis) > 0.7 and lateral < 6.0
		if lined_up and out > 8.0:
			_ramp_goal.climbing = true
		elif Vector2(v.global_position.x - foot.x, v.global_position.z - foot.z).length() < 10.0:
			_ramp_goal["lineup"] = true
		if _ramp_goal.get("lineup", false) and not _ramp_goal.climbing:
			# Missed the line: swing out a bit further along it, then come back in straight.
			if Vector2(v.global_position.x - foot.x - axis.x * 12.0, v.global_position.z - foot.z - axis.z * 12.0).length() < 7.0:
				_ramp_goal["lineup"] = false
			return foot + axis * 12.0
		if not _ramp_goal.climbing:
			return foot
	# Climbing: drifted off the side before reaching the top? Abort, back out, line up again.
	if lateral > 9.0 and v.global_position.y < top.y - 1.0 and rel.dot(axis) > 2.0:
		_ramp_failed()
		return foot
	# Steer for the ramp's centre line a little ahead, not straight at the top: keeps it off the rails.
	return top + axis * maxf(rel.dot(axis) - 9.0, 0.0)


func _ramp_key(r: Dictionary) -> String:
	var f: Vector3 = r.foot
	return "%d_%d" % [roundi(f.x), roundi(f.z)]


## A climb that went wrong: try the same ramp once more, then avoid it for a while.
func _ramp_failed() -> void:
	if _ramp_goal.is_empty():
		return
	_ramp_fails += 1
	if _ramp_fails >= 2:
		_bad_ramps[_ramp_key(_ramp_goal)] = 25.0
		_ramp_fails = 0
	_ramp_goal = {}


## After backing out of a wall: a point along the wall (the side that heads toward the goal).
func _set_escape(v: Vehicle, goal: Vector3) -> void:
	var n: Vector3 = v._last_wall_normal if v._last_wall_normal.length() > 0.1 else -v.flat_forward()
	var along := n.cross(Vector3.UP).normalized()
	var to_goal := goal - v.global_position
	to_goal.y = 0.0
	if along.dot(to_goal) < 0.0:
		along = -along
	if randf() < 0.2:
		along = -along # now and then the other way, in case that side is blocked too
	_escape_goal = v.global_position + n * 8.0 + along * 22.0
	_escape = 1.0 + 1.3 # starts after the 1.3 s reverse


## Room to speed up before the wall between us and the target (a jump-up needs a run-up).
func _runway(v: Vehicle, t: Vehicle) -> bool:
	var origin := v.global_position + Vector3.UP * 1.0
	var to := t.global_position - v.global_position
	to.y = 0.0
	var q := PhysicsRayQueryParameters3D.create(origin, origin + to.normalized() * 14.0, WORLD_MASK)
	if v.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
		return true
	_no_jump = 4.0 # nose to the wall: take a ramp this time
	return false


## The 6 m energy jump onto a higher level when its edge is just the right distance ahead.
func _try_jump_up(v: Vehicle) -> void:
	if not _plan_jump or not v.is_on_floor() or v.speed < 14.0 or v.energy < Vehicle.JUMP_COST:
		return
	var origin := v.global_position + Vector3.UP * 1.0
	var fwd := v.flat_forward()
	var q := PhysicsRayQueryParameters3D.create(origin, origin + fwd * 22.0, WORLD_MASK)
	var hit := v.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or absf((hit.normal as Vector3).y) > 0.5:
		return
	var dist := origin.distance_to(hit.position)
	# Clear 5 m between about 0.35 s and 0.9 s after takeoff; the car's nose leads by half its length.
	var half: float = float(v.stats.get("size", Vector3(2, 2, 5)).z) * 0.5
	if dist < v.speed * 0.4 + half or dist > v.speed * 0.62 + half:
		return
	if arena and arena.has_method("ground"):
		var beyond: Vector3 = arena.ground(hit.position.x + fwd.x * 3.0, hit.position.z + fwd.z * 3.0)
		var rise := beyond.y - v.global_position.y
		if rise < 2.0 or rise > 5.6:
			return
	v.want_jump = true


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


## Nearest active pickup of a group: "health", "turbo" or "weapon" (on the same level as us).
func _nearest_pickup(v: Vehicle, what: String) -> Pickup:
	var best: Pickup = null
	var best_d := INF
	for node in v.get_tree().get_nodes_in_group("pickups"):
		var p := node as Pickup
		if not p.active:
			continue
		var ok := p.is_health() if what == "health" else (p.is_turbo() if what == "turbo" else (not p.is_health() and not p.is_turbo()))
		if not ok or (what != "health" and absf(p.global_position.y - v.global_position.y) > 3.0):
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
	if dist < 70.0 and angle < 0.35 and _clear_shot(v, t):
		v.in_fire_guns = true
	if mode == "retreat" and dist > 30.0:
		return # busy getting away
	if _special_timer <= 0.0 and v.ammo.get(v.special_id, 0) > 0 and _special_makes_sense(v, dist, angle):
		_special_timer = randf_range(3.0, 6.0) / aggression
		v.selected = maxi(v.weapon_order.find(v.special_id), 0)
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
			return dist < 18.0 and angle > 2.3 # a mine for the car on our tail
		"zoomy":
			return dist < 70.0 and angle < 0.5
		"sat":
			return dist < 70.0 and angle < 0.9
	return dist < 85.0 and angle < 0.6


func _special_makes_sense(v: Vehicle, dist: float, angle: float) -> bool:
	match v.special_id:
		"omni_taser":
			return dist < SPECIAL_RANGE and _clear_shot(v, v.target)
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
	elif live is Projectile: # napalm can in the air: drop it on whoever is under it
		var p := live as Projectile
		v.selected = maxi(v.weapon_order.find("napalm"), 0)
		for o in Specials.cars_near(v.get_parent(), p.global_position, 60.0, v):
			if Vector2(o.global_position.x - p.global_position.x, o.global_position.z - p.global_position.z).length() < 4.0:
				v.want_fire_weapon = true
				return
	elif live is Mine: # blow it when an enemy is close to it and we are not
		var m := live as Mine
		if v.global_position.distance_to(m.global_position) < 7.0:
			return
		for o in Specials.cars_near(v.get_parent(), m.global_position, 4.5, v):
			v.selected = maxi(v.weapon_order.find("remote"), 0)
			v.want_fire_weapon = true
			return


func _clear_shot(v: Vehicle, t: Vehicle) -> bool:
	var q := PhysicsRayQueryParameters3D.create(v.global_position + Vector3.UP * 1.2, t.global_position + Vector3.UP * 1.2, WORLD_MASK)
	return v.get_world_3d().direct_space_state.intersect_ray(q).is_empty()
