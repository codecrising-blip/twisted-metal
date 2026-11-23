class_name Sinner
extends CharacterBody3D
## Brimstone's Sinner Bomber (round 28, design 01 ch 10, stronger than Black's): a pale, hooded sinner with
## dynamite strapped to his back is thrown out of the bed "throw" m ahead, lands and RUNS at the lock at
## run_speed (x the game's speed scale), sliding along walls and cutting inside corners. He clings to the
## first enemy car he reaches (hood or roof) and blows after "fuse" s: damage and a small throw. The driver
## shakes him off with a jump, a wall hit over shake_wall m/s or a 150-degree handbrake slide: he drops
## behind and blows for shake_damage. He can be shot down (hp: ~9 rounds) or burnt by Thumper's flame, and
## pops anyway when his run time is up (pop_damage in pop_radius). Projectiles hit him on layer 64.

enum State { FLY, RUN, CLING, DROP }

const LAYER := 64
const GRAVITY := 30.0
const TURN := 3.2 # rad/s: how fast he swings round toward his car (round 29: smooth arcs)
const ACCEL := 45.0 # m/s²: building up to his sprint

var owner_car: Vehicle
var lock: Vehicle
var def: Dictionary
var state := State.FLY
var victim: Vehicle
var _hp := 5.0
var _t := 0.0
var _fuse := 0.0
var _offset := Vector3.ZERO
var _model: Node3D
var _anim: AnimationPlayer
var _fuse_snd: AudioStreamPlayer3D
var _spark := 0.0
var _scan := 0.0
var _done := false
var _victim_floor := true


static func start(v: Vehicle, d: Dictionary) -> Sinner:
	var s := Sinner.new()
	s.owner_car = v
	s.def = d
	s.lock = v.target if is_instance_valid(v.target) and not v.target.is_dead else null
	v.get_parent().add_child(s)
	var size: Vector3 = v.stats.get("size", Vector3(2.2, 1.8, 5.5))
	var bed: Vector3 = v.model.get_meta("sinner", Vector3(0, size.y * 0.75, size.z * 0.25))
	s.global_position = v.model.to_global(bed)
	var fwd := v.flat_forward()
	var vy := 8.0
	var air := 2.0 * vy / GRAVITY
	s.velocity = fwd * (float(d.get("throw", 10.0)) / air) + Vector3(v.linear_velocity.x, 0.0, v.linear_velocity.z) + Vector3.UP * vy
	s.look_at(s.global_position + fwd, Vector3.UP)
	GameFeel.play("pedestrian_scream", s.global_position, v.get_parent(), float(d.get("sound_db", 0.0)) - 2.0, randf_range(1.05, 1.2))
	GameFeel.play("launch_napalm", s.global_position, v.get_parent(), -10.0, 1.2, true)
	var plate := v.model.find_child("bed_plate", true, false) as Node3D
	if plate: # round 29 (owner's sheet): the well's floor slams up and flings him out
		var tw := plate.create_tween()
		tw.tween_property(plate, "position:y", 0.42, 0.08).set_ease(Tween.EASE_OUT)
		tw.tween_property(plate, "position:y", 0.0, 0.35).set_delay(0.12).set_ease(Tween.EASE_IN_OUT)
		GameFeel.play("crash", plate.global_position, v, -10.0, 1.6)
	return s


func _ready() -> void:
	collision_layer = LAYER
	collision_mask = 1 # the world: he slides along walls
	add_to_group(&"sinners")
	_hp = float(def.get("hp", 5.0))
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	shape.shape = cap
	shape.position = Vector3(0, 0.9, 0)
	add_child(shape)
	floor_snap_length = 0.6
	_model = _body()
	add_child(_model)
	_anim = _model.get_meta("anim")
	_anim.play(_run_clip())
	_anim.speed_scale = 1.5 # round 29 (owner): a calm, driven sprint, not arms flailing twelve times a second
	_fuse_snd = GameFeel.loop("taser_loop", self, -10.0, 8.0)
	if _fuse_snd:
		_fuse_snd.pitch_scale = 2.6 # a hissing, spitting fuse
		_fuse_snd.play()


## The burnt-driver dummy (driver_m.glb) made a sinner: pale skin, a burlap hood, a bundle of dynamite on
## his back with a lit fuse, a loop of chain round his waist.
func _body() -> Node3D:
	var scene: PackedScene = load("res://assets/models/driver_m.glb")
	var m := scene.instantiate() as Node3D
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.74, 0.68, 0.6)
	skin.roughness = 0.75
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = skin
	var anim: AnimationPlayer = m.find_children("*", "AnimationPlayer", true, false)[0]
	for a in anim.get_animation_list():
		anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	m.set_meta("anim", anim)
	var sk: Skeleton3D = m.find_children("*", "Skeleton3D", true, false)[0]
	var burlap := MatKit.paint(Color(0.42, 0.33, 0.22), 0.4, 0.0, 0.6, 0.6, 0.1, 81)
	var red := MatKit.paint(Color(0.55, 0.08, 0.05), 0.4, 0.0, 0.4, 0.6, 0.3, 82)
	var iron := MatKit.steel(Color(0.2, 0.2, 0.2), 0.6)
	var head := BoneAttachment3D.new()
	head.bone_name = "head"
	sk.add_child(head)
	var mb := MeshBuilder.new()
	mb.sphere(burlap, 0.17, Transform3D(Basis().scaled(Vector3(1.0, 1.25, 1.05)), Vector3(0, 0.1, 0)), 10, 7)
	mb.cylinder(burlap, 0.12, 0.12, Transform3D(Basis(), Vector3(0, -0.06, 0)), 8, 0.14) # the sack tied at the neck
	mb.commit(head, false)
	var chest := BoneAttachment3D.new()
	chest.bone_name = "chest"
	sk.add_child(chest)
	var back := MeshBuilder.new()
	for k in 5:
		back.cylinder(red, 0.045, 0.42, Transform3D(Basis(), Vector3(-0.1 + k * 0.05, 0.0, 0.17)), 8)
	back.box(iron, Vector3(0.3, 0.04, 0.12), Transform3D(Basis(), Vector3(0, 0.12, 0.16)), 0.0)
	back.box(iron, Vector3(0.3, 0.04, 0.12), Transform3D(Basis(), Vector3(0, -0.12, 0.16)), 0.0)
	back.commit(chest, false)
	var hips := BoneAttachment3D.new()
	hips.bone_name = "hips"
	sk.add_child(hips)
	var chain := MeshBuilder.new()
	chain.torus(iron, 0.2, 0.025, Transform3D(Basis(), Vector3(0, 0.05, 0)), 14, 5)
	chain.commit(hips, false)
	m.set_meta("fuse", chest)
	return m


func _physics_process(delta: float) -> void:
	if _done:
		return
	_t += delta
	_spark -= delta
	if _spark <= 0.0: # the lit fuse spits sparks (it shows him in the dark)
		_spark = 0.12
		var fuse: Node3D = _model.get_meta("fuse")
		FxKit.spark(get_parent(), fuse.global_position + fuse.global_basis.z * 0.2 + Vector3.UP * 0.25, Vector3.UP)
	match state:
		State.FLY:
			velocity.y -= GRAVITY * delta
			move_and_slide()
			if is_on_floor() and _t > 0.15:
				state = State.RUN
				_t = 0.0
				GameFeel.play("land_thud", global_position, get_parent(), -10.0, 1.4)
		State.RUN:
			_run(delta)
		State.CLING:
			_cling(delta)
		State.DROP:
			velocity.y -= GRAVITY * delta
			move_and_slide()
			if _t > 0.6 or (is_on_floor() and _t > 0.25):
				_blow(float(def.get("shake_damage", 10.0)), 4.0, null)


func _run(delta: float) -> void:
	if _t > float(def.get("run_time", 6.0)):
		_blow(float(def.get("pop_damage", 12.0)), float(def.get("pop_radius", 3.0)), null)
		return
	_scan -= delta
	if _scan <= 0.0:
		_scan = 0.4
		if not is_instance_valid(lock) or lock.is_dead or lock.is_hidden():
			lock = _nearest()
	var speed := float(def.get("run_speed", 26.0)) * Roster.SPEED_SCALE * 0.85
	var dir := -global_basis.z
	if is_instance_valid(lock):
		var to := lock.global_position - global_position
		to.y = 0.0
		if to.length() > 0.5:
			dir = to.normalized()
	# Round 29 (owner: "too chaotic"): he swings round in a smooth arc (TURN rad/s) and builds up speed,
	# instead of snapping to the target every frame; the body turns with his path, eased.
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var cur := flat.normalized() if flat.length() > 0.5 else dir
	var ang := cur.signed_angle_to(dir, Vector3.UP)
	cur = cur.rotated(Vector3.UP, clampf(ang, -TURN * delta, TURN * delta))
	var spd := move_toward(flat.length(), speed, ACCEL * delta)
	flat = cur * spd
	velocity = Vector3(flat.x, velocity.y - GRAVITY * delta, flat.z)
	move_and_slide()
	if flat.length() > 1.0:
		var face := Basis.looking_at(flat, Vector3.UP)
		global_basis = global_basis.slerp(face, minf(1.0, delta * 8.0)).orthonormalized()
	for node in get_tree().get_nodes_in_group("vehicles"):
		var o := node as Vehicle
		if o == owner_car or o.is_dead:
			continue
		var local := o.global_transform.affine_inverse() * (global_position + Vector3.UP * 0.9)
		var size: Vector3 = o.stats.get("size", Vector3(2.2, 1.8, 5.0))
		if absf(local.x) < size.x * 0.5 + 0.6 and absf(local.z) < size.z * 0.5 + 0.6 and local.y > -0.5 and local.y < size.y + 1.0:
			_grab(o)
			return


## The plain sprint (round 29) when the dummy has it, else the old burning run.
func _run_clip() -> String:
	return "sprint" if _anim.has_animation("sprint") else "run_burn"


func _nearest() -> Vehicle:
	var best: Vehicle = null
	var best_d := 70.0
	for node in get_tree().get_nodes_in_group("vehicles"):
		var o := node as Vehicle
		if o == owner_car or o.is_dead or o.is_hidden():
			continue
		var d := o.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = o
	return best


## On the car: on its hood (or its roof when it is low), facing the driver, holding on.
func _grab(o: Vehicle) -> void:
	state = State.CLING
	victim = o
	_t = 0.0
	_fuse = 0.0
	collision_mask = 0
	var hood: Vector2 = o.stats.get("hood", Vector2(1.2, -1.4))
	_offset = Vector3(0.0, hood.x + 0.05, hood.y)
	_anim.play("kneel", 0.15)
	_anim.speed_scale = 1.6
	if o.has_signal("wall_slammed"):
		o.wall_slammed.connect(_on_wall)
	GameFeel.play("land_thud", global_position, get_parent(), -4.0, 1.2)
	GameFeel.play("pedestrian_scream", global_position, get_parent(), -2.0, 0.95)
	if o.is_player:
		o.notice.emit(o, "SINNER ON YOU - JUMP, SLAM A WALL OR SPIN TO SHAKE HIM")


func _cling(delta: float) -> void:
	var o := victim
	if not is_instance_valid(o) or o.is_dead:
		_shake_off()
		return
	global_transform = o.global_transform * Transform3D(Basis(Vector3.UP, PI), _offset)
	_fuse += delta
	# Shaken off: a jump (wheels off and going up), a big slide (a handbrake U-turn).
	var up := o.linear_velocity.y
	if not o.is_on_floor() and up > 4.0 and _t > 0.15:
		_shake_off()
		return
	if o.slide_degrees() > 150.0:
		_shake_off()
		return
	if _fuse >= float(def.get("fuse", 2.0)):
		var dmg := float(def.get("damage", 40.0)) * WeaponData.DAMAGE_SCALE
		o.take_damage(dmg, owner_car)
		o.hit_react(Vector3.UP, dmg)
		o.blast_knock(Vector3.UP * 5.0 + o.global_basis.x * randf_range(-3.0, 3.0), 0.15, true)
		if o.is_player and GameFeel.camera:
			GameFeel.camera.add_shake(float(def.get("shake", 0.5)))
		_blow(0.0, 0.0, o)


func _on_wall(car: Vehicle, impact: float) -> void:
	if state == State.CLING and car == victim and impact > float(def.get("shake_wall", 15.0)):
		_shake_off()


func _shake_off() -> void:
	if state != State.CLING:
		return
	state = State.DROP
	_t = 0.0
	var o := victim
	if is_instance_valid(o):
		if o.wall_slammed.is_connected(_on_wall):
			o.wall_slammed.disconnect(_on_wall)
		velocity = o.linear_velocity * 0.4 - o.flat_forward() * 6.0 + Vector3.UP * 3.0
		if o.is_player:
			o.notice.emit(o, "SHOOK HIM OFF")
	victim = null
	collision_mask = 1
	_anim.play(_run_clip(), 0.2)
	_anim.speed_scale = 1.5


## Shot or burnt while he runs.
func projectile_hit(damage: float, _shooter: Vehicle) -> void:
	if _done or state == State.CLING:
		return
	_hp -= damage
	if _hp <= 0.0:
		_blow(float(def.get("pop_damage", 12.0)), float(def.get("pop_radius", 3.0)), null)


func _blow(damage: float, radius: float, on_car: Vehicle) -> void:
	if _done:
		return
	_done = true
	var world := get_parent()
	var at := global_position + Vector3.UP * 0.8
	if is_instance_valid(victim) and victim.wall_slammed.is_connected(_on_wall):
		victim.wall_slammed.disconnect(_on_wall)
	FxKit.explosion(world, at, 1.6 if on_car else 1.0, Color(1.0, 0.5, 0.15))
	GameFeel.flash(world, at, 2.5, Color(1.0, 0.75, 0.4), 0.1)
	GameFeel.scorch(world, global_position + Vector3.UP * 0.2, 2.0)
	if damage > 0.0:
		Specials.blast(world, at, radius, damage, owner_car)
	if on_car and (on_car.is_player or (is_instance_valid(owner_car) and owner_car.is_player)):
		GameFeel.hitstop(get_tree(), 0.06, 0.05)
	queue_free()
