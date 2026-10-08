class_name Vehicle
extends CharacterBody3D
## Arcade combat vehicle shared by the player and the AI.
## A controller (PlayerController or AIDriver) fills the in_* fields each physics frame;
## this script turns them into driving, shooting and energy moves.

signal destroyed(vehicle: Vehicle, killer: Vehicle)
signal damaged(vehicle: Vehicle, amount: float, attacker: Vehicle)
signal weapons_changed(vehicle: Vehicle)

const GRAVITY := 30.0
const BRAKE := 38.0
const COAST := 7.0
const TURBO_MULT := 1.45
const TURBO_DRAIN := 40.0
const TURBO_REGEN := 10.0
const ENERGY_REGEN := 5.0
const JUMP_COST := 25.0
const JUMP_VELOCITY := 13.0
const FREEZE_COST := 50.0
const TARGET_RANGE := 110.0
const TARGET_CONE := deg_to_rad(40.0)
const AIM_ASSIST_CONE := deg_to_rad(12.0)

var car_id := ""
var stats := {}
var display_name := ""
var is_player := false
var controller: Object # has drive(vehicle, delta)

# Controller inputs.
var in_throttle := 0.0 # -1 reverse .. 1 forward
var in_steer := 0.0 # -1 left .. 1 right
var in_handbrake := false
var in_turbo := false
var in_fire_guns := false
var want_fire_weapon := false # one-shot requests, consumed here
var want_jump := false
var want_freeze := false

var max_health := 100.0
var health := 100.0
var energy := 100.0
var turbo := 100.0
var speed := 0.0 # signed forward speed the engine is aiming for
var is_dead := false
var frozen_time := 0.0
var auto_target := true # the player locks automatically; the AI picks its own target
var target: Vehicle
var last_attacker: Vehicle

var ammo := {} # weapon id -> count
var weapon_order: Array[String] = []
var selected := 0
var special_id := ""

var model: Node3D
var _visual: Node3D
var _wheels: Array = []
var _steer_pivots: Array = []
var _wheel_radius := 0.5
var _gun_cooldown := 0.0
var _weapon_cooldown := 0.0
var _gun_index := 0
var _special_timer := 0.0
var _target_timer := 0.0
var _ram_cooldown := 0.0
var _smoke: CPUParticles3D
var _fire: CPUParticles3D
var _ice: MeshInstance3D


## Call before adding to the tree.
func setup(id: String, player: bool) -> void:
	car_id = id
	stats = Roster.get_car(id)
	display_name = stats.get("name", id)
	is_player = player
	max_health = stats.get("max_health", 100.0)
	health = max_health
	special_id = stats.get("special", "")
	ammo[special_id] = WeaponData.SPECIAL_START_AMMO
	weapon_order = [special_id]

	collision_layer = 2
	collision_mask = 1 | 2
	floor_max_angle = deg_to_rad(48.0)
	floor_snap_length = 0.6
	wall_min_slide_angle = deg_to_rad(10.0)

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

	var top: Vector3 = model.get_meta("top", Vector3(0, 2, 0))
	_smoke = FxKit.smoke(0.8, 24)
	_smoke.position = top
	_smoke.emitting = false
	_visual.add_child(_smoke)
	_fire = FxKit.fire(1.0, 30)
	_fire.position = top
	_fire.emitting = false
	_visual.add_child(_fire)

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
	_combat()
	_animate(delta)


## A car nobody controls just rolls to a stop (cutscenes, tests, game over).
func _clear_inputs() -> void:
	in_throttle = 0.0
	in_steer = 0.0
	in_handbrake = false
	in_turbo = false
	in_fire_guns = false
	want_fire_weapon = false
	want_jump = false
	want_freeze = false


func _tick(delta: float) -> void:
	_gun_cooldown -= delta
	_weapon_cooldown -= delta
	_ram_cooldown -= delta
	energy = minf(100.0, energy + ENERGY_REGEN * delta)
	if frozen_time > 0.0:
		frozen_time -= delta
		if frozen_time <= 0.0:
			_ice.visible = false
	# Specials recharge one charge at a time, up to the starting amount.
	if ammo.get(special_id, 0) < WeaponData.SPECIAL_START_AMMO:
		_special_timer += delta
		if _special_timer >= WeaponData.SPECIAL_RECHARGE_SECONDS:
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

	var top: float = stats.max_speed
	var boosting := in_turbo and turbo > 0.0 and throttle > 0.1 and not frozen
	if boosting:
		top *= TURBO_MULT
		turbo = maxf(0.0, turbo - TURBO_DRAIN * delta)
	else:
		turbo = minf(100.0, turbo + TURBO_REGEN * delta)

	if on_floor:
		var accel: float = stats.accel * (1.6 if boosting else 1.0)
		if throttle > 0.05:
			if speed < -0.5:
				speed = move_toward(speed, 0.0, BRAKE * delta)
			else:
				speed = move_toward(speed, top * throttle, accel * delta)
		elif throttle < -0.05:
			if speed > 0.5:
				speed = move_toward(speed, 0.0, BRAKE * delta)
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
	var turn: float = stats.handling * (1.7 if handbrake else 1.0)
	var dir := 1.0 if speed >= 0.0 else -1.0
	rotate_y(-steer * turn * authority * dir * delta)

	var forward := _flat_forward()
	var desired := forward * speed
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var grip: float = stats.grip * (0.22 if handbrake else 1.0)
	if not on_floor:
		grip = 0.3
	hv = hv.lerp(desired, 1.0 - exp(-grip * delta))
	velocity.x = hv.x
	velocity.z = hv.z
	velocity.y -= GRAVITY * delta

	if want_jump:
		want_jump = false
		if on_floor and energy >= JUMP_COST and not frozen:
			energy -= JUMP_COST
			velocity.y = JUMP_VELOCITY

	var before := velocity
	move_and_slide()
	_resolve_collisions(before, forward)


func _resolve_collisions(before: Vector3, forward: Vector3) -> void:
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var n := c.get_normal()
		var other := c.get_collider()
		if other is Vehicle:
			_ram(other as Vehicle, before, n)
		elif absf(n.y) < 0.55:
			# Driving into a wall kills engine speed in proportion to how square the hit is.
			var into := -forward.dot(n) * signf(speed)
			if into > 0.25:
				speed *= clampf(1.0 - into * 0.6, 0.0, 1.0)


func _ram(other: Vehicle, before: Vector3, n: Vector3) -> void:
	if _ram_cooldown > 0.0 or other.is_dead:
		return
	var closing := (before - other.velocity).dot(-n)
	if closing < 9.0:
		return
	_ram_cooldown = 0.6
	other.take_damage((closing - 7.0) * 0.7, self)
	other.apply_impulse(-n * closing * 0.45 + Vector3.UP * 3.0)
	speed *= 0.5


func apply_impulse(v: Vector3) -> void:
	velocity += v


func _flat_forward() -> Vector3:
	var f := -global_transform.basis.z
	f.y = 0.0
	return f.normalized()


# ---------------------------------------------------------------- combat

func _combat() -> void:
	if frozen_time > 0.0:
		want_fire_weapon = false
		want_freeze = false
		return
	if in_fire_guns and _gun_cooldown <= 0.0:
		_gun_cooldown = WeaponData.get_def("guns").cooldown
		_fire_guns()
	if want_fire_weapon:
		want_fire_weapon = false
		_fire_selected()
	if want_freeze:
		want_freeze = false
		if energy >= FREEZE_COST:
			energy -= FREEZE_COST
			_launch("freeze", target)


func _fire_guns() -> void:
	var muzzles: Array = model.get_meta("guns", [])
	if muzzles.is_empty():
		return
	_gun_index = (_gun_index + 1) % muzzles.size()
	var from := model.to_global(muzzles[_gun_index])
	var dir := _flat_forward()
	# Light aim assist: bend shots toward a target that is almost dead ahead.
	if is_instance_valid(target) and not target.is_dead:
		var to_t := (target.global_position + Vector3.UP - from)
		if to_t.length() < 90.0 and dir.angle_to(to_t.normalized()) < AIM_ASSIST_CONE:
			dir = to_t.normalized()
	dir = (dir + Vector3(randf_range(-1, 1), randf_range(-0.5, 0.5), randf_range(-1, 1)) * 0.012).normalized()
	Projectile.spawn(get_parent(), "guns", from, dir, self, null)


func _fire_selected() -> void:
	if weapon_order.is_empty() or _weapon_cooldown > 0.0:
		return
	selected = clampi(selected, 0, weapon_order.size() - 1)
	var id := weapon_order[selected]
	if ammo.get(id, 0) <= 0:
		return
	ammo[id] -= 1
	_weapon_cooldown = WeaponData.get_def(id).get("cooldown", 0.5)
	_launch(id, target)
	if ammo[id] <= 0 and id != special_id:
		ammo.erase(id)
		weapon_order.erase(id)
		selected = clampi(selected, 0, weapon_order.size() - 1)
	weapons_changed.emit(self)


func _launch(id: String, lock: Vehicle) -> void:
	var from := model.to_global(model.get_meta("launcher", Vector3(0, 2, -2.5)))
	var dir := _flat_forward()
	if is_instance_valid(lock) and not lock.is_dead:
		var to_t := lock.global_position + Vector3.UP - from
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
	var fwd := _flat_forward()
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


# ---------------------------------------------------------------- health

func take_damage(amount: float, attacker: Vehicle = null) -> void:
	if is_dead or amount <= 0.0:
		return
	health -= amount
	if attacker and attacker != self:
		last_attacker = attacker
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


func freeze(seconds: float) -> void:
	if is_dead:
		return
	frozen_time = maxf(frozen_time, seconds)
	_ice.visible = true


func _update_damage_fx() -> void:
	var r := health / max_health
	_smoke.emitting = r < 0.5
	_fire.emitting = r < 0.25


func _die() -> void:
	is_dead = true
	frozen_time = 0.0
	_ice.visible = false
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
	velocity.y -= GRAVITY * delta
	var hv := Vector3(velocity.x, 0, velocity.z).move_toward(Vector3.ZERO, 12.0 * delta)
	velocity.x = hv.x
	velocity.z = hv.z
	move_and_slide()


# ---------------------------------------------------------------- visuals

func _animate(delta: float) -> void:
	var spin := speed * delta / _wheel_radius
	for w in _wheels:
		(w as Node3D).rotate_x(-spin)
	for s in _steer_pivots:
		(s as Node3D).rotation.y = lerpf((s as Node3D).rotation.y, -in_steer * 0.45, 12.0 * delta)

	# Lean the body into the ground slope, roll a little in turns, pitch in the air.
	var up := Vector3.UP
	if is_on_floor():
		up = global_transform.basis.inverse() * get_floor_normal()
	var roll := -in_steer * clampf(absf(speed) / stats.max_speed, 0.0, 1.0) * 0.06
	var pitch := 0.0 if is_on_floor() else clampf(velocity.y * 0.02, -0.3, 0.3)
	var target_basis := Basis(Quaternion(Vector3.UP, up.normalized())) * Basis.from_euler(Vector3(pitch, 0, roll))
	_visual.basis = _visual.basis.slerp(target_basis.orthonormalized(), clampf(10.0 * delta, 0.0, 1.0))
