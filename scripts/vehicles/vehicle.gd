class_name Vehicle
extends CharacterBody3D
## Arcade combat vehicle shared by the player and the AI.
## A controller (PlayerController or AIDriver) fills the in_* fields each physics frame;
## this script turns them into driving, shooting and energy moves.
## Rules come from docs/design/01-characters.md (sections 1.3, 1.4, 1.7, 5) and the owner's revisions.

signal destroyed(vehicle: Vehicle, killer: Vehicle)
signal damaged(vehicle: Vehicle, amount: float, attacker: Vehicle)
signal weapons_changed(vehicle: Vehicle)
signal notice(vehicle: Vehicle, text: String) # short feedback for the player's HUD

const GRAVITY := 30.0
const BRAKE := 38.0
const COAST := 7.0
## Turbo (owner, play-test 1): weaker than before and it never refills by itself. Full at the start
## and after a respawn; every turbo pickup fills it up again (Pickup).
const TURBO_MULT := 1.28
const TURBO_ACCEL := 1.35
const TURBO_DRAIN := 22.0 # a full bar lasts about 4.5 s
const ENERGY_REGEN := 2.5
const ENERGY_PAUSE := 1.5 # no regen for this long after spending energy
const JUMP_COST := 25.0
const JUMP_VELOCITY := 13.4
const FREEZE_COST := 50.0
const FREEZE_BREAK := 15.0 # a single hit this big shatters the ice
const GRIT_TIME := 3.0 # immune to full disables after one ends
const SPAWN_SHIELD := 2.0
const WRECK_SOLID_TIME := 5.0 # wrecks stop blocking the road after this
const RAM_MIN_CLOSING := 10.0
const RAM_MAX := 25.0
const TARGET_RANGE := 120.0
const TARGET_CONE := deg_to_rad(40.0)
const AIM_ASSIST_CONE := deg_to_rad(12.0)

var car_id := ""
var stats := {}
var display_name := ""
var is_player := false
var controller: Object # has drive(vehicle, delta)
var arena_center := Vector3.ZERO # wall hits with no better choice turn toward here

# Controller inputs.
var in_throttle := 0.0 # -1 reverse .. 1 forward
var in_steer := 0.0 # -1 left .. 1 right
var in_handbrake := false
var in_turbo := false
var in_fire_guns := false
var in_fire_weapon := false # fire button held (charged specials)
var want_fire_weapon := false # one-shot requests, consumed here
var want_jump := false
var want_freeze := false

var max_health := 100.0
var health := 100.0
var energy := 100.0
var turbo := 100.0
var speed := 0.0 # signed forward speed the engine is aiming for
var mass := 1.4
var knockback := 1.0
var is_dead := false
var frozen_time := 0.0
var grit_time := 0.0
var burn_time := 0.0
var invulnerable_time := 0.0
var auto_target := true # the player locks automatically; the AI picks its own target
var target: Vehicle
var last_attacker: Vehicle

var ammo := {} # weapon id -> count
var weapon_order: Array[String] = []
var selected := 0
var special_id := ""
var special_charges := 2
var charging_id := "" # weapon being charged while the fire button is held (Napalm Cone)
var charge_time := 0.0

var model: Node3D
var _visual: Node3D
var _fx: VehicleFx
var _boosting := false
var _wheels: Array = []
var _steer_pivots: Array = []
var _wheel_radius := 0.5
var _gun_cooldown := 0.0
var _weapon_cooldowns := {} # weapon id -> seconds left. Per weapon: switching and firing another is instant (combos)
var _gun_index := 0
var _special_timer := 0.0
var _target_timer := 0.0
var _energy_pause := 0.0
var _burn_tick := 0.0
var _burn_source: Vehicle
var _clock := 0.0
var _ram_times := {} # other car's instance id -> time of our last ram on it
var _wall_cooldown := 0.0
var _wall_contact := 0.0
var _last_wall_normal := Vector3.ZERO
var _yaw_fix := 0.0 # pending heading correction from wall deflection (radians)
var _stuck_time := 0.0
var _wreck_time := 0.0
var _active_special: Node # live taser link or chain bomb: repeat fire presses go to it
var _smoke: CPUParticles3D
var _fire: CPUParticles3D
var _burn_fx: CPUParticles3D
var _ice: MeshInstance3D


## Call before adding to the tree.
func setup(id: String, player: bool) -> void:
	car_id = id
	stats = Roster.get_car(id)
	display_name = stats.get("name", id)
	is_player = player
	max_health = stats.get("max_health", 280.0)
	health = max_health
	mass = stats.get("mass", 1.4)
	knockback = stats.get("knockback", 1.0)
	special_id = stats.get("special", "")
	special_charges = int(WeaponData.get_def(special_id).get("charges", 2))
	ammo[special_id] = special_charges
	weapon_order = [special_id]

	collision_layer = 2
	collision_mask = 1 | 2
	floor_max_angle = deg_to_rad(48.0)
	floor_snap_length = 0.6
	wall_min_slide_angle = deg_to_rad(5.0)

	var size: Vector3 = stats.get("size", Vector3(2.2, 1.8, 5.0))
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = Vector3(0, size.y * 0.5, 0)
	add_child(shape)

	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	model = VehicleModels.build(id)
	_visual.add_child(model)
	_wheels = model.get_meta("wheels", [])
	_steer_pivots = model.get_meta("steer", [])
	_wheel_radius = model.get_meta("wheel_radius", 0.5)
	_fx = VehicleFx.new()
	_fx.name = "Fx"
	add_child(_fx)
	_fx.setup(model)

	var top: Vector3 = model.get_meta("top", Vector3(0, 2, 0))
	_smoke = FxKit.smoke(0.8, 24)
	_smoke.position = top
	_smoke.emitting = false
	_visual.add_child(_smoke)
	_fire = FxKit.fire(1.0, 30)
	_fire.position = top
	_fire.emitting = false
	_visual.add_child(_fire)
	_burn_fx = FxKit.fire(1.3, 36)
	_burn_fx.position = Vector3(0, size.y * 0.6, 0)
	_burn_fx.emission_sphere_radius = size.x * 0.5
	_burn_fx.emitting = false
	_visual.add_child(_burn_fx)

	_ice = MeshInstance3D.new()
	var ice_mesh := BoxMesh.new()
	ice_mesh.size = size + Vector3(0.5, 0.8, 0.5)
	_ice.mesh = ice_mesh
	var ice_mat := StandardMaterial3D.new()
	ice_mat.albedo_color = Color(0.6, 0.85, 1.0, 0.45)
	ice_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ice_mat.emission_enabled = true
	ice_mat.emission = Color(0.3, 0.6, 1.0)
	ice_mat.emission_energy_multiplier = 0.6
	ice_mat.roughness = 0.05
	_ice.material_override = ice_mat
	_ice.position = shape.position
	_ice.visible = false
	_visual.add_child(_ice)

	add_to_group("vehicles")


## Respawn protection: no damage, blinking, for a moment.
func protect(seconds := SPAWN_SHIELD) -> void:
	invulnerable_time = seconds


# ---------------------------------------------------------------- per frame

func _physics_process(delta: float) -> void:
	if is_dead:
		_wreck_physics(delta)
		return
	if controller:
		controller.drive(self, delta)
	else:
		_clear_inputs()
	_tick(delta)
	_drive(delta)
	_combat(delta)
	_animate(delta)


## A car nobody controls just rolls to a stop (cutscenes, tests, game over).
func _clear_inputs() -> void:
	in_throttle = 0.0
	in_steer = 0.0
	in_handbrake = false
	in_turbo = false
	in_fire_guns = false
	in_fire_weapon = false
	want_fire_weapon = false
	want_jump = false
	want_freeze = false


func _tick(delta: float) -> void:
	_clock += delta
	_gun_cooldown -= delta
	for id in _weapon_cooldowns.keys():
		_weapon_cooldowns[id] -= delta
		if _weapon_cooldowns[id] <= 0.0:
			_weapon_cooldowns.erase(id)
	_wall_cooldown -= delta
	_wall_contact -= delta
	if _energy_pause > 0.0:
		_energy_pause -= delta
	else:
		energy = minf(100.0, energy + ENERGY_REGEN * delta)
	if invulnerable_time > 0.0:
		invulnerable_time -= delta
		_visual.visible = invulnerable_time <= 0.0 or fmod(invulnerable_time, 0.2) > 0.08
	if grit_time > 0.0:
		grit_time -= delta
	if frozen_time > 0.0:
		frozen_time -= delta
		if frozen_time <= 0.0:
			_unfreeze()
	if burn_time > 0.0:
		burn_time -= delta
		_burn_tick += delta
		if _burn_tick >= 0.5:
			_burn_tick -= 0.5
			take_damage(WeaponData.BURN_DPS * 0.5 * WeaponData.DAMAGE_SCALE, _burn_source)
		if burn_time <= 0.0:
			_burn_fx.emitting = false
	# Specials recharge one charge at a time.
	if ammo.get(special_id, 0) < special_charges:
		_special_timer += delta
		if _special_timer >= float(WeaponData.get_def(special_id).get("recharge", 20.0)):
			_special_timer = 0.0
			ammo[special_id] = ammo.get(special_id, 0) + 1
			weapons_changed.emit(self)
	if auto_target:
		_target_timer -= delta
		if _target_timer <= 0.0:
			_target_timer = 0.2
			target = find_target()


func _drive(delta: float) -> void:
	var frozen := frozen_time > 0.0
	var throttle := 0.0 if frozen else in_throttle
	var steer := 0.0 if frozen else in_steer
	var handbrake := in_handbrake and not frozen
	var on_floor := is_on_floor()
	var brake: float = BRAKE * float(stats.get("brake_mult", 1.0))

	var top: float = stats.max_speed
	var boosting := in_turbo and turbo > 0.0 and throttle > 0.1 and not frozen
	_boosting = boosting
	if boosting:
		top *= TURBO_MULT
		turbo = maxf(0.0, turbo - TURBO_DRAIN * delta)

	if on_floor:
		var accel: float = stats.accel * (TURBO_ACCEL if boosting else 1.0)
		if throttle > 0.05:
			if speed < -0.5:
				speed = move_toward(speed, 0.0, brake * delta)
			else:
				speed = move_toward(speed, top * throttle, accel * delta)
		elif throttle < -0.05:
			if speed > 0.5:
				speed = move_toward(speed, 0.0, brake * delta)
			else:
				speed = move_toward(speed, -float(stats.reverse) * -throttle, accel * 0.7 * delta)
		else:
			speed = move_toward(speed, 0.0, COAST * delta)
		if handbrake:
			speed = move_toward(speed, 0.0, 12.0 * delta)
		if frozen:
			speed = move_toward(speed, 0.0, 60.0 * delta)
		if speed > top:
			speed = move_toward(speed, top, 12.0 * delta)

	# Steering: needs speed, reverses when backing up, sharper with the handbrake.
	var authority := clampf(absf(speed) / 7.0, 0.0, 1.0)
	if not on_floor:
		authority *= 0.3
	var turn: float = stats.handling * (float(stats.drift_turn) if handbrake else 1.0)
	turn *= lerpf(1.0, 0.78, clampf(absf(speed) / float(stats.max_speed), 0.0, 1.0)) # wider turns when fast
	var dir := 1.0 if speed >= 0.0 else -1.0
	rotate_y(-steer * turn * authority * dir * delta)
	# Wall deflection turns the car over a few frames instead of snapping.
	if absf(_yaw_fix) > 0.001:
		var step := _yaw_fix * minf(1.0, 14.0 * delta)
		rotate_y(step)
		_yaw_fix -= step

	var forward := flat_forward()
	var desired := forward * speed
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var grip: float = stats.grip * (float(stats.drift_grip) if handbrake else 1.0) # heavy cars barely slide
	if not on_floor:
		grip = 0.3
	hv = hv.lerp(desired, 1.0 - exp(-grip * delta))
	velocity.x = hv.x
	velocity.z = hv.z
	velocity.y -= GRAVITY * delta

	if want_jump:
		want_jump = false
		if on_floor and not frozen and spend_energy(JUMP_COST):
			velocity.y = JUMP_VELOCITY

	var before := velocity
	move_and_slide()
	_resolve_collisions(before)
	_unstick(delta, throttle)


func _resolve_collisions(before: Vector3) -> void:
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var n := c.get_normal()
		var other := c.get_collider()
		if other is Vehicle:
			_ram(other as Vehicle, before, n)
		elif other != null and other.has_method("vehicle_contact"):
			# Breakables (stands, glass, palms) shatter and barely slow the car.
			if other.vehicle_contact(self, before):
				velocity = Vector3(before.x, velocity.y, before.z)
				speed *= 0.9
			elif absf(n.y) < 0.55:
				_wall_hit(n)
		elif absf(n.y) < 0.55:
			_wall_hit(n)


## Twisted Metal wall rule: a wall never stops the car. Glancing hits slide along it, square hits
## bounce back a little and turn the nose toward the open side (design 1.3).
func _wall_hit(n: Vector3) -> void:
	var hn := Vector3(n.x, 0.0, n.z).normalized()
	_last_wall_normal = hn
	_wall_contact = 0.3
	if _wall_cooldown > 0.0 or absf(speed) < 1.5:
		return
	var fwd := flat_forward()
	var travel := fwd * signf(speed)
	var into := -travel.dot(hn) # 0 = sliding along the wall, 1 = straight into it
	if into < 0.05:
		return
	_wall_cooldown = 0.25
	var mass_factor := 0.75 if mass >= 2.0 else (1.25 if mass < 1.2 else 1.0)
	var tangent := travel - hn * travel.dot(hn)
	if tangent.length() < 0.15:
		# Dead square hit: go the way the driver steers, else toward the middle of the arena.
		var side := hn.cross(Vector3.UP)
		var pick := -signf(in_steer) if absf(in_steer) > 0.1 else 0.0
		if pick == 0.0:
			pick = 1.0 if side.dot(arena_center - global_position) >= 0.0 else -1.0
		tangent = side * pick
	tangent = tangent.normalized()
	var loss: float
	if into < 0.5: # under 30 degrees
		loss = 0.05
	elif into < 0.866: # 30 to 60 degrees
		loss = 0.15
	else:
		loss = 0.35
		velocity += hn * 6.0
	speed *= 1.0 - loss * mass_factor
	if speed < 0.0:
		return # backing into a wall: lose speed, keep the heading
	var target_dir := tangent
	if into >= 0.866:
		target_dir = fwd.rotated(Vector3.UP, signf(fwd.signed_angle_to(tangent, Vector3.UP)) * deg_to_rad(35.0))
	_yaw_fix = fwd.signed_angle_to(target_dir, Vector3.UP)


## Stuck helper (design 2.0.1 rule 9): pressing the gas for 2 s against the world without moving
## gives a small push away from the wall. Never against another car.
func _unstick(delta: float, throttle: float) -> void:
	var hspeed := Vector2(velocity.x, velocity.z).length()
	if absf(throttle) > 0.5 and _wall_contact > 0.0 and hspeed < 1.0 and frozen_time <= 0.0:
		_stuck_time += delta
		if _stuck_time > 2.0:
			_stuck_time = 0.0
			velocity += _last_wall_normal * 9.0 + Vector3.UP * 2.0
			_yaw_fix += deg_to_rad(90.0) * (1.0 if randf() < 0.5 else -1.0)
	else:
		_stuck_time = 0.0


## Ram damage (design 1.3): (closing speed - 10) * 0.5 * sqrt(my mass / its mass), max 25,
## once per second per pair. The rammer takes some back unless it is heavier.
func _ram(other: Vehicle, before: Vector3, n: Vector3) -> void:
	if other.is_dead:
		return
	var key := other.get_instance_id()
	if _clock - float(_ram_times.get(key, -10.0)) < 1.0:
		return
	var closing := (before - other.velocity).dot(-n)
	if closing < RAM_MIN_CLOSING:
		return
	_ram_times[key] = _clock
	var ratio := sqrt(mass / other.mass)
	var dmg := minf(RAM_MAX, (closing - RAM_MIN_CLOSING) * 0.5 * ratio)
	other.take_damage(dmg, self)
	var recoil := 0.2
	if mass < other.mass - 0.01:
		recoil = 0.3
	elif mass > other.mass + 0.01:
		recoil = 0.1
	take_damage(dmg * recoil, other)
	other.apply_impulse(-n * closing * 0.35 * other.knockback * ratio + Vector3.UP * 2.5)
	speed *= 0.6 if mass <= other.mass else 0.8


func apply_impulse(v: Vector3) -> void:
	velocity += v


func flat_forward() -> Vector3:
	var f := -global_transform.basis.z
	f.y = 0.0
	return f.normalized()


func aim_point() -> Vector3:
	return global_position + Vector3.UP * 1.0


# ---------------------------------------------------------------- energy

func spend_energy(amount: float) -> bool:
	if energy < amount:
		return false
	energy -= amount
	_energy_pause = ENERGY_PAUSE
	return true


# ---------------------------------------------------------------- combat

func _combat(delta: float) -> void:
	if frozen_time > 0.0:
		want_fire_weapon = false
		want_freeze = false
		_cancel_charge()
		return
	if in_fire_guns and _gun_cooldown <= 0.0:
		_gun_cooldown = WeaponData.get_def("guns").cooldown
		_fire_guns()
	if want_fire_weapon:
		want_fire_weapon = false
		if has_live_special():
			_active_special.fire_again() # taser mash, bomb detonation, napalm drop
		elif _can_charge():
			charging_id = selected_weapon() # fires when the button is let go
			charge_time = 0.0
		else:
			_fire_selected()
	if charging_id != "":
		if selected_weapon() != charging_id or ammo.get(charging_id, 0) <= 0:
			_cancel_charge()
		elif in_fire_weapon:
			charge_time = minf(charge_time + delta, charge_full(charging_id))
		else:
			var full := charge_time >= charge_full(charging_id)
			_cancel_charge()
			_fire_selected(full)
	if want_freeze:
		want_freeze = false
		if spend_energy(float(stats.get("freeze_cost", FREEZE_COST))):
			launch("freeze", target)


## Weapons with a charged shot (Napalm Cone): tap = normal shot, hold to the end = charged shot.
func _can_charge() -> bool:
	var id := selected_weapon()
	return id != "" and WeaponData.get_def(id).has("charge_time") and ammo.get(id, 0) > 0 and not _weapon_cooldowns.has(id)


static func charge_full(id: String) -> float:
	return float(WeaponData.get_def(id).get("charge_time", 2.0))


## 0..1 while charging (HUD meter); 0 when not charging.
func charge_ratio() -> float:
	return clampf(charge_time / charge_full(charging_id), 0.0, 1.0) if charging_id != "" else 0.0


func _cancel_charge() -> void:
	charging_id = ""
	charge_time = 0.0


## A turbo pickup fills the bar up again (turbo never refills by itself).
func refill_turbo() -> void:
	turbo = 100.0


## A taser link, chain bomb, napalm can or remote bomb that is still out (fire presses go to it).
func has_live_special() -> bool:
	return is_instance_valid(_active_special) and not _active_special.is_queued_for_deletion()


func set_live_special(node: Node) -> void:
	_active_special = node


func live_special() -> Node:
	return _active_special if has_live_special() else null


func _fire_guns() -> void:
	var muzzles: Array = model.get_meta("guns", [])
	if muzzles.is_empty():
		return
	_gun_index = (_gun_index + 1) % muzzles.size()
	var from := model.to_global(muzzles[_gun_index])
	var dir := flat_forward()
	# Light aim assist: bend shots toward a target that is almost dead ahead.
	if is_instance_valid(target) and not target.is_dead:
		var to_t := (target.aim_point() - from)
		if to_t.length() < 90.0 and dir.angle_to(to_t.normalized()) < AIM_ASSIST_CONE:
			dir = to_t.normalized()
	dir = (dir + Vector3(randf_range(-1, 1), randf_range(-0.5, 0.5), randf_range(-1, 1)) * 0.012).normalized()
	Projectile.spawn(get_parent(), "guns", from, dir, self, null)
	_fx.gun_fired(_gun_index)


func _fire_selected(charged := false) -> void:
	if weapon_order.is_empty():
		return
	selected = clampi(selected, 0, weapon_order.size() - 1)
	var id := weapon_order[selected]
	if _weapon_cooldowns.has(id):
		return
	if ammo.get(id, 0) <= 0:
		return
	ammo[id] -= 1
	_weapon_cooldowns[id] = float(WeaponData.get_def(id).get("cooldown", 0.5))
	Specials.fire(self, id, charged)
	if ammo[id] <= 0 and id != special_id:
		ammo.erase(id)
		weapon_order.erase(id)
		selected = clampi(selected, 0, weapon_order.size() - 1)
	weapons_changed.emit(self)


func launch_point() -> Vector3:
	return model.to_global(model.get_meta("launcher", Vector3(0, 2, -2.5)))


func launch(id: String, lock: Vehicle) -> void:
	var from := launch_point()
	var dir := flat_forward()
	if is_instance_valid(lock) and not lock.is_dead:
		var to_t := lock.aim_point() - from
		# Start roughly toward the target so homing doesn't have to U-turn.
		if dir.angle_to(to_t.normalized()) < deg_to_rad(60):
			dir = dir.lerp(to_t.normalized(), 0.6).normalized()
	else:
		lock = null
	Projectile.spawn(get_parent(), id, from, dir, self, lock)


func cycle_weapon(step: int) -> void:
	if weapon_order.is_empty():
		return
	selected = wrapi(selected + step, 0, weapon_order.size())
	weapons_changed.emit(self)


func selected_weapon() -> String:
	if weapon_order.is_empty():
		return ""
	return weapon_order[clampi(selected, 0, weapon_order.size() - 1)]


func add_ammo(id: String, amount: int) -> void:
	if not ammo.has(id):
		weapon_order.append(id)
	ammo[id] = ammo.get(id, 0) + amount
	weapons_changed.emit(self)


## Closest live enemy in front; falls back to the closest one anywhere in range.
func find_target() -> Vehicle:
	var best: Vehicle = null
	var best_score := INF
	var fwd := flat_forward()
	for node in get_tree().get_nodes_in_group("vehicles"):
		var v := node as Vehicle
		if v == self or v.is_dead:
			continue
		var to := v.global_position - global_position
		var dist := to.length()
		if dist > TARGET_RANGE:
			continue
		var angle := fwd.angle_to(Vector3(to.x, 0, to.z).normalized())
		var score := dist * (1.0 if angle < TARGET_CONE else 3.0) + angle * 20.0
		if score < best_score:
			best_score = score
			best = v
	return best


# ---------------------------------------------------------------- health and states

func take_damage(amount: float, attacker: Vehicle = null) -> void:
	if is_dead or amount <= 0.0 or invulnerable_time > 0.0:
		return
	health -= amount
	if attacker and attacker != self:
		last_attacker = attacker
	if frozen_time > 0.0 and amount >= FREEZE_BREAK:
		_unfreeze()
		FxKit.explosion(get_parent(), global_position + Vector3.UP, 0.7, Color(0.6, 0.9, 1.0))
	damaged.emit(self, amount, attacker)
	_update_damage_fx()
	if health <= 0.0:
		health = 0.0
		_die()


func heal(amount: float) -> void:
	if is_dead:
		return
	health = minf(max_health, health + amount)
	_update_damage_fx()
	damaged.emit(self, 0.0, null)


## Full disable. Fails while Grit (after a disable) or spawn protection is on.
func freeze(seconds: float) -> bool:
	if is_dead or grit_time > 0.0 or invulnerable_time > 0.0:
		return false
	frozen_time = maxf(frozen_time, seconds)
	_ice.visible = true
	return true


func _unfreeze() -> void:
	frozen_time = 0.0
	_ice.visible = false
	grit_time = GRIT_TIME


## Burning: 3 damage a second. A new flame renews the timer, it doesn't stack.
func ignite(seconds: float, by: Vehicle) -> void:
	if is_dead or invulnerable_time > 0.0:
		return
	burn_time = maxf(burn_time, seconds)
	_burn_source = by
	_burn_fx.emitting = true


func _update_damage_fx() -> void:
	var r := health / max_health
	_smoke.emitting = r < 0.5
	_fire.emitting = r < 0.25


func _die() -> void:
	is_dead = true
	frozen_time = 0.0
	burn_time = 0.0
	_burn_fx.emitting = false
	_fx.stop()
	_ice.visible = false
	_visual.visible = true
	FxKit.explosion(get_parent(), global_position + Vector3.UP * 1.5, 2.6)
	velocity += Vector3(randf_range(-3, 3), 9.0, randf_range(-3, 3))
	_char(model)
	_smoke.emitting = true
	_fire.emitting = true
	destroyed.emit(self, last_attacker)


## Burnt-out wreck look: everything goes black, lights go out.
func _char(node: Node) -> void:
	var burnt := MeshKit.mat(Color(0.05, 0.045, 0.04), 1.0)
	for child in node.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).material_override = burnt
		elif child is Light3D and not (child is FlickerLight):
			(child as Light3D).visible = false
		elif child is Blinker:
			child.process_mode = Node.PROCESS_MODE_DISABLED
		_char(child)


func _wreck_physics(delta: float) -> void:
	_wreck_time += delta
	if _wreck_time > WRECK_SOLID_TIME and collision_layer != 0:
		collision_layer = 0 # other cars drive through the burnt shell
		_fire.emitting = false
	velocity.y -= GRAVITY * delta
	var hv := Vector3(velocity.x, 0, velocity.z).move_toward(Vector3.ZERO, 12.0 * delta)
	velocity.x = hv.x
	velocity.z = hv.z
	move_and_slide()


# ---------------------------------------------------------------- visuals

func _animate(delta: float) -> void:
	_fx.update(delta, self, velocity, _boosting, in_handbrake and is_on_floor() and absf(speed) > 8.0)
	var spin := speed * delta / _wheel_radius
	for w in _wheels:
		(w as Node3D).rotate_x(-spin)
	for s in _steer_pivots:
		(s as Node3D).rotation.y = lerpf((s as Node3D).rotation.y, -in_steer * 0.45, 12.0 * delta)

	# Lean the body into the ground slope, roll a little in turns, pitch in the air.
	var up := Vector3.UP
	if is_on_floor():
		up = global_transform.basis.inverse() * get_floor_normal()
	var roll := -in_steer * clampf(absf(speed) / stats.max_speed, 0.0, 1.0) * float(model.get_meta("lean", 0.06))
	var pitch := 0.0 if is_on_floor() else clampf(velocity.y * 0.02, -0.3, 0.3)
	var target_basis := Basis(Quaternion(Vector3.UP, up.normalized())) * Basis.from_euler(Vector3(pitch, 0, roll))
	_visual.basis = _visual.basis.slerp(target_basis.orthonormalized(), clampf(10.0 * delta, 0.0, 1.0))
