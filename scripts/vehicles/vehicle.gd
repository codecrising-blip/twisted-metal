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
var _air_basis := Basis.IDENTITY # body attitude at takeoff: kept through the air (no fake tilting)
var _visual_base := Basis.IDENTITY # attitude without the hit dip (the slerps run on this)
var _flash_meshes: Array[MeshInstance3D] = [] # flash white when hit
var _flash_time := 0.0
var _jolt := Vector3.ZERO # body knocked off its seat by a hit, springs back
var _charge_fx: Node3D # glow growing on the launcher while a charged shot builds
var _wreck_spin := Vector3.ZERO # a wreck tumbles through the air when it blows
static var _white: StandardMaterial3D
static var _blob_mat: StandardMaterial3D
var _blob: MeshInstance3D # soft round shadow under the car on LOW (TM2 style; real shadows are off there)
var _airborne := false
var _stuck_time := 0.0
var _wreck_time := 0.0
var _active_special: Node # live taser link, chain bomb, napalm can or mine: repeat fire presses go to it
var _live_weapon := "" # the weapon that left it out ("" = any fire press goes to it)
# Attitude (owner, session 6): cars tip off ledges under gravity, spin through the air when thrown,
# can land on their roof, and roll back with handbrake + left/right. Visual only: the collision box
# stays upright, the body turns about its middle.
var flipped := false # on its roof: no driving until rolled back
var _spinning := false # turning through the air (blast, ledge, power missile)
var _spin_axis := Vector3.RIGHT # in the car's own space
var _spin_rate := 0.0
var _spin_angle := 0.0
var _spin_grace := 0.0 # just launched: don't count the ground we are leaving as a landing
var _tip_axis := Vector3.RIGHT
var _tip_angle := 0.0 # hanging over an edge: gravity tips it
var _tip_rate := 0.0
var _hanging := false # some wheels still on an edge while the middle hangs over it
var _edge_y := 0.0 # height of the ground it last stood on (the edge it pivots on)
var _tip_slow := 0.0 # how slowly it went over (1 = from standing): slow cars keep turning as they fall
var _recover := 0.0 # 0..1 rolling back onto the wheels
var _recover_dir := 1.0
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
var _engine_snd: AudioStreamPlayer3D
var _gun_snd: AudioStreamPlayer3D
var _skid_snd: AudioStreamPlayer3D
var _gun_snd_t := 0.0


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
	_engine_snd = GameFeel.loop("engine_" + str(stats.get("class", "medium")), self, -15.0 if player else -11.0, 9.0)
	if _engine_snd:
		_engine_snd.autoplay = true
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
		_wreck_physics(delta)
		return
	if controller:
		controller.drive(self, delta)
	else:
		_clear_inputs()
	_tick(delta)
	_drive(delta)
	_edge_tip(delta)
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


## Driving model: the car's velocity is split into forward and sideways parts. Gas, brake and
## handbrake act on the forward part; tyre grip pulls the sideways part toward zero. So a car that
## brakes while sliding keeps skidding sideways and slows over a short distance instead of stopping
## dead (owner, session 6), and the handbrake (less grip, sharper turn) makes the drifts.
func _drive(delta: float) -> void:
	var frozen := frozen_time > 0.0
	var throttle := 0.0 if (frozen or flipped) else in_throttle
	var steer := 0.0 if (frozen or flipped) else in_steer
	if flipped:
		_recover_input(delta)
	var handbrake := in_handbrake and not frozen
	var on_floor := is_on_floor() and not _spinning # tumbling: the tyres don't hold it
	var brake: float = BRAKE * float(stats.get("brake_mult", 1.0))
	_wall_pin -= delta

	var top: float = stats.max_speed
	# Turbo works forward, in reverse (owner, session 6) and in the air (thrust onto a ledge after a jump).
	var boost_dir := signf(throttle) if absf(throttle) > 0.1 else (0.0 if on_floor else 1.0)
	var boosting := in_turbo and turbo > 0.0 and boost_dir != 0.0 and not frozen
	_boosting = boosting
	if boosting:
		top *= TURBO_MULT
		turbo = maxf(0.0, turbo - TURBO_DRAIN * delta)
		_turbo_run += delta
		if _turbo_run >= TURBO_PUTS_OUT_FIRE and burn_time > 0.0: # the rush of air blows the flames out
			burn_time = 0.0
			_burn_fx.emitting = false
			if is_player:
				notice.emit(self, "FIRE OUT")
	else:
		_turbo_run = 0.0

	# Steering first: needs speed, reverses when backing up, sharper with the handbrake.
	var authority := clampf(absf(speed) / 7.0, 0.0, 1.0)
	if not on_floor:
		authority *= 0.25
	var turn: float = stats.handling * (float(stats.drift_turn) if handbrake else 1.0)
	turn *= lerpf(1.0, 0.78, clampf(absf(speed) / float(stats.max_speed), 0.0, 1.0)) # wider turns when fast
	var dir := 1.0 if speed >= 0.0 else -1.0
	rotate_y(-steer * turn * authority * dir * delta)
	if _wobble_t > 0.0: # a homing hit knocks the steering a little
		_wobble_t -= delta
		rotate_y(_wobble_dir * 1.3 * delta)
	if absf(_yaw_fix) > 0.001: # a glancing wall hit turns the car along the wall over a few frames
		var step := _yaw_fix * minf(1.0, 14.0 * delta)
		rotate_y(step)
		_yaw_fix -= step

	var forward := flat_forward()
	var right := Vector3(-forward.z, 0.0, forward.x)
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var v_f := hv.dot(forward)
	var v_l := hv.dot(right)
	if absf(speed - _speed_out) > 0.01:
		v_f = speed # someone set the speed directly (spawn, tests, a ram): take it as the new forward speed

	if on_floor:
		var sliding := clampf(absf(v_l) / 10.0, 0.0, 1.0) # tyres busy holding a slide brake less
		var accel: float = stats.accel * (TURBO_ACCEL if boosting else 1.0)
		var braking := false
		if throttle > 0.05:
			if v_f < -0.5:
				v_f = move_toward(v_f, 0.0, brake * delta)
				braking = true
			else:
				v_f = move_toward(v_f, top * throttle, accel * delta)
		elif throttle < -0.05:
			if v_f > 0.5:
				v_f = move_toward(v_f, 0.0, brake * (1.0 - 0.45 * sliding) * delta)
				braking = true
			else:
				v_f = move_toward(v_f, -float(stats.reverse) * -throttle * (2.0 if boosting else 1.0), accel * 0.7 * delta)
		else:
			v_f = move_toward(v_f, 0.0, COAST * delta)
		if handbrake:
			v_f = move_toward(v_f, 0.0, HANDBRAKE_DECEL * delta)
		if frozen:
			v_f = move_toward(v_f, 0.0, 60.0 * delta)
		if flipped: # sliding on the roof
			v_f = move_toward(v_f, 0.0, 16.0 * delta)
			v_l = move_toward(v_l, 0.0, 16.0 * delta)
		if v_f > top:
			v_f = move_toward(v_f, top, 12.0 * delta)
		if _wall_pin > 0.0 and forward.dot(-_last_wall_normal) > 0.3:
			v_f = minf(v_f, 4.0) # nose against the wall: scraping out is slow
		# Sideways: grip pulls the slide back in. Handbrake or locked brakes in a slide grip less.
		var grip: float = stats.grip * (float(stats.drift_grip) if handbrake else 1.0)
		if braking and absf(v_l) > 3.0:
			grip *= 0.55
		v_l *= exp(-grip * delta)
	else:
		v_l *= exp(-0.3 * delta) # in the air: momentum carries on
		if boosting:
			var air_top: float = top if boost_dir > 0.0 else float(stats.reverse) * 2.0
			v_f = move_toward(v_f, air_top * boost_dir, TURBO_AIR_THRUST * delta)
	speed = v_f
	_speed_out = speed
	hv = forward * v_f + right * v_l
	velocity.x = hv.x
	velocity.z = hv.z
	velocity.y -= GRAVITY * delta

	if want_jump:
		want_jump = false
		if on_floor and not frozen and not flipped and spend_energy(JUMP_COST):
			velocity.y = JUMP_VELOCITY

	var before := velocity
	move_and_slide()
	_resolve_collisions(before)
	_unstick(delta, throttle)
	_speed_out = speed


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
				_wall_hit(n, before)
		elif absf(n.y) < 0.55:
			_wall_hit(n, before)


## Wall hits (owner, session 6, replacing the old "never stop" rule):
##   55-90 degrees into the wall: a slam. The car stops against it with a small bounce; steering out
##     along the wall is slow (heavy friction) for a moment, or back away from it.
##   30-55 degrees: it scrapes along the wall, losing about a third of its speed.
##   under 30 degrees: it slides along, losing a little.
func _wall_hit(n: Vector3, before: Vector3) -> void:
	var hn := Vector3(n.x, 0.0, n.z).normalized()
	_last_wall_normal = hn
	_wall_contact = 0.3
	var moving := Vector3(before.x, 0.0, before.z)
	if _wall_cooldown > 0.0 or moving.length() < 1.5:
		return
	var travel := moving.normalized()
	var into := -travel.dot(hn) # 0 = sliding along the wall, 1 = straight into it
	if into < 0.05:
		return
	_wall_cooldown = 0.25
	var impact := moving.length() * into
	var mass_factor := 0.75 if mass >= 2.0 else (1.25 if mass < 1.2 else 1.0)
	var tangent := travel - hn * travel.dot(hn)
	tangent = tangent.normalized() if tangent.length() > 0.05 else hn.cross(Vector3.UP)
	if into >= 0.82: # 55 degrees or more: slam
		var keep := tangent * moving.dot(tangent) * 0.15
		velocity.x = keep.x + hn.x * minf(2.0 + impact * 0.06, 4.0)
		velocity.z = keep.z + hn.z * minf(2.0 + impact * 0.06, 4.0)
		speed = velocity.dot(flat_forward())
		_wall_pin = 0.7
		_yaw_fix = 0.0
		wall_slammed.emit(self, impact)
		return
	var loss := 0.3 if into >= 0.5 else 0.08
	var kept := moving.length() * (1.0 - loss * mass_factor)
	var slide := tangent * kept
	velocity.x = slide.x + hn.x * 0.5
	velocity.z = slide.z + hn.z * 0.5
	speed *= 1.0 - loss * mass_factor
	if speed < 0.0:
		return # backing into a wall: lose speed, keep the heading
	var fwd := flat_forward()
	_yaw_fix = fwd.signed_angle_to(tangent, Vector3.UP) * (0.6 if into >= 0.5 else 1.0)


## Stuck helper (design 2.0.1 rule 9): pressing the gas for 2 s against the world without moving
## gives a small push away from the wall. Never against another car.
func _unstick(delta: float, throttle: float) -> void:
	var hspeed := Vector2(velocity.x, velocity.z).length()
	if absf(throttle) > 0.5 and _wall_contact > 0.0 and hspeed < 1.0 and frozen_time <= 0.0:
		_stuck_time += delta
		if _stuck_time > 4.0: # only a real trap: normally you steer out or back off
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
	GameFeel.play("ram", (global_position + other.global_position) * 0.5 + Vector3.UP, get_parent(), clampf(-14.0 + closing * 0.8, -14.0, 0.0))
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


## A blast throws the car (heavy cars less). flip 1 = one full roll through the air away from the
## blast, small values only tilt it; the body lands back on its wheels.
func blast_knock(push: Vector3, flip := 0.0, by_weight := true) -> void:
	var v := push * knockback if by_weight else push
	velocity += v
	if flip <= 0.0 or v.y < 2.0:
		return
	var air := maxf(0.5, 2.0 * v.y / GRAVITY)
	var axis := Vector3.UP.cross(Vector3(v.x, 0.0, v.z))
	if axis.length() < 0.1:
		axis = global_basis.x
	_start_spin((global_basis.inverse() * axis.normalized()).normalized(), 0.0, flip * TAU / air)


func _start_spin(axis: Vector3, angle: float, rate: float) -> void:
	_spinning = true
	_spin_axis = axis
	_spin_angle = angle
	_spin_rate = rate
	_spin_grace = 0.15
	_tip_angle = 0.0
	_tip_rate = 0.0


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


## Hanging over a ledge: when the middle of the car has no ground under it but some wheels do,
## gravity tips it over the edge and pulls it off, nose or side first.
func _edge_tip(delta: float) -> void:
	_hanging = false
	if _spinning:
		return
	var grounded := is_on_floor()
	if grounded and get_floor_normal().y < 0.7:
		return
	if _ground_under(Vector3.ZERO):
		_edge_y = global_position.y
		_tip_rate = 0.0
		_tip_angle = move_toward(_tip_angle, 0.0, 3.0 * delta) # back on solid ground
		return
	var size: Vector3 = stats.get("size", Vector3(2.2, 1.8, 5.0))
	var hx := size.x * 0.42
	var hz := size.z * 0.42
	var away := Vector3.ZERO
	var hanging := 0
	for c: Vector3 in [Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(-hx, 0, hz), Vector3(hx, 0, hz)]:
		if not _ground_under(c):
			away += c
			hanging += 1
	if hanging == 0:
		return # a hole under the middle
	if hanging == 4:
		if not grounded or _tip_angle <= 0.0:
			return # clear of the edge
		away = Vector3.UP.cross(_tip_axis) * -1.0 # still resting on the edge by its back: keep tipping
	away.y = 0.0
	away = away.normalized()
	_hanging = true
	var out := global_basis * away
	out.y = 0.0
	out = out.normalized()
	if flipped: # on its roof but balanced on the edge: it slides off
		global_position += out * 8.0 * delta
		return
	# The middle hangs over the drop, some wheels still on the edge: the car pivots on the edge and
	# tips (a slow car tips right over; a fast one is gone before gravity has much time).
	var slow := clampf(1.0 - absf(speed) / 15.0, 0.1, 1.0)
	_tip_slow = slow
	_tip_axis = Vector3.UP.cross(away).normalized()
	_tip_rate += 7.0 * slow * delta
	_tip_angle += _tip_rate * delta
	if slow > 0.45 and velocity.y < 0.0:
		velocity.y = 0.0 # held up by the wheels still on the edge while it pivots
		global_position.y = maxf(global_position.y, _edge_y - 0.05)
	global_position += out * (0.4 + _tip_rate * 1.5) * delta
	if _tip_angle > 0.9: # past the tipping point: it goes over and keeps turning as it falls
		velocity += out * 5.0 + Vector3.DOWN * 2.0
		_start_spin(_tip_axis, _tip_angle, maxf(_tip_rate, 2.5))
		_spin_grace = 0.6


## Ground within `depth` below this point of the car? Tipping only counts real drops (a ledge of
## a metre or more), not kerbs, ramp sides or bumps.
func _ground_under(local: Vector3, depth := 1.0) -> bool:
	var from := global_transform * (local + Vector3.UP * 0.8)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * (1.0 + depth), 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return not hit.is_empty() and (hit.position as Vector3).y > global_position.y - depth


## On its roof: hold the handbrake and steer left or right to roll back onto the wheels.
func _recover_input(delta: float) -> void:
	if in_handbrake and absf(in_steer) > 0.4:
		if _recover <= 0.0:
			_recover_dir = signf(in_steer)
		_recover += delta / 0.6
		if _recover >= 1.0:
			flipped = false
			_recover = 0.0
			if is_on_floor():
				velocity.y = 4.0
	else:
		_recover = maxf(0.0, _recover - delta * 2.0)


func _land_from_spin() -> void:
	_spinning = false
	var a := fposmod(_spin_angle, TAU)
	if a > PI * 0.55 and a < PI * 1.45:
		flipped = true # came down on its roof
		_recover = 0.0
		speed *= 0.4
		if is_player:
			notice.emit(self, "FLIPPED!  HANDBRAKE + LEFT / RIGHT")
		GameFeel.shake(global_position, 0.35)


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


## Engine pitch follows the speed (turbo pushes it higher), guns loop while firing, tires squeal
## while the car slides sideways or drifts on the handbrake.
func _update_sounds(delta: float) -> void:
	if _engine_snd:
		var r := clampf(absf(speed) / float(stats.max_speed), 0.0, 1.4)
		var want := 0.75 + r * 0.55 + (0.15 if _boosting else 0.0)
		_engine_snd.pitch_scale = lerpf(_engine_snd.pitch_scale, want, 1.0 - exp(-5.0 * delta))
	if _gun_snd:
		_gun_snd_t -= delta
		if _gun_snd_t > 0.0 and not _gun_snd.playing:
			_gun_snd.play()
		elif _gun_snd_t <= 0.0 and _gun_snd.playing:
			_gun_snd.stop()
	if _skid_snd:
		var side := absf(velocity.dot(global_basis.x))
		var skid := is_on_floor() and not flipped and (side > 5.0 or (in_handbrake and absf(speed) > 8.0))
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
	for snd: AudioStreamPlayer3D in [_engine_snd, _gun_snd, _skid_snd]:
		if snd:
			snd.stop()
	velocity += Vector3(randf_range(-3, 3), 11.0, randf_range(-3, 3))
	_wreck_spin = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * randf_range(2.5, 4.5)
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


func _wreck_physics(delta: float) -> void:
	_wreck_time += delta
	if not is_on_floor() and _wreck_spin.length() > 0.1: # the shell tumbles until it hits the ground
		_visual.rotate_object_local(_wreck_spin.normalized(), _wreck_spin.length() * delta)
	elif is_on_floor():
		_wreck_spin = Vector3.ZERO
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

	# Attitude. On the ground: lean into the slope, roll a little in turns. In the air: keep the
	# takeoff attitude (no fake tilting). Thrown or tipped off an edge: spin until landing, maybe
	# onto the roof. On the roof: upside down until rolled back. A hit adds an elastic dip.
	var grounded := is_on_floor()
	var b := _visual_base
	if flipped:
		var roll := PI * (1.0 - _recover) * _recover_dir
		b = Basis(Vector3.FORWARD, roll if _recover > 0.0 else PI)
	elif _spinning:
		_spin_grace -= delta
		_spin_angle += _spin_rate * delta
		b = Basis(_spin_axis, _spin_angle)
		_airborne = true
		_air_basis = Basis.IDENTITY
		if grounded and _spin_grace <= 0.0 and (get_floor_normal().y > 0.75 or absf(velocity.y) < 1.0): # landed (not sliding down a cliff face)
			_land_from_spin()
	elif _tip_angle > 0.02:
		if not grounded and not _hanging: # tipped clean off the edge: keep turning through the fall
			_start_spin(_tip_axis, _tip_angle, maxf(_tip_rate, 3.2 * _tip_slow))
		b = Basis(_tip_axis, _tip_angle)
	elif not grounded:
		if not _airborne:
			_airborne = true
			_air_basis = _visual_base
		b = _visual_base.slerp(_air_basis, clampf(10.0 * delta, 0.0, 1.0))
	else:
		_airborne = false
		var up := global_transform.basis.inverse() * get_floor_normal()
		var lean := -in_steer * clampf(absf(speed) / stats.max_speed, 0.0, 1.0) * float(model.get_meta("lean", 0.06))
		var target_basis := Basis(Quaternion(Vector3.UP, up.normalized())) * Basis.from_euler(Vector3(0.0, 0, lean))
		b = _visual_base.slerp(target_basis.orthonormalized(), clampf(10.0 * delta, 0.0, 1.0))
	# Elastic dip: a damped spring, springs back with a little overshoot.
	_squish_vel += (-220.0 * _squish - 12.0 * _squish_vel) * delta
	_squish += _squish_vel * delta
	b = b.orthonormalized()
	_visual_base = b
	var shown := b
	if _squish.length() > 0.0005:
		shown = b * Basis(_squish.normalized(), _squish.length())
	# Turn about the middle of the body, not the wheels, so a car on its roof lies on its roof.
	var mid := Vector3(0, float(stats.get("size", Vector3(2, 1.8, 5)).y) * 0.5, 0)
	_visual.transform = Transform3D(shown, mid - shown * mid + _jolt)
