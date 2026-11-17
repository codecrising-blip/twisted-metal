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
## Round 9 (owner: "the build-up is so slow"): the moment turbo kicks in it shoves the car on by
## TURBO_KICK m/s, then pulls extra hard (TURBO_LAUNCH x the normal pick-up, fading over TURBO_LAUNCH_TIME).
## Same shove backwards for reverse turbo.
const TURBO_KICK := 7.0
const TURBO_LAUNCH := 2.4
const TURBO_LAUNCH_TIME := 0.6
const TURBO_KICK_COST := 6.0 # of 100: tapping turbo again and again is no free speed
const TURBO_KICK_REST := 0.35 # seconds off turbo before the next shove
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
const AIR_YAW_RESPONSE := 7.0 # rad/s^2: how fast air steering reaches its turn rate (Roster.air_turn)
var _air_steer_w := 0.0 # the yaw rate air steering has added this flight
const BODY_CLEARANCE := 0.3 # the collision box starts this high: wheels hold it, the box takes the hard knocks
const SUSP_BUMP := 0.3 # compression where the bump stop starts (rest is GRAVITY / SUSP_K = 0.16)
const SUSP_BUMP_STIFF := 7.0 # bump stop: this many times the spring rate on top
const YAW_RESPONSE := 40.0 # rad/s^2: steering reaches its turn rate in a blink, a hit can still swing it
# U-turn slides (round 11, profiles in Roster.UTURN).
const SLIDE_MIN_SPEED := 0.5 # share of top speed needed to start one
const SLIDE_TAP_WINDOW := 0.45 # s: a re-press of the handbrake this soon is a tap (heavy cars)
const SLIDE_TAP_GAIN := 25.0 # degrees each tap buys
const SLIDE_TAP_LOSS := 0.15 # share of speed each tap costs
const RECOVER_ROLL := 7.0 # rad/s roll when gas + left/right rights a flipped car
const WALL_DAMAGE := 0.3 # per m/s of impact over 10: a 25 m/s square slam costs about 4.5
const CHARGE_SILENT := 0.25 # a tap shorter than this makes no charging sound
const KNOCK_TIME := 0.6 # after a blast the tyres let the car fly instead of gripping it back in line
const RECOVER_HOP := 5.5 # m/s lift as the roll starts (again every half second until it is back up)
const FREEZE_COST := 50.0
# Energy moves (design 5.2, owner's combos play-test 1).
const REAR_FREEZE_COST := 40.0
const SHIELD_COST := 70.0
const LAST_LAUGH_AT := 0.3 # Sweet Tooth's perk: below this share of health...
const LAST_LAUGH_RATE := 1.5 # ...the special recharges this much faster
var _last_laugh := false
const SHIELD_TIME := 2.5
const INVIS_COST := 50.0
const INVIS_TIME := 6.0
const CLOAK_IN := 0.8 # round 16 (owner, TM2): sparks for 0.8 s, then gone (before the 6 s)
const CLOAK_OUT := 0.45 # sparks and fade coming back
const MINE_COST := 25.0
const REAR_ATTACK_COST := 30.0
const HEADLIGHT_RANGE := 45.0
const HEADLIGHT_CONE := deg_to_rad(26.0)
const FREEZE_BREAK := 15.0 # a single hit this big shatters the ice
const GRIT_TIME := 3.0 # immune to full disables after one ends
const SPAWN_SHIELD := 2.0
const PYRE_TIME := 3.0 # the fire where the car blew apart burns full this long, then dies down
const RAM_MIN_CLOSING := 8.0
const RAM_PER_MS := 0.9
const RAM_MAX := 45.0
const RAM_THROW_MAX := 22.0 # m/s: the most a ram throws the car it hits (light cars get more via knockback)
const RAM_ATTACK := {"front": 1.0, "side": 0.3, "rear": 0.3}
const RAM_DEFENSE := {"front": 1.0, "side": 1.6, "rear": 1.3}
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
var want_move := "" # an energy move by name (combos, number keys, AI): see energy_move()

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
var special_charges := 4 # the most specials this car can hold (Roster.special_max)
var charging_id := "" # weapon being charged while the fire button is held (Napalm Cone)
var charge_time := 0.0

var model: Node3D
var _visual: Node3D
var _fx: VehicleFx
var _boosting := false
var _slide := false # a U-turn slide is on (Roster.UTURN)
var _slide_turned := 0.0 # radians turned since it began
var _slide_limit := 0.0
var _slide_dir := 0.0
var _slide_off := 0.0 # seconds since the handbrake was let go
var _hb_was := false
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
static var _ram_pairs := {} # "id:id" -> time of the last ram between those two cars
var last_ram := {} # the last ram this car was in (parts and damage): tests and HUD
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
var shield_time := 0.0 # energy shield up: no damage, no states; guns only
var invisible_time := 0.0 # energy invisibility: no locks on you, AI loses you past 12 m
var revealed_time := 0.0 # seen anyway for a moment: hit, or caught in headlights
var headlights_on := false
var _energy_mines: Array = []
var _shield_mat: ShaderMaterial # round 17: a forest-green force-field shell hovering round the whole car
var _shield_flare := 0.0 # a hit brightens the whole field for a moment
var _shield_hit_age := 9.0 # seconds since the field last blocked a hit (the hot patch fades)
var _shield_spark_cd := 0.0 # sparks at most this often (a gatling burst would bury the car)
const SHIELD_SHADER := preload("res://scripts/fx/shield_field.gdshader")
const SHIELD_BLINK := 0.6 # it blinks for this long before it ends (owner, round 17)
var _cloak: CloakFx # round 16: TM2 sparks going invisible and coming back
var _was_invisible := false
var _cloak_back := 0.0 # coming back into sight (seconds left)
var _shield_hum: AudioStreamPlayer3D
var _headlight_t := 0.0
var _turbo_kick := false # this step is the shove at the start of a boost
var _turbo_rest := 1.0 # seconds since the last boost ended
var _air_t := 0.0 # time in the air this flight
var _air_vy := 0.0 # fastest fall this flight (negative)
var _invis_shown := -1.0 # last transparency written to the meshes
var _charge_beeps := 0
var _charge_hold := 0.0 # seconds the fire button has been held on this charge
var _locked := {} # weapon id -> seconds left of a meltdown lock
var _charge_hum: AudioStreamPlayer3D
var _charge_hum_t := 0.0
var _knock := 0.0 # seconds left of "thrown": tyres barely grip, so blasts carry the car sideways
var _wheel_rest: Dictionary = {} # wheel node -> its resting position
var _lean := 0.0
var _squish := Vector3.ZERO # elastic dip from a hit (rotation vector, car space)
var _squish_vel := Vector3.ZERO
var _wobble_t := 0.0 # homing hit: the steering twitches
var _wobble_dir := 1.0
var _smoke: CPUParticles3D
var _fire: FoamFire # badly damaged: a smaller fire on the engine cover
var _burn_fx: FoamFire # set on fire: the engine cover burns, streaming back as it drives (round 18)
var _pyre: FoamFire # blown apart: the heap of fire left on the ground, then dying down
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
	# Round 12 (owner): every life starts with 2 specials; held unused they build up to the car's max.
	special_charges = Roster.special_max(id)
	ammo[special_id] = mini(Roster.SPECIAL_START, special_charges)
	weapon_order = [special_id]

	collision_layer = 2
	collision_mask = 1 | 2 | 16 # world, cars, the invisible wall over the stage's fence
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

	# The body: a box with its front and back bottom edges cut off like a sled (round 7). A plain box's bottom edge
	# caught on slopes and curved ground (hill sides, the crater, ramp feet); the contact pushed
	# straight back like a wall and stopped the car dead: the owner's "invisible walls". The cut
	# faces lean 45 degrees, so the ground pushes the nose up and over instead.
	var shape := CollisionShape3D.new()
	var hull := ConvexPolygonShape3D.new()
	var hw := size.x * 0.5
	var hl := size.z * 0.5
	var bottom := BODY_CLEARANCE
	var roof := size.y
	var cut := minf(0.45, (roof - bottom) * 0.4) # how high the chamfers reach
	var pts := PackedVector3Array()
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			pts.append(Vector3(sx * hw, roof, sz * hl))
			pts.append(Vector3(sx * hw, bottom + cut, sz * hl))
			# Only the front and back edges are cut: chamfered sides rode up over the low rails of
			# the ramps and slid off them.
			pts.append(Vector3(sx * hw, bottom, sz * (hl - cut)))
	hull.points = pts
	shape.shape = hull
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
	_cloak = CloakFx.new()
	_cloak.car = self
	_cloak.size = stats.get("size", Vector3(2.2, 1.8, 5.0))
	add_child(_cloak)
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
	# The game's fire (round 18, the owner's pick): FoamFire, only on the engine cover, never over the
	# whole car or inside it; it streams back and swings through turns on its own.
	_fire = FoamFire.on_hood(_visual, stats) # badly damaged: smaller, lazier
	_fire.level = 0.55
	_burn_fx = FoamFire.on_hood(_visual, stats) # set on fire
	_pyre = FoamFire.pyre(_visual, size) # blown apart: the heap of fire left where it stood

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
	_sat_preview_step()
	if is_dead:
		_wreck_time += delta
		if _wreck_time > PYRE_TIME and _pyre.on:
			_pyre.on = false # the pyre burns down (owner's TMB clips: ~3 s full, then it shrinks away)
		return
	if controller:
		controller.drive(self, delta)
	else:
		_clear_inputs()
	_tick(delta)
	_combat(delta)
	_animate(delta)


## Owner, round 9: with SAT selected, its zone shows ahead of the car in dim yellow, for every car:
## a threat the enemy can see, and a way to judge the distance before launching. Hidden while a
## strike of this car is on its way, while invisible, and once the car is dead.
var _sat_preview: SatMarker


func _sat_preview_step() -> void:
	var want := not is_dead and not is_hidden() and selected_weapon() == "sat" and not SatStrike.busy(self)
	if not want:
		if _sat_preview:
			_sat_preview.queue_free()
			_sat_preview = null
		return
	var d := WeaponData.get_def("sat")
	if _sat_preview == null:
		_sat_preview = SatMarker.make(get_parent(), float(d.get("radius", 7.5)))
		_sat_preview.spin_speed = 0.3
		_sat_preview.set_tint(SatMarker.YELLOW, 0.45, 0.0)
		_sat_preview.global_position = SatStrike.zone_point(self, d)
	_sat_preview.global_position = _sat_preview.global_position.lerp(SatStrike.zone_point(self, d), 0.35)


func _exit_tree() -> void:
	if _sat_preview:
		_sat_preview.queue_free()
		_sat_preview = null


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
	for id in _locked.keys():
		_locked[id] -= delta
		if _locked[id] <= 0.0:
			_locked.erase(id)
	if _energy_pause > 0.0:
		_energy_pause -= delta
	else:
		energy = minf(100.0, energy + ENERGY_REGEN * delta)
	if invulnerable_time > 0.0:
		invulnerable_time -= delta
		_visual.visible = invulnerable_time <= 0.0 or fmod(invulnerable_time, 0.2) > 0.08
	if grit_time > 0.0:
		grit_time -= delta
	_energy_tick(delta)
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
			_burn_fx.on = false
	# Specials recharge one charge at a time; the slot comes back with the first one.
	var laughing: bool = stats.get("last_laugh", false) and health < max_health * LAST_LAUGH_AT and not is_dead
	if laughing != _last_laugh:
		_last_laugh = laughing
		BlenderCars.cone_fire_blue(model, laughing)
	if ammo.get(special_id, 0) < special_charges:
		_special_timer += delta * (LAST_LAUGH_RATE if laughing else 1.0)
		if _special_timer >= Roster.special_recharge(car_id):
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
				# Bump stop (round 9, owner: "struggles on the hill"): near full travel the spring
				# stiffens hard, so the body doesn't drag its belly up a hill or a ramp at speed.
				var bump := maxf(0.0, comp - SUSP_BUMP) * k * SUSP_BUMP_STIFF
				var f := maxf(0.0, k * comp + bump - c * point_vel.dot(up))
				state.apply_force(up * f, (hit.position as Vector3) - xf.origin)
		_wheel_comp[i] = comp
		i += 1
	_knock -= dt
	var upright := up.y > 0.45
	_grounded = touching >= 2 and upright
	# Landing (juice guide, speed): after a real flight a thump, a ring of dust and the body dips.
	if not _grounded:
		_air_t += dt
		_air_vy = minf(_air_vy, v.y)
	else:
		if _air_t > 0.35 and _air_vy < -7.0:
			call_deferred("_landed", -_air_vy)
		_air_t = 0.0
		_air_vy = 0.0
	_ground_n = (normal_sum / maxf(1.0, touching)).normalized() if touching > 0 else Vector3.UP
	v = _upside_watch(dt, up, state, v)
	if _grounded:
		_air_steer_w = 0.0
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
	var launch := 1.0 + (TURBO_LAUNCH - 1.0) * clampf(1.0 - _turbo_run / TURBO_LAUNCH_TIME, 0.0, 1.0)
	var accel: float = stats.accel * (TURBO_ACCEL * launch if boosting else 1.0)
	if _turbo_kick: # the first step of a boost: the shove
		var rev_top := minf(float(stats.reverse) * 2.0, float(stats.max_speed) * TURBO_MULT)
		v_f = clampf(v_f + TURBO_KICK * signf(throttle), -rev_top, top)
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
			var rev_top := minf(float(stats.reverse) * 2.0, float(stats.max_speed) * TURBO_MULT) if boosting else float(stats.reverse)
			v_f = move_toward(v_f, -rev_top * -throttle, accel * Roster.REVERSE_ACCEL * dt)
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
	var slide_turn := _slide_step(handbrake, steer, (v - n * v_n).length(), boosting, dt)
	if slide_turn and _slide_tapped:
		_slide_tapped = false
		v_f *= 1.0 - SLIDE_TAP_LOSS
		v_l *= 1.0 - SLIDE_TAP_LOSS
	var grip: float = stats.grip * (float(stats.drift_grip) if handbrake else 1.0)
	if braking and absf(v_l) > 3.0:
		grip *= 0.55
	if _knock > 0.0:
		grip *= 0.08 # thrown by a blast: the tyres skate, the car goes where it was pushed
	v_l *= exp(-grip * dt)
	# Steering turns the car about the ground's normal; a hit can still knock it round for a moment.
	# In a U-turn slide the car keeps turning past sideways (the speed it carries, not its forward
	# part, gives the tyres their bite, and the steering doesn't flip when it faces backwards), up to
	# its class limit; it eases onto the limit and holds the heading there.
	var plane_speed := (v - n * v_n).length()
	var authority := clampf((plane_speed if slide_turn else absf(v_f)) / 7.0, 0.0, 1.0)
	var turn: float = stats.handling * (float(stats.drift_turn) if handbrake else 1.0)
	turn *= lerpf(1.0, 0.78, clampf(absf(v_f) / float(stats.max_speed), 0.0, 1.0)) # wider turns when fast
	var yaw := -steer * turn * authority * (1.0 if (v_f >= 0.0 or slide_turn) else -1.0)
	var w_now := state.angular_velocity.dot(n)
	if slide_turn:
		var prof := Roster.uturn(stats)
		if boosting:
			yaw *= float(prof.turbo_rate)
		var left := maxf(0.0, _slide_limit - _slide_turned)
		var cap := sqrt(2.0 * YAW_RESPONSE * left) # slow down to land on the limit
		yaw = clampf(yaw, -cap, cap)
		_slide_turned += absf(w_now) * dt
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


var _slide_tapped := false

## U-turn slide bookkeeping (owner, round 11). True while the slide is turning the car this step.
## Starts on a handbrake press at speed with a direction held; a quick re-press (heavy cars) buys
## more turn for some speed; boosting extends it for the classes that allow it; it ends when the
## handbrake stays off, the car slows right down, or the steering goes the other way.
func _slide_step(handbrake: bool, steer: float, plane_speed: float, boosting: bool, dt: float) -> bool:
	var prof := Roster.uturn(stats)
	if handbrake and not _hb_was:
		if _slide and _slide_off < SLIDE_TAP_WINDOW and bool(prof.taps) and plane_speed > 5.0:
			_slide_limit = minf(_slide_limit + deg_to_rad(SLIDE_TAP_GAIN), PI)
			_slide_tapped = true
		elif plane_speed >= SLIDE_MIN_SPEED * float(stats.max_speed) and absf(steer) > 0.4:
			_slide = true
			_slide_turned = 0.0
			_slide_limit = deg_to_rad(float(prof.max))
			_slide_dir = signf(steer)
	_hb_was = handbrake
	if not _slide:
		return false
	if handbrake:
		_slide_off = 0.0
	else:
		_slide_off += dt
		if _slide_off >= SLIDE_TAP_WINDOW:
			_slide = false
	if plane_speed < 2.5 or (absf(steer) > 0.4 and signf(steer) != _slide_dir):
		_slide = false
	if _slide and boosting and float(prof.turbo_to) > 0.0:
		_slide_limit = maxf(_slide_limit, deg_to_rad(float(prof.turbo_to)))
	return _slide and handbrake


## Degrees turned in the current U-turn slide (tests, HUD).
func slide_degrees() -> float:
	return rad_to_deg(_slide_turned) if _slide else 0.0


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
	# Round 13 (owner: "near zero control after the jump"): steering turns the car in the air, light
	# cars quickly, heavy ones a little; the flight bends a share of that turn, and turbo then drives
	# the car the way it now faces. Pitch and roll keep their takeoff attitude.
	var air := Roster.air_turn(stats)
	var steer := in_steer if frozen_time <= 0.0 else 0.0
	var w := state.angular_velocity
	var wy := w.dot(Vector3.UP)
	var new_wy := wy
	if absf(steer) > 0.05:
		new_wy = move_toward(wy, -steer * float(air.rate), AIR_YAW_RESPONSE * dt)
		hv = hv.rotated(Vector3.UP, new_wy * dt * float(air.carry))
	elif _air_steer_w != 0.0: # let go: only the turn the stick added eases out (hit spins stay)
		var eased := move_toward(_air_steer_w, 0.0, AIR_YAW_RESPONSE * dt)
		new_wy = wy + (eased - _air_steer_w)
	_air_steer_w += new_wy - wy
	state.angular_velocity = w + Vector3.UP * (new_wy - wy)
	if _turbo_step(dir, dt):
		var air_top: float = float(stats.max_speed) * TURBO_MULT if dir > 0.0 else minf(float(stats.reverse) * 2.0, float(stats.max_speed) * TURBO_MULT)
		var along := hv.dot(forward)
		var thrust := TURBO_AIR_THRUST * (1.0 + (TURBO_LAUNCH - 1.0) * clampf(1.0 - _turbo_run / TURBO_LAUNCH_TIME, 0.0, 1.0))
		if _turbo_kick:
			along = clampf(along + TURBO_KICK * dir, -air_top, air_top) # the shove works in the air too
		var target := move_toward(along, air_top * dir, thrust * dt)
		hv += forward * (target - along)
	hv -= Vector3(v.x, 0.0, v.z) - Vector3(v.x, 0.0, v.z) * exp(-0.05 * dt)
	return Vector3(hv.x, v.y, hv.z)


## Turbo bookkeeping for this step: burns the tank, blows out fire. True while boosting.
func _turbo_step(dir: float, dt: float) -> bool:
	var boosting := in_turbo and turbo > 0.0 and dir != 0.0 and frozen_time <= 0.0 and not flipped
	_boosting = boosting
	_turbo_kick = false
	if boosting:
		if _turbo_run == 0.0 and _turbo_rest >= TURBO_KICK_REST: # a fresh boost: the shove (costs a little)
			_turbo_kick = true
			turbo = maxf(0.0, turbo - TURBO_KICK_COST / float(stats.get("turbo_tank", 1.0)))
			if is_player:
				GameFeel.shake(global_position, 0.12)
		turbo = maxf(0.0, turbo - TURBO_DRAIN / float(stats.get("turbo_tank", 1.0)) * dt) # Outlaw's tank is bigger
		_turbo_run += dt
		_turbo_rest = 0.0
		if _turbo_run >= TURBO_PUTS_OUT_FIRE and burn_time > 0.0: # the rush of air blows the flames out
			burn_time = 0.0
			_burn_fx.on = false
			if is_player:
				notice.emit(self, "FIRE OUT")
	else:
		_turbo_run = 0.0
		_turbo_rest += dt
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
		# Back on its wheels: stop the roll, or it carries on over onto the other side (round 7).
		var w0 := state.angular_velocity
		state.angular_velocity = Vector3(0.0, w0.y * 0.5, 0.0)
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


func _landed(fall_speed: float) -> void:
	if is_dead:
		return
	var k := clampf((fall_speed - 7.0) / 18.0, 0.0, 1.0)
	GameFeel.play("land_thud", global_position + Vector3.UP * 0.5, get_parent(), lerpf(-12.0, 0.0, k), lerpf(1.15, 0.85, k) / sqrt(weight), true)
	FxKit.dust_ring(get_parent(), global_position, 0.6 + 0.8 * k)
	_jolt += Vector3(0.0, -0.08 - 0.14 * k, 0.0)
	if is_player:
		GameFeel.shake(global_position, 0.1 + 0.35 * k, 30.0)


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
			_ram(other as Vehicle, _prev_velocity, n, state.get_contact_collider_position(k))
		elif other != null and other.has_method("vehicle_contact"):
			# Breakables (stands, glass, palms) shatter and barely slow the car.
			if other.vehicle_contact(self, _prev_velocity):
				state.linear_velocity = Vector3(_prev_velocity.x, state.linear_velocity.y, _prev_velocity.z) * 0.95
			elif absf(n.y) < 0.55:
				_wall_hit(state, n)
		elif absf(n.y) < 0.55 and not _ground_contact(state, k, other):
			_wall_hit(state, n)


## The terrain touched low on the body where the ground itself is drivable (a slope, a hill side,
## the crater): not a wall, whatever sideways normal the solver reported (round 7, the owner's
## invisible walls). The battleground's edge stays a wall: there the ground is a cliff.
func _ground_contact(state: PhysicsDirectBodyState3D, k: int, other: Object) -> bool:
	if not (other is Node and (other as Node).is_in_group(&"ground")):
		return false
	var at := state.get_contact_collider_position(k)
	if (state.transform.affine_inverse() * at).y > BODY_CLEARANCE + 0.7:
		return false # high on the body: a real wall
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 1.5, at + Vector3.DOWN * 1.0, 1)
	q.exclude = [get_rid()]
	var r := state.get_space_state().intersect_ray(q)
	return not r.is_empty() and (r.normal as Vector3).y > 0.6 and absf((r.position as Vector3).y - at.y) < 0.7


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
	if impact > 10.0: # walls hurt a little (owner, round 6)
		take_damage((impact - 10.0) * WALL_DAMAGE * (1.0 if into >= 0.82 else 0.5), null)
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


## Rams (owner, round 6): ramming is a real weapon. Every car has a ram power (Roster "ram", 1-10)
## and what part of each car takes the hit matters:
##   damage to the other = base x (my power / its power) x ATTACK[my part] x DEFENSE[its part]
## base = (closing speed - 8) x 0.9, max 45 per hit. A nose hits hard (1.0), a side or tail barely
## hits back (0.3); a side is soft (x1.6, the T-bone), a tail x1.3, a nose x1.0. So nose to nose the
## stronger car wins; a nose into a side wins unless the side's car is over ~2.3x stronger (Twister
## into Axel's side still loses). Once a second per pair; both cars' damage comes from one hit.
func _ram(other: Vehicle, before: Vector3, n: Vector3, at: Vector3) -> void:
	if other.is_dead:
		return
	var a := get_instance_id()
	var b := other.get_instance_id()
	var key := "%d:%d" % [mini(a, b), maxi(a, b)]
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_ram_pairs.get(key, -10.0)) < 1.0:
		return
	var closing := (before - other._prev_velocity).dot(-n)
	if closing < RAM_MIN_CLOSING:
		return
	_ram_pairs[key] = now
	var mine := hit_part(at)
	var its := other.hit_part(at)
	var base := (closing - RAM_MIN_CLOSING) * RAM_PER_MS
	var ratio := ram_power() / other.ram_power()
	var to_it := minf(RAM_MAX, base * ratio * float(RAM_ATTACK[mine]) * float(RAM_DEFENSE[its]))
	var to_me := minf(RAM_MAX, base / ratio * float(RAM_ATTACK[its]) * float(RAM_DEFENSE[mine]))
	last_ram = {"me": mine, "it": its, "to_it": to_it, "to_me": to_me}
	other.last_ram = {"me": its, "it": mine, "to_it": to_me, "to_me": to_it}
	other.take_damage(to_it, self)
	take_damage(to_me, other)
	other.hit_react(-n, to_it)
	hit_react(n, to_me)
	_ram_feel(other, at, n, closing, to_it, to_me)
	# Knock-back (round 7, owner: "no pushback after they get hit"). The loser is thrown off along the
	# hit, its tyres let go for a moment (it slides, it doesn't grip back in line), and a hit on its
	# side or tail spins it. The winner keeps going but loses most of its speed into the hit.
	var share := to_it / maxf(to_it + to_me, 0.01)
	var travel := Vector3(before.x - other._prev_velocity.x, 0.0, before.z - other._prev_velocity.z)
	var line := travel.normalized() if travel.length() > 1.0 else -n
	var heavier := clampf(weight / other.weight, 0.6, 1.6) # a truck throws a bike further than the reverse
	var throw_it := minf(RAM_THROW_MAX, closing * (0.45 + 0.55 * share) * heavier) * other.knockback
	other.push(line * throw_it + Vector3.UP * (1.5 + 3.5 * share))
	other._knock = maxf(other._knock, KNOCK_TIME * (0.4 + 0.6 * share))
	if its != "front":
		var lever := other.global_basis.inverse() * (at - other.global_position)
		other.angular_velocity.y += clampf(lever.z * line.dot(other.global_basis.x) * 0.25, -1.0, 1.0) * (2.0 + 4.0 * share) * other.knockback
	var throw_me := minf(RAM_THROW_MAX, closing * (0.45 + 0.55 * (1.0 - share)) / heavier) * knockback
	push(-line * throw_me * 0.6 + Vector3.UP * (1.0 + 2.0 * (1.0 - share)))


## What a ram looks and sounds like (round 7, the owner's game-feel videos): sparks sprayed along the
## hit, metal bits, a white flash, a ring on big ones, a heavy layered crash, a short freeze of time
## when you are in it, a camera kick, the loser's body dips and both flash.
func _ram_feel(other: Vehicle, at: Vector3, n: Vector3, closing: float, to_it: float, to_me: float) -> void:
	var power := clampf((closing - RAM_MIN_CLOSING) / 26.0, 0.0, 1.0)
	var mid := at + Vector3.UP * 0.4
	FxKit.crash_burst(get_parent(), mid, -n if to_it >= to_me else n, power)
	var vol := lerpf(-8.0, 2.0, power)
	GameFeel.play("ram", mid, get_parent(), vol)
	GameFeel.play("ram_impact", mid, get_parent(), vol - 2.0, lerpf(1.15, 0.85, power), true) # synced: its peak is 0.44 s in
	if power > 0.5:
		GameFeel.play("explosion_big", mid, get_parent(), -10.0 + 6.0 * power, 0.55, true) # low thud under it
	GameFeel.shake(mid, 0.25 + 0.6 * power, 40.0)
	var loser := other if to_it >= to_me else self
	loser.squish(loser.global_position - at, 0.03 + 0.04 * power) # elastic dip, a few degrees (never goofy)
	if (is_player or other.is_player) and power > 0.25:
		GameFeel.hitstop(get_tree(), 0.05 + 0.07 * power, 0.05)


func ram_power() -> float:
	return float(stats.get("ram", 5.0))


## Which part of this car is at `at` (a world point): "front", "rear" or "side".
func hit_part(at: Vector3) -> String:
	var size: Vector3 = stats.get("size", Vector3(2.2, 1.8, 5.0))
	var p := global_basis.inverse() * (at - global_position)
	if p.z < -size.z * 0.3:
		return "front"
	if p.z > size.z * 0.3:
		return "rear"
	return "side"


## Knock the car (weapons, rams, recoil): a change of velocity.
func push(dv: Vector3) -> void:
	linear_velocity += dv
	if dv.length() > 4.0:
		_knock = maxf(_knock, KNOCK_TIME * 0.5)


## A hit lands (game feel): the body jolts away from it and big hits flash the car white.
func hit_react(dir: Vector3, amount: float) -> void:
	if is_dead:
		return
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length() > 0.01:
		_jolt += global_basis.inverse() * flat.normalized() * clampf(amount * 0.012, 0.05, 0.4)
	if shield_time > 0.0: # the field takes it: a hot patch and sparks instead of the white flash
		_shield_hit(dir)
		return
	if amount >= 4.0:
		if _flash_time <= 0.0:
			if _white == null:
				_white = StandardMaterial3D.new()
				_white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				_white.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				_white.albedo_color = Color(1.0, 0.97, 0.9, 0.6)
		_flash_time = maxf(_flash_time, 0.05 + minf(amount, 60.0) / 1200.0)
		# Body meshes only (round 17): flashing every mesh also whitened the soft ground shadow and
		# the fake headlight beams, and the end of the flash only clears the body, so after the first
		# hit a bright square stayed under the car for good.
		_apply_overlays()


## A blast throws the car (heavy cars less). flip 1 = about one full roll through the air away from
## the blast, smaller values tip it. Where it lands (wheels, side or roof) is up to the physics.
func blast_knock(push_v: Vector3, flip := 0.0, by_weight := true) -> void:
	var dv := push_v * knockback if by_weight else push_v
	linear_velocity += dv
	_knock = KNOCK_TIME
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


## Where the guns and launcher point: the body's real nose, pitch included (round 6: nose up on a
## ramp or in a jump and the missile climbs; HOLLYWOOD secret), kept within 35 degrees of level.
func aim_forward() -> Vector3:
	var f := -global_basis.z
	var flat := Vector3(f.x, 0.0, f.z)
	if flat.length() < 0.2 or global_basis.y.y < 0.3:
		return flat_forward() # on its side or roof: level
	var pitch := clampf(atan2(f.y, flat.length()), deg_to_rad(-35.0), deg_to_rad(35.0))
	return (flat.normalized() * cos(pitch) + Vector3.UP * sin(pitch)).normalized()


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
	if want_freeze:
		want_freeze = false
		want_move = "freeze"
	if want_move != "":
		energy_move(want_move)
		want_move = ""
	if frozen_time > 0.0 or flipped:
		want_fire_weapon = false
		_cancel_charge()
		return
	if shield_time > 0.0 and want_fire_weapon: # shield up: guns only (design 5.2)
		want_fire_weapon = false
		if is_player:
			GameFeel.ui("not_available", get_tree())
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
			_charge_hold = 0.0
			_charge_beeps = 0
		else:
			_fire_selected()
	if charging_id != "":
		if selected_weapon() != charging_id or ammo.get(charging_id, 0) <= 0:
			_cancel_charge()
		elif in_fire_weapon:
			charge_time = minf(charge_time + delta, charge_full(charging_id))
			_charge_hold += delta
			_charge_sound(delta)
			var melt := meltdown_at(charging_id)
			if melt > 0.0 and _charge_hold >= melt:
				_meltdown(charging_id)
		else:
			var full := charge_time >= charge_full(charging_id)
			_cancel_charge()
			_fire_selected(full)


## Energy moves (owner's combos, play-test 1; costs and times from design 5.2). Not while frozen or
## flipped. Each says so on the HUD when there isn't enough energy.
func energy_move(move: String) -> void:
	if is_dead or frozen_time > 0.0 or flipped:
		return
	var costs := {
		"jump": JUMP_COST, "freeze": float(stats.get("freeze_cost", FREEZE_COST)), "rear_freeze": REAR_FREEZE_COST,
		"shield": float(stats.get("shield_cost", SHIELD_COST)), "invisible": INVIS_COST, "mines": MINE_COST,
		"rear_attack": REAR_ATTACK_COST,
	}
	if move == "jump":
		want_jump = true # done by the physics step (needs the wheels on the ground)
		return
	if move == "secondary":
		if is_player:
			notice.emit(self, "SECONDARY WEAPON: NOT BUILT YET")
		return
	if not costs.has(move):
		return
	if energy < float(costs[move]):
		if is_player:
			notice.emit(self, "NOT ENOUGH ENERGY")
			GameFeel.ui("not_available", get_tree())
		return
	if (move == "freeze" or move == "rear_freeze" or move == "rear_attack") and shield_time > 0.0:
		return # shield up: no attacks but the guns
	spend_energy(float(costs[move]))
	match move:
		"freeze":
			launch("freeze", target)
		"rear_freeze":
			_launch_rear("rear_freeze", 1)
		"rear_attack":
			_launch_rear("rear_missile", 2)
		"shield":
			shield_time = SHIELD_TIME
			_show_shield(true)
			GameFeel.play("shield_activate", global_position + Vector3.UP, self, -2.0)
		"invisible":
			invisible_time = INVIS_TIME + CLOAK_IN # the sparks first, then 6 s unseen
			revealed_time = 0.0
			_cloak.play(CLOAK_IN)
			GameFeel.play("teleport", global_position + Vector3.UP, self, -6.0, 1.4)
			GameFeel.play("taser_fizzle", global_position + Vector3.UP, self, -8.0, 1.3)
			if is_player:
				notice.emit(self, "INVISIBLE")
		"mines":
			Mine.drop_energy(self)


## Out of the back: aimed at the nearest car behind (within 60 degrees and 80 m), else straight back.
func _launch_rear(id: String, count: int) -> void:
	_break_invisibility()
	var size: Vector3 = stats.get("size", Vector3(2.2, 1.8, 5.0))
	var back := -aim_forward()
	var lock: Vehicle = null
	var best := INF
	for node in get_tree().get_nodes_in_group("vehicles"):
		var o := node as Vehicle
		if o == self or o.is_dead or o.is_hidden():
			continue
		var to := o.global_position - global_position
		if to.length() < 80.0 and back.angle_to(to.normalized()) < deg_to_rad(60.0) and to.length() < best:
			best = to.length()
			lock = o
	for k in count:
		var side := global_basis.x * (0.6 * (k - (count - 1) * 0.5))
		var from := global_position + global_basis.z * (size.z * 0.5 + 0.8) + Vector3.UP * size.y * 0.6 + side
		Projectile.spawn(get_parent(), id, from, back, self, lock)
	GameFeel.play("launch_fire" if id == "rear_missile" else "launch_freeze", global_position, self, -2.0)


## Shield, invisibility and headlights, every tick.
func _energy_tick(delta: float) -> void:
	if shield_time > 0.0:
		shield_time -= delta
		if _shield_mat:
			_shield_mat.set_shader_parameter("strength", _shield_strength())
			_shield_mat.set_shader_parameter("car_inv", Projection(global_transform.affine_inverse()))
			_shield_hit_age += delta
			_shield_mat.set_shader_parameter("hit_age", _shield_hit_age)
		_shield_flare = maxf(0.0, _shield_flare - delta * 6.0)
		_shield_spark_cd -= delta
		if shield_time <= 0.0:
			_show_shield(false)
			GameFeel.play("shield_off", global_position + Vector3.UP, self, -4.0)
	if invisible_time > 0.0:
		invisible_time = maxf(0.0, invisible_time - delta)
	if _was_invisible and invisible_time <= 0.0: # time up or broken by firing: back, with sparks
		_cloak_back = CLOAK_OUT
		_cloak.play(CLOAK_OUT)
		GameFeel.play("taser_fizzle", global_position + Vector3.UP, self, -10.0, 1.5)
	_was_invisible = invisible_time > 0.0
	_cloak_back = maxf(0.0, _cloak_back - delta)
	revealed_time = maxf(0.0, revealed_time - delta)
	_cloak_look()
	# Headlights reveal invisible cars in the beam (owner: from the start; Calypso's clones later).
	if headlights_on:
		_headlight_t -= delta
		if _headlight_t <= 0.0:
			_headlight_t = 0.1
			var fwd := aim_forward()
			for node in get_tree().get_nodes_in_group("vehicles"):
				var o := node as Vehicle
				if o == self or o.is_dead or o.invisible_time <= 0.0:
					continue
				var to := o.aim_point() - (global_position + Vector3.UP)
				if to.length() < HEADLIGHT_RANGE and fwd.angle_to(to.normalized()) < HEADLIGHT_CONE:
					o.revealed_time = maxf(o.revealed_time, 0.25)


## Invisible and not revealed: no locks, no homing, the AI loses you past 12 m.
func is_hidden() -> bool:
	return invisible_time > 0.0 and invisible_time <= INVIS_TIME and revealed_time <= 0.0


## Round 16 (owner, TM2): while the sparks fly the body breaks up and fades; then it is gone for
## everyone, its own driver too (a headlight or a hit shows it faintly for a moment); coming back
## it fades in through the sparks.
func _cloak_look() -> void:
	var t := 0.0 # 1 = gone
	var gone := false
	if invisible_time > INVIS_TIME:
		var p := 1.0 - (invisible_time - INVIS_TIME) / CLOAK_IN
		t = clampf(p + randf_range(-0.3, 0.3) * p, 0.0, 0.97) # it flickers apart, not a smooth fade
	elif invisible_time > 0.0:
		if revealed_time > 0.0:
			t = 0.55 + randf_range(0.0, 0.15)
		else:
			gone = true
	elif _cloak_back > 0.0:
		var q := _cloak_back / CLOAK_OUT
		t = clampf(q + randf_range(-0.25, 0.25) * q, 0.0, 0.97)
	if model and model.visible == gone:
		model.visible = not gone
		if _blob:
			_blob.visible = not gone and not GraphicsSettings.high
	if absf(t - _invis_shown) > 0.01 or (t > 0.0 and not gone):
		_invis_shown = t
		_dissolve(t if not gone else 0.0)


## Round 16: the body breaks up in a pixel pattern (TM2's look; per-mesh transparency does nothing on
## the Compatibility renderer). Each surface gets a copy of its material with distance fade in
## pixel-dither mode, its fade band placed around the camera's distance so `amount` of the pixels
## drop out (0 = solid, 1 = gone). At 0 the copies are dropped again.
const DISSOLVE_BAND := 1000.0
var _dissolving := false

func _dissolve(amount: float) -> void:
	if amount <= 0.001:
		if _dissolving:
			_dissolving = false
			for mi in _flash_meshes:
				if is_instance_valid(mi):
					for i in mi.get_surface_override_material_count():
						mi.set_surface_override_material(i, null)
		return
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var d := cam.global_position.distance_to(global_position) if cam else 10.0
	var low := d - DISSOLVE_BAND * (1.0 - amount)
	for mi in _flash_meshes:
		if not is_instance_valid(mi) or mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m := mi.get_surface_override_material(i) as BaseMaterial3D
			if m == null or not m.has_meta("dissolve"):
				var src := mi.get_active_material(i) as BaseMaterial3D
				if src == null:
					continue
				m = src.duplicate() as BaseMaterial3D
				m.set_meta("dissolve", true)
				m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
				mi.set_surface_override_material(i, m)
			m.distance_fade_min_distance = low
			m.distance_fade_max_distance = low + DISSOLVE_BAND
	_dissolving = true


func _break_invisibility() -> void:
	if invisible_time > 0.0:
		invisible_time = 0.0
		if is_player:
			notice.emit(self, "VISIBLE AGAIN")


func _show_shield(on: bool) -> void:
	if on and _shield_mat == null:
		_shield_mat = ShaderMaterial.new()
		_shield_mat.shader = SHIELD_SHADER
		_shield_mat.set_shader_parameter("half_size", (stats.get("size", Vector3(2.2, 1.8, 5.0)) as Vector3) * 0.5)
	if _shield_mat:
		_shield_hit_age = 9.0
		_shield_mat.set_shader_parameter("strength", 0.0)
		_shield_mat.set_shader_parameter("hit_age", _shield_hit_age)
		_shield_mat.set_shader_parameter("car_inv", Projection(global_transform.affine_inverse()))
	_apply_overlays()
	if on:
		if _shield_hum == null:
			_shield_hum = GameFeel.loop("shield_loop", self, -10.0, 12.0)
		if _shield_hum:
			_shield_hum.play()
	elif _shield_hum:
		_shield_hum.stop()


## The shield field's brightness (round 17): switches on with a bright green pulse, holds,
## then blinks brighter and dimmer in its last SHIELD_BLINK seconds (the warning) and is gone.
func _shield_strength() -> float:
	var t_on := SHIELD_TIME - shield_time
	var s := clampf(t_on / 0.08, 0.0, 1.0) + 0.9 * maxf(0.0, 1.0 - t_on / 0.3)
	if shield_time < SHIELD_BLINK:
		var phase := fmod(shield_time / SHIELD_BLINK * 3.0, 1.0) # three blinks
		s = 1.55 if phase > 0.45 else 0.3
		s *= clampf(shield_time / 0.08, 0.0, 1.0)
	return s * (1.0 + _shield_flare * 0.25)


## A blocked hit (round 17, owner): the field turns hot yellow-lime where it landed and sparks fly
## off that spot. `dir` is the way the hit was travelling.
func _shield_hit(dir: Vector3) -> void:
	_shield_flare = 1.0
	var size: Vector3 = stats.get("size", Vector3(2.2, 1.8, 5.0))
	var half := size * 0.5
	var centre := Vector3(0.0, half.y, 0.0)
	var d := global_basis.inverse() * -dir # from the car towards where the hit came from
	if d.length() < 0.01:
		d = Vector3(randf_range(-1, 1), randf_range(0, 1), randf_range(-1, 1))
	d = d.normalized()
	var reach := 1e9 # walk out from the centre to the side of the car's box
	for i in 3:
		if absf(d[i]) > 0.001:
			reach = minf(reach, half[i] / absf(d[i]))
	var p := centre + d * reach
	_shield_hit_age = 0.0
	if _shield_mat:
		_shield_mat.set_shader_parameter("hit_pos", p)
		_shield_mat.set_shader_parameter("hit_age", 0.0)
	if _shield_spark_cd <= 0.0:
		_shield_spark_cd = 0.07
		FxKit.shield_sparks(get_parent(), global_transform * p, global_basis * d)


## The layer drawn over the car's own meshes, wheels included: the white hit flash, else the shield.
func _apply_overlays() -> void:
	var over: Material = null
	if _flash_time > 0.0:
		over = _white
	elif shield_time > 0.0 and _shield_mat:
		over = _shield_mat
	for mi in _flash_meshes:
		# Only the body: the soft ground shadow and the fake headlight beams carry their own override.
		if is_instance_valid(mi) and mi.material_override == null:
			mi.material_overlay = over


## Headlights on/off (owner: Circle / H). They light the way and show invisible cars in the beam.
func toggle_headlights() -> void:
	headlights_on = not headlights_on
	if headlights_on and model.find_children("HeadlightFx", "Node3D", false, false).is_empty():
		VehicleFx.headlight_beams(model, stats.get("size", Vector3(2.2, 1.8, 5.0)))
	VehicleFx.show_headlights(model, headlights_on)
	# The real light only on HIGH: on the Compatibility renderer a light draws every merged stage mesh
	# it touches a second time. LOW gets the painted beam instead (round 7).
	for l in model.find_children("*", "SpotLight3D", true, false):
		if (l as Node).is_in_group(GraphicsSettings.HEADLIGHT_GROUP):
			(l as Light3D).set_meta("on", headlights_on)
			(l as Light3D).visible = headlights_on and GraphicsSettings.high
	GameFeel.play("menu_select", global_position + Vector3.UP, self, -12.0, 1.6)


## Weapons with a charged shot (Napalm Cone): tap = normal shot, hold to the end = charged shot.
func _can_charge() -> bool:
	var id := selected_weapon()
	return id != "" and WeaponData.get_def(id).has("charge_time") and ammo.get(id, 0) > 0 and not _weapon_cooldowns.has(id)


static func charge_full(id: String) -> float:
	return float(WeaponData.get_def(id).get("charge_time", 2.0))


## Seconds of holding fire (from the press) after which a charged weapon melts down; 0 = never.
static func meltdown_at(id: String) -> float:
	var after := float(WeaponData.get_def(id).get("meltdown_after", -1.0))
	return charge_full(id) + after if after >= 0.0 else 0.0


## 0..1 while charging (HUD meter); 0 when not charging.
func charge_ratio() -> float:
	return clampf(charge_time / charge_full(charging_id), 0.0, 1.0) if charging_id != "" else 0.0


## Owner, round 10: a charge held too long melts down. No shot, no ammo lost, but the weapon is
## locked for `meltdown_lock` seconds (the HUD shows a ban sign over its slot). A charged cone is
## for the short window you made (a freeze), not something to carry around all day.
func _meltdown(id: String) -> void:
	var d := WeaponData.get_def(id)
	_cancel_charge()
	var lock := float(d.get("meltdown_lock", 3.0))
	_weapon_cooldowns[id] = lock
	_locked[id] = lock
	notice.emit(self, "%s MELTDOWN" % String(d.get("label", id)).to_upper())
	var at := launch_point()
	GameFeel.play("taser_fizzle", at, self, 0.0, 0.8)
	FxKit.puff(get_parent(), at, 0.7)
	for k in 3:
		FxKit.spark(get_parent(), at, (Vector3.UP + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))).normalized())
	GameFeel.flash(get_parent(), at, 1.2, Color(1.0, 0.6, 0.2), 0.1)
	if is_player:
		GameFeel.ui("not_available", get_tree())
		GameFeel.shake(at, 0.15)
	weapons_changed.emit(self)


## Seconds this weapon is still locked after a meltdown (0 = usable). For the HUD.
func locked_left(id: String) -> float:
	return float(_locked.get(id, 0.0))


func _cancel_charge() -> void:
	charging_id = ""
	charge_time = 0.0
	_charge_hold = 0.0
	_charge_beeps = 0
	if is_instance_valid(_charge_hum):
		_charge_hum.queue_free()
	_charge_hum = null


## Charging sound (owner, round 6): a tap makes no sound. Held, five beeps climb in pitch
## ("pew, Pew, PEw, PEW, PEW") until the shot is full; held past full, a humming buzz that keeps
## going and climbs until you let go or it melts down.
func _charge_sound(delta: float) -> void:
	if not is_player:
		return
	var full := charge_full(charging_id)
	var start := CHARGE_SILENT
	var step := (full - start) / 5.0
	while _charge_beeps < 5 and charge_time >= start + step * _charge_beeps:
		GameFeel.play("charge_up", launch_point(), self, -6.0 + _charge_beeps * 1.0, 1.0 + 0.16 * _charge_beeps)
		_charge_beeps += 1
	if charge_time >= full:
		# Owner, round 10: the full charge keeps humming for as long as it is held (it used to fade to
		# silence), climbing in pitch as the meltdown nears.
		var melt := meltdown_at(charging_id)
		if melt <= 0.0:
			melt = full + 1.0
		var near := clampf((_charge_hold - full) / maxf(melt - full, 0.1), 0.0, 1.0)
		if _charge_hum == null:
			_charge_hum = GameFeel.loop("taser_loop", self, -3.0, 10.0)
			if _charge_hum:
				_charge_hum.play()
		if is_instance_valid(_charge_hum):
			_charge_hum.volume_db = lerpf(-4.0, 1.0, near)
			_charge_hum.pitch_scale = lerpf(1.4, 2.3, near * near)


## The round shadow sits on the ground under the car, fading as the car rises.
func _place_blob() -> void:
	if model and not model.visible: # invisible (round 16): no shadow either
		_blob.visible = false
		return
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
	_break_invisibility()
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
	_break_invisibility()
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
	_break_invisibility()
	var from := launch_point()
	var dir := aim_forward()
	var homing := float(WeaponData.get_def(id).get("homing", 0.0)) > 0.0
	if is_instance_valid(lock) and not lock.is_dead:
		var to_t := lock.aim_point() - from
		# Start roughly toward the target so homing doesn't have to U-turn. Round 12 (owner): only
		# homing weapons; straight ones (power) leave along the nose, or they looked half-homing.
		if homing and dir.angle_to(to_t.normalized()) < deg_to_rad(60):
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
	var cap := int(WeaponData.get_def(id).get("max_ammo", 0))
	if cap > 0 and id != special_id:
		ammo[id] = mini(ammo[id], cap) # round 12 (owner): homing/fire 10, power 8, napalm/remote 6, zoomy/SAT 3
	weapons_changed.emit(self)


## Closest live enemy in front; falls back to the closest one anywhere in range.
func find_target() -> Vehicle:
	var best: Vehicle = null
	var best_score := INF
	var fwd := flat_forward()
	for node in get_tree().get_nodes_in_group("vehicles"):
		var v := node as Vehicle
		if v == self or v.is_dead or v.is_hidden():
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
	if shield_time > 0.0:
		GameFeel.play("shield_impact", global_position + Vector3.UP, self, -4.0)
		_shield_flare = 1.0 # the field brightens (the hot patch and sparks come from hit_react)
		return
	if invisible_time > 0.0:
		revealed_time = maxf(revealed_time, 0.5) # a hit shows where you are for a moment
	health -= amount
	if attacker and attacker != self:
		last_attacker = attacker
	if frozen_time > 0.0 and amount >= FREEZE_BREAK:
		_unfreeze() # the ice is smashed open (shards and the crash come from _unfreeze)
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
	if is_dead or grit_time > 0.0 or invulnerable_time > 0.0 or shield_time > 0.0:
		return false
	var was := frozen_time > 0.0
	frozen_time = maxf(frozen_time, seconds)
	_ice.visible = true
	if not was:
		# Impact beat on the car (juice guide): the TM freeze crackle and the ice growing over the body
		# with a little overshoot, white flash under it.
		GameFeel.play("freeze_hit", global_position + Vector3.UP, get_parent(), 0.0, 1.0, true)
		_ice.scale = Vector3.ONE * 0.7
		var tw := _ice.create_tween()
		tw.tween_property(_ice, "scale", Vector3.ONE * 1.06, 0.12).set_ease(Tween.EASE_OUT)
		tw.tween_property(_ice, "scale", Vector3.ONE, 0.1)
		hit_react(Vector3.ZERO, 10.0)
	return true


## The ice comes off (time's up, or smashed by a hit): it bursts into shards with an icy crash.
func _unfreeze() -> void:
	frozen_time = 0.0
	_ice.visible = false
	grit_time = GRIT_TIME
	var size: Vector3 = stats.get("size", Vector3(2.2, 1.8, 5.0))
	var c := global_position + global_basis.y * size.y * 0.5
	GameFeel.play("ice_break", c, get_parent(), 0.0, 1.0, true)
	FxKit.shatter(get_parent(), c, (global_basis * (size * 0.5)).abs(), Vector3.UP, 4.0, Color(0.75, 0.95, 1.0), true)
	GameFeel.flash(get_parent(), c, 2.0, Color(0.8, 0.95, 1.0), 0.08)
	FxKit.puff(get_parent(), c, 0.6)


## Burning: 3 damage a second. A new flame renews the timer, it doesn't stack.
func ignite(seconds: float, by: Vehicle) -> void:
	if is_dead or invulnerable_time > 0.0 or shield_time > 0.0:
		return
	if burn_time <= 0.0:
		GameFeel.play("ignite", global_position + Vector3.UP, get_parent(), -3.0)
	burn_time = maxf(burn_time, seconds)
	_burn_source = by
	_burn_fx.on = true


func _update_damage_fx() -> void:
	var r := health / max_health
	_smoke.emitting = r < 0.5
	_fire.on = r < 0.25


func _die() -> void:
	var airborne := not is_on_floor() # owner, round 17: died in the air = the driver is blasted out
	is_dead = true
	frozen_time = 0.0
	burn_time = 0.0
	_burn_fx.on = false
	_fx.stop()
	_ice.visible = false
	_visual.visible = true
	# Owner, round 18: the car blows apart completely. Nothing is left but a patch of fire on the ground
	# and a scorch; the driver runs out of the fire at once (no waiting for a wreck to settle).
	var world := get_parent()
	var spot := Specials.ground_below(world, global_position + Vector3.UP)
	FxKit.explosion(world, global_position + Vector3.UP * 1.2, 3.4)
	BurningDriver.spawn_for(self, airborne) # the driver runs out burning (or is thrown out); they scream
	GameFeel.scorch(world, spot, maxf(stats.size.x, 2.0) * 1.1)
	for snd: AudioStreamPlayer3D in [_gun_snd, _skid_snd]:
		if snd:
			snd.stop()
	for layer: String in _eng:
		(_eng[layer] as AudioStreamPlayer3D).stop()
	_charge_fx = null
	model.visible = false
	_blob.visible = false
	_blob.remove_from_group(GraphicsSettings.BLOB_GROUP) # a graphics switch must not bring it back
	_smoke.emitting = false
	_fire.on = false
	_pyre.on = true
	# The body stays only as the place the camera watches (round 12: on the wreck for the 6 s): frozen on
	# the ground under where it died, touching nothing.
	set_deferred("freeze_mode", RigidBody3D.FREEZE_MODE_STATIC)
	set_deferred("freeze", true)
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	var yaw := global_rotation.y # upright where it died, whatever way it was tumbling: the fire stands up
	set_deferred("global_transform", Transform3D(Basis(Vector3.UP, yaw), spot))
	destroyed.emit(self, last_attacker)


# ---------------------------------------------------------------- visuals

func _animate(delta: float) -> void:
	_fx.update(delta, self, velocity, _boosting, in_handbrake and is_on_floor() and absf(speed) > 8.0)
	_update_sounds(delta)
	if _flash_time > 0.0:
		_flash_time -= delta
		if _flash_time <= 0.0:
			_apply_overlays()
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
