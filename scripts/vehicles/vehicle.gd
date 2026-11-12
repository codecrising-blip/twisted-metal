class_name Vehicle
extends RigidBody3D
## Arcade combat vehicle shared by the player and the AI.
## A controller (PlayerController or AIDriver) fills the in_* fields each physics frame;
## this script turns them into driving, shooting and energy moves.
## Rules come from docs/design/01-characters.md (sections 1.3, 1.4, 1.7, 5) and the owner's revisions.

signal destroyed(vehicle: Vehicle, killer: Vehicle)
signal damaged(vehicle: Vehicle, amount: float, attacker: Vehicle)
signal weapons_changed(vehicle: Vehicle)
signal notice(vehicle: Vehicle, text: String) # short feedback for the player's HUD
signal wall_slammed(vehicle: Vehicle, impact: float) # camera shake, sparks, sound

const GRAVITY := 30.0
const BRAKE := 26.0 # m/s^2 on the forward speed (about a second from full speed)
const HANDBRAKE_DECEL := 7.0
const COAST := 7.0
## Turbo (owner, play-test 1): weaker than before and it never refills by itself. Full at the start
## and after a respawn; every turbo pickup fills it up again (Pickup).
const TURBO_MULT := 1.28
const TURBO_ACCEL := 1.35
const TURBO_DRAIN := 20.0 # a full bar lasts 5 s (owner, session 6)
const TURBO_AIR_THRUST := 18.0 # m/s^2: turbo in the air pushes the car on (jump + turbo onto a ledge)
const TURBO_PUTS_OUT_FIRE := 0.5 # seconds of turbo blow out the flames
const ENERGY_REGEN := 2.5
const ENERGY_PAUSE := 1.5 # no regen for this long after spending energy
const JUMP_COST := 25.0
const JUMP_VELOCITY := 19.0 # 6 m high (owner, session 6): over the 5 m battleground walls for surprise entries
# Springs under the body (round 5, real physics). SUSP_K is stiffness per unit mass (rad/s squared):
# the body sinks GRAVITY / SUSP_K at rest, so the rest length puts the wheels' bottoms at y = 0.
const SUSP_TOP := 0.8 # ray start above the wheels' bottoms, inside the body
const SUSP_K := 190.0 # about 2.2 Hz
const SUSP_REST := SUSP_TOP + GRAVITY / SUSP_K
const SUSP_DROOP := 0.25 # wheels still count as touching this far below rest
const SUSP_DAMP := 0.9 # 2 x damping ratio
const BODY_CLEARANCE := 0.3 # the collision box starts this high: wheels hold it, the box takes the hard knocks
const YAW_RESPONSE := 40.0 # rad/s^2: steering reaches its turn rate in a blink, a hit can still swing it
const RECOVER_ROLL := 7.0 # rad/s roll when gas + left/right rights a flipped car
const RECOVER_HOP := 5.5 # m/s lift as the roll starts (again every half second until it is back up)
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
var speed := 0.0 # signed forward speed (set it to launch the car that fast)
var weight := 1.4 # design class: light 1.0, medium 1.4, heavy 2.0, super 2.8 (rams, knockback, physics mass)
## Same name as before the rigid body (AI, weapons, tests use it).
var velocity: Vector3:
	get:
		return linear_velocity
	set(value):
		linear_velocity = value
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
var _turbo_run := 0.0
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
var _speed_out := 0.0 # forward speed at the end of the last frame (detects outside changes to `speed`)
var _wall_pin := 0.0 # after slamming into a wall: scraping against it is slow until you steer away or back off
var _flash_meshes: Array[MeshInstance3D] = [] # flash white when hit
var _flash_time := 0.0
var _jolt := Vector3.ZERO # body knocked off its seat by a hit, springs back
var _charge_fx: Node3D # glow growing on the launcher while a charged shot builds
static var _white: StandardMaterial3D
static var _blob_mat: StandardMaterial3D
var _blob: MeshInstance3D # soft round shadow under the car on LOW (TM2 style; real shadows are off there)
var _stuck_time := 0.0
var _wreck_time := 0.0
var _active_special: Node # live taser link, chain bomb, napalm can or mine: repeat fire presses go to it
var _live_weapon := "" # the weapon that left it out ("" = any fire press goes to it)
# Physics state (round 5).
var flipped := false # lying on its roof or side: gas + left/right rolls it back
var _grounded := false
var _ground_n := Vector3.UP
var _wheel_comp: Array[float] = [0.0, 0.0, 0.0, 0.0] # spring compression per corner (visual wheel travel)
var _prev_velocity := Vector3.ZERO # before this step's contacts (rams, walls, breakables)
var _lying_time := 0.0
var _recover_kick := 0.0
var _wheel_rest: Dictionary = {} # wheel node -> its resting position
var _lean := 0.0
var _squish := Vector3.ZERO # elastic dip from a hit (rotation vector, car space)
var _squish_vel := Vector3.ZERO
var _wobble_t := 0.0 # homing hit: the steering twitches
var _wobble_dir := 1.0
var _smoke: CPUParticles3D
var _fire: CPUParticles3D
var _burn_fx: CPUParticles3D
var _ice: MeshInstance3D
# Sound loops (the owner's TM2 recordings, session 6): engine by weight class, guns and tire skid
# while they happen. Null when a file is missing.
var _gun_snd: AudioStreamPlayer3D
var _skid_snd: AudioStreamPlayer3D
var _gun_snd_t := 0.0
var _shells := 0
var _eng := {} # engine layer ("idle", "slow", "fast") -> looping player, crossfaded by speed (TM 2012 sets)
var _eng_set := ""
var _rev_cool := 0.0
var _prev_throttle := 0.0
var _was_skidding := false
var _screech_t := 0.0


## Call before adding to the tree.
func setup(id: String, player: bool) -> void:
	car_id = id
	stats = Roster.get_car(id)
	display_name = stats.get("name", id)
	is_player = player
	max_health = stats.get("max_health", 280.0)
	health = max_health
	weight = stats.get("mass", 1.4)
	knockback = stats.get("knockback", 1.0)
	special_id = stats.get("special", "")
	special_charges = int(WeaponData.get_def(special_id).get("charges", 2))
	ammo[special_id] = special_charges
	weapon_order = [special_id]

	collision_layer = 2
	collision_mask = 1 | 2
	# A real body (round 5): mass by class, centre of mass low in the chassis, gravity as strong as
	# before, metal-on-asphalt friction for roof slides and scrapes, no sleeping.
	var size: Vector3 = stats.get("size", Vector3(2.2, 1.8, 5.0))
	mass = rigid_mass()
	gravity_scale = GRAVITY / float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, size.y * 0.38, 0)
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.6
	can_sleep = false
	contact_monitor = true
	max_contacts_reported = 8
	var pm := PhysicsMaterial.new()
	pm.friction = 0.35
	pm.bounce = 0.05
	physics_material_override = pm

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, size.y - BODY_CLEARANCE, size.z)
	shape.shape = box
	shape.position = Vector3(0, BODY_CLEARANCE + (size.y - BODY_CLEARANCE) * 0.5, 0)
	add_child(shape)

	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	model = VehicleModels.build(id)
	_visual.add_child(model)
	_wheels = model.get_meta("wheels", [])
	_steer_pivots = model.get_meta("steer", [])
	_wheel_radius = model.get_meta("wheel_radius", 0.5)
	for w: Node3D in _wheels:
		_wheel_rest[w] = w.position
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		_flash_meshes.append(mi as MeshInstance3D)
	if _blob_mat == null:
		_blob_mat = StandardMaterial3D.new()
		_blob_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_blob_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_blob_mat.albedo_texture = FxKit.soft_texture()
		_blob_mat.albedo_color = Color(0, 0, 0, 0.75)
	_blob = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(size.x * 1.5, size.z * 1.25)
	_blob.mesh = plane
	_blob.material_override = _blob_mat
	_blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_blob.top_level = true
	_blob.visible = not GraphicsSettings.high
	_blob.add_to_group(GraphicsSettings.BLOB_GROUP)
	add_child(_blob)
	_fx = VehicleFx.new()
	_fx.name = "Fx"
	add_child(_fx)
	# Engine: idle, slow and fast loops of this car's own engine, crossfaded by speed (round 5).
	_eng_set = str(stats.get("engine", "suv"))
	for layer: String in ["idle", "slow", "fast"]:
		var file := "engine_%s_%s" % [_eng_set, layer]
		if GameFeel.streams(file).is_empty():
			file = "engine_%s_slow" % _eng_set # no fast recording: the slow one, pitched up
		var p := GameFeel.loop(file, self, -60.0, 10.0)
		if p:
			_eng[layer] = p
	_gun_snd = GameFeel.loop("guns_loop", self, -9.0, 14.0)
	_skid_snd = GameFeel.loop("skid_loop", self, -14.0, 10.0)
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
		_wreck_time += delta
		if _wreck_time > WRECK_SOLID_TIME and collision_layer != 0:
			collision_layer = 0 # other cars drive through the burnt shell
			collision_mask = 1
			_fire.emitting = false
		return
	if controller:
		controller.drive(self, delta)
	else:
		_clear_inputs()
	_tick(delta)
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
	# Specials recharge one charge at a time; the slot comes back with the first one.
	if ammo.get(special_id, 0) < special_charges:
		_special_timer += delta
		if _special_timer >= float(WeaponData.get_def(special_id).get("recharge", 20.0)):
			_special_timer = 0.0
			ammo[special_id] = ammo.get(special_id, 0) + 1
			if ammo[special_id] == 1 and is_player:
				notice.emit(self, "%s READY" % String(WeaponData.get_def(special_id).get("label", special_id)).to_upper())
			_refresh_slots()
	# A napalm can, mine or taser link that is over frees its empty slot.
	if _live_weapon != "" and not has_live_special():
		_live_weapon = ""
		_refresh_slots()
	if auto_target:
		_target_timer -= delta
		if _target_timer <= 0.0:
			_target_timer = 0.2
			target = find_target()


# ---------------------------------------------------------------- physics (owner, round 5: option A)
# The car is a real rigid body: a box with mass, a centre of mass and inertia, held up by four
# spring-damper "wheels" (rays from the corners). Gravity, ledges, hills, landings, rolls and flips
# all come out of the physics: a car with its back over a ledge drops its back first and pivots on
# the edge; a hill crest throws a fast car into the air; a car on its roof slides on its roof.
# The tyres are arcade-tuned (the drift, brakes and grip numbers from Roster, owner-rated): they act
# along the ground under the wheels, so they only work while the wheels touch it.

## Body-space corners where the four spring "wheels" sit (x, z) and their ray tops.
func _wheel_corners() -> Array[Vector3]:
	var size: Vector3 = stats.get("size", Vector3(2.2, 1.8, 5.0))
	var hx := size.x * 0.42
	var hz := size.z * 0.38
	return [Vector3(-hx, SUSP_TOP, -hz), Vector3(hx, SUSP_TOP, -hz), Vector3(-hx, SUSP_TOP, hz), Vector3(hx, SUSP_TOP, hz)]


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var dt := state.step
	var xf := state.transform
	var up := xf.basis.y
	var v := state.linear_velocity
	if is_dead:
		_prev_velocity = v
		return
	# Springs: each corner's ray finds the ground below it (along the body's own down).
	var space := state.get_space_state()
	var touching := 0
	var normal_sum := Vector3.ZERO
	var k: float = SUSP_K * rigid_mass() / 4.0
	var c: float = SUSP_DAMP * sqrt(SUSP_K) * rigid_mass() / 4.0
	var i := 0
	for corner: Vector3 in _wheel_corners():
		var from := xf * corner
		var q := PhysicsRayQueryParameters3D.create(from, from - up * (SUSP_REST + SUSP_DROOP), 1, [get_rid()])
		var hit := space.intersect_ray(q)
		var comp := 0.0
		if not hit.is_empty():
			var dist := from.distance_to(hit.position)
			comp = SUSP_REST - dist
			if comp > -SUSP_DROOP * 0.5:
				touching += 1
				normal_sum += hit.normal
			if comp > 0.0:
				var arm := from - xf.origin
				var point_vel := v + state.angular_velocity.cross(arm)
				var f := maxf(0.0, k * comp - c * point_vel.dot(up))
				state.apply_force(up * f, (hit.position as Vector3) - xf.origin)
		_wheel_comp[i] = comp
		i += 1
	var upright := up.y > 0.45
	_grounded = touching >= 2 and upright
	_ground_n = (normal_sum / maxf(1.0, touching)).normalized() if touching > 0 else Vector3.UP
	v = _upside_watch(dt, up, state, v)
	if _grounded:
		v = _tyres(state, v, dt)
	else:
		v = _in_air(state, v, dt)
	if want_jump:
		want_jump = false
		if _grounded and frozen_time <= 0.0 and not flipped and spend_energy(JUMP_COST):
			v.y = maxf(v.y, JUMP_VELOCITY)
	state.linear_velocity = v
	_contacts(state)
	_unstick(dt)
	_prev_velocity = state.linear_velocity
	speed = state.linear_velocity.dot(_drive_forward())
	_speed_out = speed


## Forward along the ground: the body's nose, flattened onto the surface the wheels stand on.
func _drive_forward() -> Vector3:
	var f := -global_basis.z
	var n := _ground_n if _grounded else Vector3.UP
	f -= n * f.dot(n)
	return f.normalized() if f.length() > 0.01 else flat_forward()


## On the wheels: gas, brakes, handbrake drift, grip and steering (the tuned arcade model, applied
## in the plane of the ground so slopes, ramps and hill crests are real).
func _tyres(state: PhysicsDirectBodyState3D, v: Vector3, dt: float) -> Vector3:
	var frozen := frozen_time > 0.0
	var throttle := 0.0 if frozen else in_throttle
	var steer := 0.0 if frozen else in_steer
	var handbrake := in_handbrake and not frozen
	var brake: float = BRAKE * float(stats.get("brake_mult", 1.0))
	_wall_pin -= dt
	var n := _ground_n
	var forward := _drive_forward()
	var right := forward.cross(n).normalized()
	var v_f := v.dot(forward)
	var v_l := v.dot(right)
	var v_n := v.dot(n)
	if absf(speed - _speed_out) > 0.01:
		v_f = speed # someone set the speed directly (spawn, tests, teleport): take it
	var top: float = stats.max_speed
	var boosting := _turbo_step(signf(throttle) if absf(throttle) > 0.1 else 0.0, dt)
	if boosting:
		top *= TURBO_MULT
	var sliding := clampf(absf(v_l) / 10.0, 0.0, 1.0) # tyres busy holding a slide brake less
	var accel: float = stats.accel * (TURBO_ACCEL if boosting else 1.0)
	var braking := false
	if throttle > 0.05:
		if v_f < -0.5:
			v_f = move_toward(v_f, 0.0, brake * dt)
			braking = true
		else:
			v_f = move_toward(v_f, top * throttle, accel * dt)
	elif throttle < -0.05:
		if v_f > 0.5:
			v_f = move_toward(v_f, 0.0, brake * (1.0 - 0.45 * sliding) * dt)
			braking = true
		else:
			v_f = move_toward(v_f, -float(stats.reverse) * -throttle * (2.0 if boosting else 1.0), accel * 0.7 * dt)
	else:
		v_f = move_toward(v_f, 0.0, COAST * dt)
	if handbrake:
		v_f = move_toward(v_f, 0.0, HANDBRAKE_DECEL * dt)
	if frozen:
		v_f = move_toward(v_f, 0.0, 60.0 * dt)
	if v_f > top:
		v_f = move_toward(v_f, top, 12.0 * dt)
	if _wall_pin > 0.0 and forward.dot(-_last_wall_normal) > 0.3:
		v_f = minf(v_f, 4.0) # nose against the wall: scraping out is slow
	var grip: float = stats.grip * (float(stats.drift_grip) if handbrake else 1.0)
	if braking and absf(v_l) > 3.0:
		grip *= 0.55
	v_l *= exp(-grip * dt)
	# Steering turns the car about the ground's normal; a hit can still knock it round for a moment.
	var authority := clampf(absf(v_f) / 7.0, 0.0, 1.0)
	var turn: float = stats.handling * (float(stats.drift_turn) if handbrake else 1.0)
	turn *= lerpf(1.0, 0.78, clampf(absf(v_f) / float(stats.max_speed), 0.0, 1.0)) # wider turns when fast
	var yaw := -steer * turn * authority * (1.0 if v_f >= 0.0 else -1.0)
	if _wobble_t > 0.0: # a homing hit knocks the steering a little
		_wobble_t -= dt
		yaw += _wobble_dir * 1.3
	if absf(_yaw_fix) > 0.001: # a glancing wall hit turns the car along the wall over a few frames
		var step := _yaw_fix * minf(1.0, 14.0 * dt)
		yaw += step / dt
		_yaw_fix -= step
	var w := state.angular_velocity
	var w_n := w.dot(n)
	state.angular_velocity = w + n * (move_toward(w_n, yaw, YAW_RESPONSE * dt) - w_n)
	return forward * v_f + right * v_l + n * v_n


## Wheels off the ground: momentum carries on; turbo still pushes the nose's way (jump + turbo onto
## a ledge), and backwards too.
func _in_air(state: PhysicsDirectBodyState3D, v: Vector3, dt: float) -> Vector3:
	var hv := Vector3(v.x, 0.0, v.z)
	var forward := flat_forward()
	var throttle := in_throttle if frozen_time <= 0.0 and not flipped else 0.0
	var dir := signf(throttle) if absf(throttle) > 0.1 else 1.0
	if flipped:
		_turbo_step(0.0, dt)
		return v
	if _turbo_step(dir, dt):
		var air_top: float = float(stats.max_speed) * TURBO_MULT if dir > 0.0 else float(stats.reverse) * 2.0
		var along := hv.dot(forward)
		var target := move_toward(along, air_top * dir, TURBO_AIR_THRUST * dt)
		hv += forward * (target - along)
	hv -= Vector3(v.x, 0.0, v.z) - Vector3(v.x, 0.0, v.z) * exp(-0.05 * dt)
	return Vector3(hv.x, v.y, hv.z)


## Turbo bookkeeping for this step: burns the tank, blows out fire. True while boosting.
func _turbo_step(dir: float, dt: float) -> bool:
	var boosting := in_turbo and turbo > 0.0 and dir != 0.0 and frozen_time <= 0.0 and not flipped
	_boosting = boosting
	if boosting:
		turbo = maxf(0.0, turbo - TURBO_DRAIN * dt)
		_turbo_run += dt
		if _turbo_run >= TURBO_PUTS_OUT_FIRE and burn_time > 0.0: # the rush of air blows the flames out
			burn_time = 0.0
			_burn_fx.emitting = false
			if is_player:
				notice.emit(self, "FIRE OUT")
	else:
		_turbo_run = 0.0
	return boosting


## On the roof or the side and resting there: "flipped". Gas (or reverse) + left/right rolls the
## car back over (owner, round 5); it slides on its roof with real friction meanwhile.
func _upside_watch(dt: float, up: Vector3, state: PhysicsDirectBodyState3D, v: Vector3) -> Vector3:
	var lying := up.y < 0.4 and state.get_contact_count() > 0
	if lying:
		_lying_time += dt
	else:
		_lying_time = 0.0
	if not flipped and _lying_time > 0.3:
		flipped = true
		if is_player:
			notice.emit(self, "FLIPPED!  GAS + LEFT / RIGHT")
		GameFeel.shake(global_position, 0.3)
	elif flipped and up.y > 0.75 and _grounded:
		flipped = false
	_recover_kick -= dt
	if not flipped:
		return v
	if absf(in_throttle) > 0.3 and absf(in_steer) > 0.4 and frozen_time <= 0.0:
		# Turn the roof back toward the sky: about the axis that brings "up" to up (on its side or
		# nose-up against a wall), or a roll the way you steer when it lies flat on its roof.
		var axis := up.cross(Vector3.UP)
		if axis.length() < 0.3:
			axis = -state.transform.basis.z * -signf(in_steer)
		axis = axis.normalized()
		var w := state.angular_velocity
		state.angular_velocity = w + axis * (RECOVER_ROLL - w.dot(axis))
		if _recover_kick <= 0.0 and state.get_contact_count() > 0:
			_recover_kick = 0.5
			v += Vector3.UP * RECOVER_HOP
	return v


func is_on_floor() -> bool:
	return _grounded


func get_floor_normal() -> Vector3:
	return _ground_n


## Mass in physics units (kg-like). `weight` is the design class (1.0 light .. 2.8 super heavy).
func rigid_mass() -> float:
	return weight * 1000.0


## Collisions this step: walls (the owner's slam rule), other cars (rams), breakables.
func _contacts(state: PhysicsDirectBodyState3D) -> void:
	_wall_cooldown -= state.step
	for k in state.get_contact_count():
		var other := state.get_contact_collider_object(k)
		var n := state.get_contact_local_normal(k)
		if other is Vehicle:
			_ram(other as Vehicle, _prev_velocity, n)
		elif other != null and other.has_method("vehicle_contact"):
			# Breakables (stands, glass, palms) shatter and barely slow the car.
			if other.vehicle_contact(self, _prev_velocity):
				state.linear_velocity = Vector3(_prev_velocity.x, state.linear_velocity.y, _prev_velocity.z) * 0.95
			elif absf(n.y) < 0.55:
				_wall_hit(state, n)
		elif absf(n.y) < 0.55:
			_wall_hit(state, n)


## Wall hits (owner, session 6): 55-90 degrees into a wall is a slam (the body stops, a small
## bounce, scraping out along it is slow for a moment, or back away); 30-55 scrapes and loses about a
## third of the speed; flatter slides along losing a little.
func _wall_hit(state: PhysicsDirectBodyState3D, n: Vector3) -> void:
	var hn := Vector3(n.x, 0.0, n.z).normalized()
	_last_wall_normal = hn
	_wall_contact = 0.3
	var moving := Vector3(_prev_velocity.x, 0.0, _prev_velocity.z)
	if _wall_cooldown > 0.0 or moving.length() < 1.5:
		return
	var travel := moving.normalized()
	var into := -travel.dot(hn) # 0 = sliding along the wall, 1 = straight into it
	if into < 0.05:
		return
	_wall_cooldown = 0.25
	var impact := moving.length() * into
	var mass_factor := 0.75 if weight >= 2.0 else (1.25 if weight < 1.2 else 1.0)
	var tangent := travel - hn * travel.dot(hn)
	tangent = tangent.normalized() if tangent.length() > 0.05 else hn.cross(Vector3.UP)
	var lv := state.linear_velocity
	if into >= 0.82: # 55 degrees or more: slam
		var keep := tangent * moving.dot(tangent) * 0.15
		var bounce := hn * minf(2.0 + impact * 0.06, 4.0)
		state.linear_velocity = Vector3(keep.x + bounce.x, lv.y, keep.z + bounce.z)
		_wall_pin = 0.7
		_yaw_fix = 0.0
		wall_slammed.emit(self, impact)
		return
	var loss := 0.3 if into >= 0.5 else 0.08
	var slide := tangent * moving.length() * (1.0 - loss * mass_factor)
	state.linear_velocity = Vector3(slide.x + hn.x * 0.5, lv.y, slide.z + hn.z * 0.5)
	if moving.dot(flat_forward()) < 0.0:
		return # backing into a wall: lose speed, keep the heading
	_yaw_fix = flat_forward().signed_angle_to(tangent, Vector3.UP) * (0.6 if into >= 0.5 else 1.0)


## Stuck helper (design 2.0.1 rule 9): gas held against the world for 4 s without moving gives a
## small push away from the wall. Never against another car.
func _unstick(dt: float) -> void:
	_wall_contact -= dt
	var hspeed := Vector2(linear_velocity.x, linear_velocity.z).length()
	if absf(in_throttle) > 0.5 and _wall_contact > 0.0 and hspeed < 1.0 and frozen_time <= 0.0 and not flipped:
		_stuck_time += dt
		if _stuck_time > 4.0: # only a real trap: normally you steer out or back off
			_stuck_time = 0.0
			linear_velocity += _last_wall_normal * 9.0 + Vector3.UP * 2.0
			_yaw_fix += deg_to_rad(90.0) * (1.0 if randf() < 0.5 else -1.0)
	else:
		_stuck_time = 0.0


## Ram damage (design 1.3): (closing speed - 10) * 0.5 * sqrt(my weight / its weight), max 25,
## once per second per pair. The rammer takes some back unless it is heavier. The bodies bounce off
## each other by themselves now; this adds the damage, the sound and the class knockback.
func _ram(other: Vehicle, before: Vector3, n: Vector3) -> void:
	if other.is_dead:
		return
	var key := other.get_instance_id()
	if _clock - float(_ram_times.get(key, -10.0)) < 1.0:
		return
	var closing := (before - other._prev_velocity).dot(-n)
	if closing < RAM_MIN_CLOSING:
		return
	_ram_times[key] = _clock
	GameFeel.play("ram", (global_position + other.global_position) * 0.5 + Vector3.UP, get_parent(), clampf(-14.0 + closing * 0.8, -14.0, 0.0))
	var ratio := sqrt(weight / other.weight)
	var dmg := minf(RAM_MAX, (closing - RAM_MIN_CLOSING) * 0.5 * ratio)
	other.take_damage(dmg, self)
	var recoil := 0.2
	if weight < other.weight - 0.01:
		recoil = 0.3
	elif weight > other.weight + 0.01:
		recoil = 0.1
	take_damage(dmg * recoil, other)
	# Bodies alone stick together after a hit (little bounce): the ram knocks them apart like before.
	other.push(-n * closing * 0.35 * other.knockback * ratio + Vector3.UP * 2.0)
	push(n * closing * 0.15 * knockback / ratio)


## Knock the car (weapons, rams, recoil): a change of velocity.
func push(dv: Vector3) -> void:
	linear_velocity += dv


## A hit lands (game feel): the body jolts away from it and big hits flash the car white.
func hit_react(dir: Vector3, amount: float) -> void:
	if is_dead:
		return
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length() > 0.01:
		_jolt += global_basis.inverse() * flat.normalized() * clampf(amount * 0.012, 0.05, 0.4)
	if amount >= 4.0:
		if _flash_time <= 0.0:
			if _white == null:
				_white = StandardMaterial3D.new()
				_white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				_white.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				_white.albedo_color = Color(1.0, 0.97, 0.9, 0.6)
			for mi in _flash_meshes:
				if is_instance_valid(mi):
					mi.material_overlay = _white
		_flash_time = maxf(_flash_time, 0.05 + minf(amount, 60.0) / 1200.0)


## A blast throws the car (heavy cars less). flip 1 = about one full roll through the air away from
## the blast, smaller values tip it. Where it lands (wheels, side or roof) is up to the physics.
func blast_knock(push_v: Vector3, flip := 0.0, by_weight := true) -> void:
	var dv := push_v * knockback if by_weight else push_v
	linear_velocity += dv
	if flip <= 0.0 or dv.y < 2.0:
		return
	var air := maxf(0.5, 2.0 * dv.y / GRAVITY)
	var axis := Vector3.UP.cross(Vector3(dv.x, 0.0, dv.z))
	if axis.length() < 0.1:
		axis = global_basis.x
	angular_velocity += axis.normalized() * flip * TAU / air


## Elastic dip from a hit (owner: "squishy reflex", a few degrees, never goofy): the side the hit
## came from goes down, the other side comes up, and it springs back with a little overshoot.
func squish(from_dir: Vector3, amount: float) -> void:
	if is_dead or amount <= 0.0:
		return
	var side := global_basis.inverse() * Vector3(-from_dir.x, 0.0, -from_dir.z)
	side.y = 0.0
	if side.length() < 0.01:
		return
	var axis := Vector3.UP.cross(side.normalized())
	_squish_vel += axis * amount * 18.0


## A homing hit twitches the steering for a moment.
func wobble(seconds := 0.35) -> void:
	_wobble_t = seconds
	_wobble_dir = 1.0 if randf() < 0.5 else -1.0


func flat_forward() -> Vector3:
	var f := -global_transform.basis.z
	f.y = 0.0
	if f.length() < 0.05: # nose straight up or down: use the roof's direction
		f = global_transform.basis.y * (-1.0 if global_transform.basis.z.y > 0.0 else 1.0)
		f.y = 0.0
	return f.normalized() if f.length() > 0.001 else Vector3.FORWARD


func aim_point() -> Vector3:
	return global_position + global_basis.y * 1.0


# ---------------------------------------------------------------- energy

func spend_energy(amount: float) -> bool:
	if energy < amount:
		return false
	energy -= amount
	_energy_pause = ENERGY_PAUSE
	return true


# ---------------------------------------------------------------- combat

func _combat(delta: float) -> void:
	if frozen_time > 0.0 or flipped:
		want_fire_weapon = false
		want_freeze = false
		_cancel_charge()
		return
	if in_fire_guns and _gun_cooldown <= 0.0:
		_gun_cooldown = WeaponData.get_def("guns").cooldown
		_fire_guns()
	if want_fire_weapon:
		want_fire_weapon = false
		if has_live_special() and (_live_weapon == "" or _live_weapon == selected_weapon()):
			_active_special.fire_again() # taser mash, bomb detonation, napalm drop
		elif _can_charge():
			charging_id = selected_weapon() # fires when the button is let go
			if is_player:
				GameFeel.play("charge_up", launch_point(), self, -4.0)
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


## The round shadow sits on the ground under the car, fading as the car rises.
func _place_blob() -> void:
	if not _blob.visible and not GraphicsSettings.high:
		_blob.visible = true
	if not _blob.is_visible_in_tree():
		return
	var from := global_position + Vector3.UP * 1.0
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 30.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		_blob.visible = false
		return
	var n: Vector3 = hit.normal
	var height := from.y - 1.0 - (hit.position as Vector3).y
	var fade := clampf(1.0 - height / 12.0, 0.15, 1.0)
	_blob.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, n)) * Basis(Vector3.UP, rotation.y) * Basis.from_scale(Vector3.ONE * (1.0 + (1.0 - fade) * 0.6)), (hit.position as Vector3) + n * 0.12)
	_blob.transparency = 1.0 - fade


## Engine layers: idle at a standstill, slow through the middle, fast near top speed, each pitched
## with the speed (turbo pushes it up). A rev when the gas goes down from low speed. Cars far from
## the camera go quiet (no streams decoding for nothing).
func _update_engine(delta: float) -> void:
	if _eng.is_empty():
		return
	var r := clampf(absf(speed) / float(stats.max_speed), 0.0, 1.3)
	var near := GameFeel.camera == null or not is_instance_valid(GameFeel.camera) \
		or global_position.distance_squared_to(GameFeel.camera.global_position) < 8100.0
	var weights := {
		"idle": 1.0 - smoothstep(0.04, 0.22, r),
		"slow": smoothstep(0.04, 0.22, r) * (1.0 - smoothstep(0.5, 0.75, r)),
		"fast": smoothstep(0.5, 0.75, r),
	}
	var boost := 0.12 if _boosting else 0.0
	var pitches := {"idle": 1.0, "slow": 0.85 + r * 0.45 + boost, "fast": 0.9 + (r - 0.5) * 0.5 + boost}
	var base := -13.0 if is_player else -9.0
	for layer: String in _eng:
		var p := _eng[layer] as AudioStreamPlayer3D
		var w: float = weights[layer] if near else 0.0
		if w < 0.02:
			if p.playing:
				p.stop()
			continue
		if not p.playing:
			p.play()
		p.volume_db = base + linear_to_db(w)
		p.pitch_scale = lerpf(p.pitch_scale, pitches[layer], 1.0 - exp(-6.0 * delta))
	_rev_cool -= delta
	if near and in_throttle > 0.6 and _prev_throttle < 0.2 and r < 0.35 and _rev_cool <= 0.0:
		_rev_cool = 1.5
		GameFeel.play("engine_%s_rev" % _eng_set, global_position + Vector3.UP, self, base + 2.0)
	_prev_throttle = in_throttle


## Engine pitch follows the speed (turbo pushes it higher), guns loop while firing, tires squeal
## while the car slides sideways or drifts on the handbrake.
func _update_sounds(delta: float) -> void:
	_update_engine(delta)
	if _gun_snd:
		_gun_snd_t -= delta
		if _gun_snd_t > 0.0 and not _gun_snd.playing:
			_gun_snd.play()
		elif _gun_snd_t <= 0.0 and _gun_snd.playing:
			_gun_snd.stop()
			GameFeel.play("guns_stop", global_position + Vector3.UP, self, -9.0) # the barrels spin down
	if _skid_snd:
		var side := absf(velocity.dot(global_basis.x))
		var skid := is_on_floor() and not flipped and (side > 5.0 or (in_handbrake and absf(speed) > 8.0))
		# A screech as a hard slide starts, then the skid loop carries it.
		_screech_t -= delta
		if skid and not _was_skidding and side > 7.0 and _screech_t <= 0.0:
			_screech_t = 1.2
			GameFeel.play("screech", global_position, get_parent(), -8.0)
		_was_skidding = skid
		if skid:
			_skid_snd.volume_db = -18.0 + clampf(side / 14.0, 0.0, 1.0) * 9.0
			if not _skid_snd.playing:
				_skid_snd.play()
		elif _skid_snd.playing:
			_skid_snd.stop()


## The charged shot builds up where everyone can see it: a fireball swelling on the launcher,
## white-hot and pulsing once it is full.
func _update_charge_fx() -> void:
	if charging_id == "":
		if is_instance_valid(_charge_fx):
			_charge_fx.queue_free()
		_charge_fx = null
		return
	if not is_instance_valid(_charge_fx):
		_charge_fx = Node3D.new()
		model.add_child(_charge_fx)
		_charge_fx.position = model.get_meta("launcher", Vector3(0, 2, -2.5))
		var ball := MeshKit.sphere(_charge_fx, 0.25, Vector3.ZERO, MeshKit.emissive(Color(1.0, 0.45, 0.1), 4.0), Vector3.ONE, 10)
		ball.name = "Ball"
		ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var flames := FxKit.fire(0.7, 20)
		_charge_fx.add_child(flames)
		flames.emitting = true
	var r := charge_ratio()
	var ball := _charge_fx.get_node("Ball") as MeshInstance3D
	var pulse := 1.0 + (0.18 * sin(_clock * 30.0) if r >= 1.0 else 0.0)
	ball.scale = Vector3.ONE * (0.5 + r * 2.2) * pulse
	(ball.material_override as StandardMaterial3D).emission = Color(1.0, 0.45, 0.1).lerp(Color(1.0, 0.95, 0.8), r)


## A turbo pickup fills the bar up again (turbo never refills by itself).
func refill_turbo() -> void:
	turbo = 100.0


## A taser link, chain bomb, napalm can or remote bomb that is still out (fire presses go to it).
func has_live_special() -> bool:
	return is_instance_valid(_active_special) and not _active_special.is_queued_for_deletion()


func set_live_special(node: Node, weapon := "") -> void:
	_active_special = node
	_live_weapon = weapon if node else ""
	if node == null:
		_refresh_slots.call_deferred() # detonated / over: an empty weapon leaves the list at once


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
	_gun_snd_t = 0.14 # the loop runs while the guns keep firing
	_shells += 1
	if _shells % 6 == 0:
		GameFeel.play("shell", global_position + Vector3.UP * 0.5, self, -20.0) # casings on the tarmac
	if _gun_snd == null and _gun_index == 0:
		GameFeel.play("guns", from, get_parent(), -6.0)


func _fire_selected(charged := false) -> void:
	if weapon_order.is_empty():
		if is_player:
			GameFeel.ui("not_available", get_tree())
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
	if has_live_special() and _live_weapon == "":
		_live_weapon = id # a taser link or chain bomb: its slot stays until it is over
	_refresh_slots()


## Owner, session 6: an empty weapon leaves the list and comes back when there is ammo again
## (the special too, as it recharges). A weapon still out in the world (mine, napalm can, taser
## link, chain bomb) keeps its slot until it is detonated or over. Keeps the same weapon selected.
func _refresh_slots() -> void:
	var keep := selected_weapon()
	for id: String in weapon_order.duplicate():
		if ammo.get(id, 0) <= 0 and not (has_live_special() and _live_weapon == id):
			weapon_order.erase(id)
			if id != special_id:
				ammo.erase(id)
	if ammo.get(special_id, 0) > 0 and not weapon_order.has(special_id):
		weapon_order.insert(0, special_id)
	var at := weapon_order.find(keep)
	selected = at if at >= 0 else clampi(selected, 0, maxi(weapon_order.size() - 1, 0))
	weapons_changed.emit(self)


## True while the selected weapon is out in the world waiting for a fire press (DETONATE / DROP / MASH).
func selected_is_live() -> bool:
	return has_live_special() and _live_weapon != "" and _live_weapon == selected_weapon()


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
	if is_player:
		GameFeel.ui("weapon_switch", get_tree(), -10.0)


func selected_weapon() -> String:
	if weapon_order.is_empty():
		return ""
	return weapon_order[clampi(selected, 0, weapon_order.size() - 1)]


func add_ammo(id: String, amount: int) -> void:
	if not weapon_order.has(id):
		if id == special_id:
			weapon_order.insert(0, id)
		else:
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
func freeze_for(seconds: float) -> bool:
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
	if burn_time <= 0.0:
		GameFeel.play("ignite", global_position + Vector3.UP, get_parent(), -3.0)
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
	GameFeel.play("death_female" if stats.get("female", false) else "death_male", global_position + Vector3.UP, get_parent())
	for snd: AudioStreamPlayer3D in [_gun_snd, _skid_snd]:
		if snd:
			snd.stop()
	for layer: String in _eng:
		(_eng[layer] as AudioStreamPlayer3D).stop()
	linear_velocity += Vector3(randf_range(-3, 3), 11.0, randf_range(-3, 3))
	angular_velocity += Vector3(randf_range(-1, 1), randf_range(-0.3, 0.3), randf_range(-1, 1)).normalized() * randf_range(2.5, 4.5)
	_charge_fx = null
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


# ---------------------------------------------------------------- visuals

func _animate(delta: float) -> void:
	_fx.update(delta, self, velocity, _boosting, in_handbrake and is_on_floor() and absf(speed) > 8.0)
	_update_sounds(delta)
	if _flash_time > 0.0:
		_flash_time -= delta
		if _flash_time <= 0.0:
			for mi in _flash_meshes:
				if is_instance_valid(mi):
					mi.material_overlay = null
	_jolt = _jolt.lerp(Vector3.ZERO, 1.0 - exp(-12.0 * delta))
	_update_charge_fx()
	_place_blob()
	var spin := speed * delta / _wheel_radius
	for w in _wheels:
		(w as Node3D).rotate_x(-spin)
	for s in _steer_pivots:
		(s as Node3D).rotation.y = lerpf((s as Node3D).rotation.y, -in_steer * 0.45, 12.0 * delta)

	# The body's attitude is the physics now. The visual adds a small lean into turns, the
	# elastic dip from hits (a damped spring) and the jolt; the wheels follow their springs.
	var lean := 0.0
	if _grounded:
		lean = -in_steer * clampf(absf(speed) / stats.max_speed, 0.0, 1.0) * float(model.get_meta("lean", 0.06))
	_lean = lerpf(_lean, lean, clampf(10.0 * delta, 0.0, 1.0))
	_squish_vel += (-220.0 * _squish - 12.0 * _squish_vel) * delta
	_squish += _squish_vel * delta
	var shown := Basis.from_euler(Vector3(0.0, 0.0, _lean))
	if _squish.length() > 0.0005:
		shown = shown * Basis(_squish.normalized(), _squish.length())
	var mid := Vector3(0, float(stats.get("size", Vector3(2, 1.8, 5)).y) * 0.5, 0)
	_visual.transform = Transform3D(shown, mid - shown * mid + _jolt)
	# Wheels drop into their arches as the springs stretch, tuck up as they squash.
	for w: Node3D in _wheels:
		var rest: Vector3 = _wheel_rest.get(w, w.position)
		var corner := (1 if rest.x > 0.01 else 0) + (2 if rest.z > 0.0 else 0) # same order as _wheel_corners()
		var travel := clampf(_wheel_comp[corner] - GRAVITY / SUSP_K, -SUSP_DROOP, 0.25)
		w.position.y = rest.y + travel
